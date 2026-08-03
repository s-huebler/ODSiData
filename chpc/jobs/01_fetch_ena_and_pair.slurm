#!/bin/bash
# =============================================================================
# 01_fetch_ena_and_pair.slurm — fetch + re-pair "split-run" paired-end studies.
#
# For studies deposited in ENA/SRA as TWO separate single-end runs per sample
# (one run = R1, the other = R2), both declared library_layout=SINGLE and often
# both carrying a "/1" header suffix — so nothing downstream can pair them.
# Liu2017 (ERP017899) is the motivating case: 158 runs = 79 samples x 2 runs.
#
# This job replaces the per-run array in 01_fetch.slurm with per-SAMPLE work:
#   1. group runs by a pair key (default sample_accession) from an ENA report,
#   2. download both mates of each sample,
#   3. decide which mate is forward vs reverse BY PRIMER SEQUENCE (deterministic;
#      no quality guessing) — the mate whose reads start with $PRIMER_F is R1,
#   4. clean the injected @ACCESSION.spot header prefix (record-safe), rewrite
#      the reverse mate's trailing /1 -> /2 so mates are distinguishable,
#   5. repair.sh (BBTools) re-syncs the pair and drops orphans,
#   6. write <key>_1.fastq / <key>_2.fastq straight into $WORK_BASE/$STUDY/RawData
#      — the exact layout make_manifest_paired.sh (02_import.slurm) expects.
#
# It is GENERAL: every study-specific value (primers, pair key, ftp column,
# report path) comes from the study file, so a future split-run dataset only
# needs its own primers and report.
#
# Run via chpc/submit.sh (which sets FETCH_JOB + submits WITHOUT --array).
# Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/Liu2017.sh chpc/jobs/01_fetch_ena_and_pair.slurm
#
# NOTE ON HEADERS (verify once per new study): the prefix-strip and /1->/2 steps
# assume the mates share a common original read name that ends in /1. This holds
# for the ENA fastqs of ERP017899. For a NEW study, inspect the first sample's
# two files (zcat | head) and confirm before trusting the whole run.
# =============================================================================
#SBATCH --job-name=ena-pair-fetch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=24:00:00
#SBATCH --output=chpc/logs/fetch_pair_%j.out
#SBATCH --error=chpc/logs/fetch_pair_%j.err

set -euo pipefail

# --- Load config + study params ---------------------------------------------
: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Liu2017.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

# BBTools repair.sh must be on PATH.
load_bbmap_env

# --- Required study-file parameters -----------------------------------------
: "${STUDY:?set STUDY in the study file}"
: "${PRIMER_F:?set PRIMER_F (forward primer) — used to orient the mates}"
: "${PRIMER_R:?set PRIMER_R (reverse primer) — used to cross-check orientation}"
# ENA filereport TSV: must contain run_accession, the pair key, and an ftp column.
ENA_REPORT="${ENA_REPORT:-$REPO_ROOT/$STUDY/RawData/ENA_samples.tsv}"
PAIR_KEY="${PAIR_KEY:-sample_accession}"   # column that is identical for the two mates
FTP_COL="${FTP_COL:-submitted_ftp}"        # column holding the download URL(s)
ORIENT_READS="${ORIENT_READS:-2000}"       # reads scanned per file to call orientation
MAX_RETRIES="${FETCH_MAX_RETRIES:-3}"
RETRY_DELAY="${FETCH_RETRY_DELAY:-60}"

[[ -f "$ENA_REPORT" ]] || { echo "ERROR: ENA report not found: $ENA_REPORT" >&2; exit 1; }

# --- Node-local temp --------------------------------------------------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

RAW_DIR="$WORK_BASE/$STUDY/RawData"
mkdir -p "$RAW_DIR"
FAILED_LOG="$WORK_BASE/$STUDY/failed_downloads.txt"

echo "==== ENA fetch + re-pair for $STUDY ===="
echo "Report   : $ENA_REPORT"
echo "Pair key : $PAIR_KEY   FTP col: $FTP_COL"
echo "Primers  : F=$PRIMER_F   R=$PRIMER_R"
echo "Output   : $RAW_DIR/<key>_1.fastq , <key>_2.fastq"

# --- IUPAC primer -> POSIX ERE ----------------------------------------------
# Degenerate bases become bracket classes. Inserted brackets contain only
# A/C/G/T, none of which are IUPAC codes, so substitutions never cascade.
iupac_regex() {
    echo "$1" | sed -e 's/M/[AC]/g' -e 's/R/[AG]/g' -e 's/W/[AT]/g' \
        -e 's/S/[CG]/g' -e 's/Y/[CT]/g' -e 's/K/[GT]/g' \
        -e 's/V/[ACG]/g' -e 's/H/[ACT]/g' -e 's/D/[AGT]/g' \
        -e 's/B/[CGT]/g' -e 's/N/[ACGT]/g'
}
RE_F="$(iupac_regex "$PRIMER_F")"
RE_R="$(iupac_regex "$PRIMER_R")"

# Count reads (of the first $ORIENT_READS) whose sequence starts with $2 (regex).
count_primer_hits() {
    local file="$1" pat="$2"
    awk -v pat="^$pat" -v max="$ORIENT_READS" '
        NR%4==2 { c++; if ($0 ~ pat) m++; if (c>=max) exit }
        END { print m+0 }' "$file"
}

# Record-safe header edits (only line 1 of each 4-line FASTQ record).
strip_accession_prefix() {   # @ERR1688232.1 <name>  ->  @<name>   (no-op if absent)
    awk 'NR%4==1 { sub(/^@[A-Za-z]+[0-9]+\.[0-9]+[[:space:]]+/, "@") } { print }' "$1"
}
rewrite_slash1_to_slash2() { # trailing /1 -> /2 on the header line (no-op if absent)
    awk 'NR%4==1 { sub(/\/1$/, "/2") } { print }' "$1"
}

# Download one run's FASTQ (handles ';'-separated links + optional .gz) to $2.
download_run() {
    local ftp_field="$1" out="$2" attempt=1
    local link; link="$(echo "$ftp_field" | cut -d ';' -f 1)"
    [[ "$link" == ftp://* || "$link" == http* ]] || link="ftp://$link"
    while (( attempt <= MAX_RETRIES )); do
        if wget -c -q -O "$out.dl" "$link"; then
            if [[ "$link" == *.gz ]]; then
                gunzip -c "$out.dl" > "$out" && rm -f "$out.dl" && return 0
            else
                mv "$out.dl" "$out" && return 0
            fi
        fi
        echo "    download attempt $attempt/$MAX_RETRIES failed for $link"
        (( attempt < MAX_RETRIES )) && sleep "$RETRY_DELAY"
        (( attempt++ ))
    done
    return 1
}

# --- Parse the report: emit "pairkey<TAB>run<TAB>ftp", sorted by key then run --
# Lower run accession lands first, but orientation is decided by PRIMER below,
# NOT by this order — the ordering here is only to make grouping deterministic.
PLAN="$TMPDIR/pair_plan.tsv"
awk -F'\t' -v keycol="$PAIR_KEY" -v ftpcol="$FTP_COL" '
NR==1 {
    for (i=1;i<=NF;i++){ if($i=="run_accession")r=i; if($i==keycol)k=i; if($i==ftpcol)f=i }
    if(!r||!k||!f){ print "ERR_MISSING_COLUMN" > "/dev/stderr"; exit 3 }
    next
}
{ if($r!="" && $k!="" && $f!="") print $k "\t" $r "\t" $f }
' "$ENA_REPORT" | sort -k1,1 -k2,2 > "$PLAN"

n_rows=$(wc -l < "$PLAN")
n_keys=$(cut -f1 "$PLAN" | sort -u | wc -l)
echo "Report parsed: $n_rows runs across $n_keys pair keys."

# --- Process each pair key --------------------------------------------------
processed=0; skipped=0; failed=0
mapfile -t KEYS < <(cut -f1 "$PLAN" | sort -u)

for key in "${KEYS[@]}"; do
    out1="$RAW_DIR/${key}_1.fastq"
    out2="$RAW_DIR/${key}_2.fastq"

    # Checkpoint: both final mates already present.
    if [[ -s "$out1" && -s "$out2" ]]; then
        echo "[$key] already paired — skipping."
        skipped=$((skipped+1)); continue
    fi

    # Gather this key's runs (expect exactly 2).
    mapfile -t runs < <(awk -F'\t' -v k="$key" '$1==k{print $2"\t"$3}' "$PLAN")
    if [[ "${#runs[@]}" -ne 2 ]]; then
        echo "[$key] expected 2 runs, found ${#runs[@]} — skipping (logged)."
        echo "$key: ${#runs[@]} runs (expected 2)" >> "$FAILED_LOG"
        failed=$((failed+1)); continue
    fi

    echo "--------------------------------------------------"
    echo "[$key] runs: $(echo "${runs[0]}" | cut -f1) , $(echo "${runs[1]}" | cut -f1)"

    ok=1
    declare -a raw=()
    for idx in 0 1; do
        run="$(echo "${runs[$idx]}" | cut -f1)"
        ftp="$(echo "${runs[$idx]}" | cut -f2)"
        dst="$TMPDIR/${key}.run${idx}.fastq"
        echo "  downloading $run ..."
        if ! download_run "$ftp" "$dst"; then
            echo "  ERROR: download failed for $run" >&2
            echo "$key/$run: download failed" >> "$FAILED_LOG"
            ok=0; break
        fi
        # Strip any @ACCESSION.spot prefix so the common read name is exposed.
        strip_accession_prefix "$dst" > "$dst.clean" && mv "$dst.clean" "$dst"
        raw[$idx]="$dst"
    done
    [[ "$ok" -eq 1 ]] || { failed=$((failed+1)); continue; }

    # --- Orientation by primer ---------------------------------------------
    f0=$(count_primer_hits "${raw[0]}" "$RE_F")
    f1=$(count_primer_hits "${raw[1]}" "$RE_F")
    r0=$(count_primer_hits "${raw[0]}" "$RE_R")
    r1=$(count_primer_hits "${raw[1]}" "$RE_R")
    echo "  primer hits (of first $ORIENT_READS reads): run0 F=$f0 R=$r0 | run1 F=$f1 R=$r1"

    if (( f0 >= f1 )); then
        fwd="${raw[0]}"; rev="${raw[1]}"
    else
        fwd="${raw[1]}"; rev="${raw[0]}"
    fi
    # Sanity check: the file we called reverse should carry the reverse primer.
    if { [[ "$fwd" == "${raw[0]}" ]] && (( r1 < r0 )); } || \
       { [[ "$fwd" == "${raw[1]}" ]] && (( r0 < r1 )); }; then
        echo "  WARNING: [$key] reverse-primer counts disagree with the forward call — inspect this sample." >&2
    fi
    if (( f0 == 0 && f1 == 0 )); then
        echo "  ERROR: [$key] neither mate matches PRIMER_F; check primers/orientation for this study." >&2
        echo "$key: no forward-primer hits in either mate" >> "$FAILED_LOG"
        failed=$((failed+1)); continue
    fi

    # Reverse mate: make its header end in /2 so the pair is distinguishable.
    rewrite_slash1_to_slash2 "$rev" > "$rev.r2" && mv "$rev.r2" "$rev"

    # --- Re-sync the pair (drops orphans) ----------------------------------
    echo "  repairing pair ..."
    if repair.sh -Xmx12g in="$fwd" in2="$rev" \
            out="$out1" out2="$out2" \
            outs="$RAW_DIR/${key}_orphans.fastq" \
            overwrite=t repair 2>>"$WORK_BASE/$STUDY/repair.log"; then
        processed=$((processed+1))
        echo "  OK: $key -> ${key}_1.fastq / ${key}_2.fastq"
    else
        echo "  ERROR: repair.sh failed for $key" >&2
        echo "$key: repair failed" >> "$FAILED_LOG"
        rm -f "$out1" "$out2"
        failed=$((failed+1))
    fi
    unset raw
done

echo "=================================================="
echo "Done. paired=$processed  skipped(existing)=$skipped  failed=$failed"
if [[ "$failed" -gt 0 ]]; then
    echo "Some samples failed — see $FAILED_LOG" >&2
    exit 1
fi
echo "Ready for import: ./chpc/submit.sh $STUDY import"
