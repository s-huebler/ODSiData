#!/usr/bin/env bash
# Step 2 — quality trimming (Trimmomatic) then primer removal (cutadapt).
#
# Run INSIDE the container:
#   ./docker/run.sh bash scripts/02_trim.sh
#
# Reads are single-end Ion Torrent (V1-V3, ~500 bp amplicon, 600 bp protocol),
# already demultiplexed by ENA — so the "demultiplexed using cutadapt" clause in
# the methods reduces to primer stripping here.
#
# Inputs:  data/raw/*.fastq.gz
# Outputs: data/trimmed/*.fastq.gz    (post-Trimmomatic)
#          data/cutadapt/*.fastq.gz   (post-primer-removal, input to DADA2)
#          logs/02_trim.log, results/02_cutadapt_summary.tsv
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="${HERE}/data/raw"
TRIM="${HERE}/data/trimmed"
CUT="${HERE}/data/cutadapt"
mkdir -p "${TRIM}" "${CUT}" "${HERE}/logs" "${HERE}/results"

exec > >(tee "${HERE}/logs/02_trim.log") 2>&1

# ---------------------------------------------------------------------------
# PRIMERS (Klindworth-style names given in the paper)
#   S-D-Bact-0008-c-S-20  = 27F   forward, 20 nt
#   S-D-Bact-0517-a-A-18  = 519R  reverse, 18 nt
# Reads are forward-oriented, so we expect 27F at the 5' end and, for short
# amplicons that read through, the reverse complement of 519R at the 3' end.
# ---------------------------------------------------------------------------
FWD_PRIMER="AGRGTTYGATYMTGGCTCAG"
REV_PRIMER_RC="GCCAGCMGCCGCGGTAAT"

# ---------------------------------------------------------------------------
# TRIMMOMATIC PARAMETERS — INFERRED, NOT REPORTED.
# The paper states only "quality trimming with Trimmomatic (0.9)" with no
# settings. These are conventional single-end defaults. If the alpha diversity
# comparison in step 4 is off, this block is the first thing to vary.
# ---------------------------------------------------------------------------
TRIMMOMATIC_ARGS="LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:100"

THREADS="${THREADS:-4}"

echo "=== Step 2: trim ==="
date
echo "Trimmomatic args : ${TRIMMOMATIC_ARGS}"
echo "Forward primer   : ${FWD_PRIMER}"
echo "Reverse primer RC: ${REV_PRIMER_RC}"
echo "Threads          : ${THREADS}"
echo

shopt -s nullglob
FILES=("${RAW}"/*.fastq.gz)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR: no fastq.gz in ${RAW}. Run scripts/01_download.sh first." >&2
  exit 1
fi
echo "Found ${#FILES[@]} input files."
echo

SUMMARY="${HERE}/results/02_cutadapt_summary.tsv"
printf "sample\traw_reads\ttrimmomatic_reads\tcutadapt_reads\tfwd_primer_found\trev_primer_found\n" > "${SUMMARY}"

for f in "${FILES[@]}"; do
  s="$(basename "${f}" .fastq.gz)"
  echo "--- ${s} ---"

  raw_n=$(( $(zcat "${f}" | wc -l) / 4 ))

  # --- Trimmomatic (single-end) ---
  trimmomatic SE -threads "${THREADS}" -phred33 \
    "${f}" "${TRIM}/${s}.fastq.gz" \
    ${TRIMMOMATIC_ARGS}

  trim_n=$(( $(zcat "${TRIM}/${s}.fastq.gz" | wc -l) / 4 ))

  # --- cutadapt: strip 27F from 5', read-through 519R-rc from 3' ---
  # --discard-untrimmed is deliberately NOT set: Ion Torrent 5' ends are noisy
  # and dropping every read without a clean primer match would bias depth.
  # -e 0.15 tolerates the degenerate bases; -n 2 allows both ends in one pass.
  ca_report="${HERE}/logs/cutadapt_${s}.txt"
  cutadapt \
    -g "${FWD_PRIMER}" \
    -a "${REV_PRIMER_RC}" \
    -e 0.15 -n 2 \
    --minimum-length 100 \
    -j "${THREADS}" \
    -o "${CUT}/${s}.fastq.gz" \
    "${TRIM}/${s}.fastq.gz" > "${ca_report}"

  cut_n=$(( $(zcat "${CUT}/${s}.fastq.gz" | wc -l) / 4 ))
  # cutadapt's per-adapter block reads:
  #   Sequence: <seq>; Type: regular 5'; Length: 20; Trimmed: 9512 times
  # so pull the token immediately after "Trimmed:" under each adapter header.
  fwd_hit=$(awk '/=== Adapter 1 ===/{f=1} f && /Trimmed:/{for(i=1;i<=NF;i++) if($i=="Trimmed:"){gsub(/,/,"",$(i+1)); print $(i+1); exit}}' "${ca_report}")
  rev_hit=$(awk '/=== Adapter 2 ===/{f=1} f && /Trimmed:/{for(i=1;i<=NF;i++) if($i=="Trimmed:"){gsub(/,/,"",$(i+1)); print $(i+1); exit}}' "${ca_report}")

  printf "%s\t%s\t%s\t%s\t%s\t%s\n" "${s}" "${raw_n}" "${trim_n}" "${cut_n}" "${fwd_hit:-NA}" "${rev_hit:-NA}" >> "${SUMMARY}"
  echo "raw=${raw_n} trimmomatic=${trim_n} cutadapt=${cut_n}"
  echo
done

echo "=== done ==="
echo "Per-sample read survival written to ${SUMMARY}"
date
