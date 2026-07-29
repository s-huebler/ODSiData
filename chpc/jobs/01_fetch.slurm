#!/bin/bash
# =============================================================================
# 01_fetch.slurm — download SRA runs as a SLURM job array (one run per task).
# One array task = one SRR: prefetch + fasterq-dump --split-files, with retries.
# FASTQs land on scratch: $WORK_BASE/$STUDY/RawData.
#
# Submit via chpc/submit.sh (which sets --array and env). To run standalone:
#   sbatch -A <acct> -p notchpeak --array=1-274%20 \
#          --export=ALL,STUDY_FILE=studies/Artacho2024.sh chpc/jobs/01_fetch.slurm
# =============================================================================
#SBATCH --job-name=sra-fetch
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=12:00:00
#SBATCH --output=chpc/logs/fetch_%A_%a.out
#SBATCH --error=chpc/logs/fetch_%A_%a.err

set -euo pipefail

# --- Load config + study params ---------------------------------------------
: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Artacho2024.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_sra_env

RAW_DIR="$WORK_BASE/$STUDY/RawData"
mkdir -p "$RAW_DIR"
cd "$RAW_DIR"

# --- Resolve this array task's accession ------------------------------------
IDX="${SLURM_ARRAY_TASK_ID:?run under a job array (--array)}"
SRR="$(sed -n "${IDX}p" "$ACCESSIONS" | tr -d '[:space:]')"
[[ -n "$SRR" ]] || { echo "No accession at line $IDX of $ACCESSIONS"; exit 0; }

echo "==== [$IDX] $SRR ===="

# Checkpoint: skip if already extracted.
if [[ -f "${SRR}_1.fastq" || -f "${SRR}.fastq" ]]; then
    echo "FASTQ for $SRR already present — skipping."
    exit 0
fi

MAX_RETRIES=3
RETRY_DELAY=60
attempt=1
while (( attempt <= MAX_RETRIES )); do
    echo "Attempt $attempt/$MAX_RETRIES..."
    if prefetch "$SRR" --output-directory . \
       && fasterq-dump --split-files --threads "${SLURM_CPUS_PER_TASK:-4}" "$SRR"; then
        rm -rf "$SRR"          # drop the raw .sra dir to save scratch
        echo "OK: $SRR"
        exit 0
    fi
    echo "Attempt $attempt failed for $SRR."
    (( attempt < MAX_RETRIES )) && sleep "$RETRY_DELAY"
    (( attempt++ ))
done

echo "$SRR" >> "$WORK_BASE/$STUDY/failed_downloads.txt"
echo "ERROR: $SRR failed after $MAX_RETRIES attempts." >&2
exit 1
