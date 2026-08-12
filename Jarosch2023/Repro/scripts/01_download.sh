#!/usr/bin/env bash
# Step 1 — fetch PRJEB60178 (Jarosch et al. 2023) single-end Ion Torrent reads
# from ENA.
#
# Run on the HOST (not in the container) — it only needs curl.
#   bash scripts/01_download.sh
#
# Safe to re-run: files whose MD5 already matches are skipped, so repeated runs
# fill in whatever is still missing. EBI's endpoint drops connections fairly
# often, so each file gets several attempts and a failure never aborts the run.
#
# Outputs:
#   data/raw/<run>.fastq.gz        one file per run (Ion Torrent = single-end)
#   data/raw/filereport.tsv        ENA run manifest
#   logs/01_download.log
#   results/01_download_status.tsv per-run outcome
set -uo pipefail          # deliberately NOT -e: see retry logic below

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="${HERE}/data/raw"
LOG="${HERE}/logs/01_download.log"
STATUS="${HERE}/results/01_download_status.tsv"
PROJECT="PRJEB60178"
ATTEMPTS="${ATTEMPTS:-5}"

mkdir -p "${RAW}" "${HERE}/logs" "${HERE}/results"
exec > >(tee "${LOG}") 2>&1

# macOS has `md5`, Linux has `md5sum`.
md5of() {
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | cut -d' ' -f1
  else
    md5 -q "$1"
  fi
}

echo "=== ENA fetch: ${PROJECT} ==="
date

REPORT="${RAW}/filereport.tsv"
if ! curl -sS --retry 3 --retry-delay 3 -o "${REPORT}" \
  "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${PROJECT}&result=read_run&fields=run_accession,sample_accession,sample_alias,instrument_model,library_layout,read_count,base_count,fastq_ftp,fastq_md5,fastq_bytes&format=tsv&download=false"; then
  echo "ERROR: could not retrieve the ENA filereport." >&2
  exit 1
fi

N=$(( $(wc -l < "${REPORT}") - 1 ))
echo "Runs listed in project: ${N}"
if [[ "${N}" -lt 1 ]]; then
  echo "ERROR: empty filereport. Check network / accession." >&2
  exit 1
fi

echo
echo "Instrument / layout summary:"
awk -F'\t' 'NR>1 {print $4"\t"$5}' "${REPORT}" | sort | uniq -c

# Restrict to the curated run list for this study, if present.
ACC_LIST="${HERE}/../RawData/run_accessions.txt"
KEEP=""
if [[ -f "${ACC_LIST}" ]]; then
  KEEP="$(mktemp)"
  grep -v '^[[:space:]]*$' "${ACC_LIST}" | tr -d '\r' | sort -u > "${KEEP}"
  echo
  echo "Filtering to $(wc -l < "${KEEP}" | tr -d ' ') accessions from RawData/run_accessions.txt"
fi

# --------------------------------------------------------------------------
# Download one file, with retries. Returns 0 on verified success.
# --------------------------------------------------------------------------
fetch_one() {
  local url="$1" dest="$2" want="$3" name
  name="$(basename "${dest}")"

  # Already present and correct?
  if [[ -s "${dest}" ]]; then
    local have; have="$(md5of "${dest}")"
    if [[ -z "${want}" || "${have}" == "${want}" ]]; then
      echo "  ok (cached)  ${name}"
      return 0
    fi
    echo "  stale        ${name} (md5 mismatch) — refetching"
    rm -f "${dest}"
  fi

  local attempt
  for (( attempt = 1; attempt <= ATTEMPTS; attempt++ )); do
    # --http1.1 avoids the HTTP/2 "empty reply" that EBI returns intermittently.
    # --retry-all-errors makes curl itself retry transient non-HTTP failures.
    if curl -sS -L --http1.1 \
            --retry 3 --retry-delay 5 --retry-all-errors \
            --connect-timeout 30 --max-time 1800 \
            --speed-limit 1024 --speed-time 120 \
            -o "${dest}.part" "${url}"; then
      mv -f "${dest}.part" "${dest}"
      local have; have="$(md5of "${dest}")"
      if [[ -z "${want}" || "${have}" == "${want}" ]]; then
        echo "  got          ${name} (attempt ${attempt})"
        return 0
      fi
      echo "  !! md5 mismatch ${name}: got ${have}, want ${want} (attempt ${attempt})"
      rm -f "${dest}"
    else
      echo "  !! transfer failed ${name} (attempt ${attempt}/${ATTEMPTS})"
      rm -f "${dest}.part"
    fi
    (( attempt < ATTEMPTS )) && sleep $(( attempt * 5 ))
  done

  echo "  XX GAVE UP   ${name} after ${ATTEMPTS} attempts"
  return 1
}

# --------------------------------------------------------------------------
# Main loop. Reads from a temp file rather than a pipe so counters survive,
# and so nothing downstream can swallow stdin.
# --------------------------------------------------------------------------
echo
echo "Downloading FASTQs into ${RAW}"
echo

MANIFEST="$(mktemp)"
awk -F'\t' 'NR>1 {print $1"\t"$8"\t"$9}' "${REPORT}" > "${MANIFEST}"

printf "run\tstatus\tfile\n" > "${STATUS}"
n_ok=0; n_fail=0; n_skip=0
failed_runs=()

while IFS=$'\t' read -r run ftp md5; do
  [[ -z "${run}" ]] && continue

  if [[ -n "${KEEP}" ]] && ! grep -qx "${run}" "${KEEP}"; then
    n_skip=$(( n_skip + 1 ))
    printf "%s\tnot_in_curated_list\t-\n" "${run}" >> "${STATUS}"
    continue
  fi

  if [[ -z "${ftp}" ]]; then
    echo "  !! ${run}: no fastq_ftp entry"
    n_fail=$(( n_fail + 1 )); failed_runs+=("${run}")
    printf "%s\tno_fastq_url\t-\n" "${run}" >> "${STATUS}"
    continue
  fi

  # Ion Torrent runs are single-end, so this is normally one path; semicolons
  # would indicate paired files. Handle both.
  IFS=';' read -ra URLS <<< "${ftp}"
  IFS=';' read -ra MD5S <<< "${md5}"

  run_ok=1
  for i in "${!URLS[@]}"; do
    url="${URLS[$i]}"
    fname="$(basename "${url}")"
    if fetch_one "https://${url#ftp://}" "${RAW}/${fname}" "${MD5S[$i]:-}"; then
      printf "%s\tok\t%s\n" "${run}" "${fname}" >> "${STATUS}"
    else
      run_ok=0
      printf "%s\tFAILED\t%s\n" "${run}" "${fname}" >> "${STATUS}"
    fi
  done

  if [[ "${run_ok}" -eq 1 ]]; then
    n_ok=$(( n_ok + 1 ))
  else
    n_fail=$(( n_fail + 1 )); failed_runs+=("${run}")
  fi
done < "${MANIFEST}"

rm -f "${MANIFEST}"
[[ -n "${KEEP}" ]] && rm -f "${KEEP}"

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
echo
echo "=========================================="
echo "  runs downloaded/verified : ${n_ok}"
echo "  runs failed              : ${n_fail}"
echo "  runs skipped (not listed): ${n_skip}"
echo "  files on disk            : $(ls -1 "${RAW}"/*.fastq.gz 2>/dev/null | wc -l | tr -d ' ')"
echo "  total size               : $(du -sh "${RAW}" | cut -f1)"
echo "=========================================="

if [[ "${n_fail}" -gt 0 ]]; then
  echo
  echo "Failed runs:"
  printf '  %s\n' "${failed_runs[@]}"
  echo
  echo "EBI drops connections intermittently. Just re-run this script — verified"
  echo "files are skipped, so it will retry only what is missing:"
  echo "    bash scripts/01_download.sh"
  date
  exit 1
fi

echo
echo "All requested runs present and MD5-verified."
date
echo "=== done ==="
