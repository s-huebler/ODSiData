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

# --- Node-local temp for fasterq-dump's heavy random I/O --------------------
# Keep temp OFF the network filesystem (/scratch/general/vast). Use fast
# node-local disk instead. Per-task dir, cleaned up on exit.
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

RAW_DIR="$WORK_BASE/$STUDY/RawData"
mkdir -p "$RAW_DIR"
cd "$RAW_DIR"

# --- Resolve this array task's accession ------------------------------------
IDX="${SLURM_ARRAY_TASK_ID:?run under a job array (--array)}"
SRR="$(sed -n "${IDX}p" "$ACCESSIONS" | tr -d '[:space:]')"
[[ -n "$SRR" ]] || { echo "No accession at line $IDX of $ACCESSIONS"; exit 0; }

echo "==== [$IDX] $SRR ===="

# --- Concatenated-read split helper -----------------------------------------
# Studies whose SRA records store forward+revcomp(reverse) joined in a single
# read (e.g. DAmico2019) set SPLIT_CONCAT=1 in their study file. After download
# this turns the single ${SRR}.fastq into proper ${SRR}_1.fastq / ${SRR}_2.fastq
# so the standard paired import + DADA2 path applies. No-op when SPLIT_CONCAT!=1.
split_concat() {
    [[ "${SPLIT_CONCAT:-0}" == "1" ]] || return 0
    [[ -f "${SRR}.fastq" && ! -f "${SRR}_1.fastq" ]] || return 0
    echo "Splitting concatenated reads for $SRR (r1-len=${SPLIT_R1_LEN:-250})..."
    python3 "$REPO_ROOT/chpc/lib/split_concat_16s.py" \
        "${SRR}.fastq" . \
        --r1-len "${SPLIT_R1_LEN:-250}" --min-r2 "${SPLIT_MIN_R2:-20}" \
        || { echo "ERROR: split failed for $SRR" >&2; return 1; }
    rm -f "${SRR}.fastq"          # drop the concatenated original
}

# Checkpoint: skip only when the FINAL outputs for this layout already exist.
if [[ "${SPLIT_CONCAT:-0}" == "1" ]]; then
    if [[ -f "${SRR}_1.fastq" && -f "${SRR}_2.fastq" ]]; then
        echo "Split FASTQs for $SRR already present — skipping."
        exit 0
    fi
    # Resume: a concatenated file survived a previous run — split it, don't re-download.
    if [[ -f "${SRR}.fastq" ]]; then
        split_concat && { echo "OK (resumed split): $SRR"; exit 0; }
        exit 1
    fi
elif [[ -f "${SRR}_1.fastq" || -f "${SRR}.fastq" ]]; then
    echo "FASTQ for $SRR already present — skipping."
    exit 0
fi

MAX_RETRIES=3
RETRY_DELAY=60
attempt=1
while (( attempt <= MAX_RETRIES )); do
    echo "Attempt $attempt/$MAX_RETRIES..."
    if prefetch "$SRR" --output-directory . \
       && fasterq-dump --split-files \
              --threads "${SLURM_CPUS_PER_TASK:-4}" \
              --temp "$TMPDIR" "$SRR"; then
        rm -rf "$SRR"          # drop the raw .sra dir to save scratch
        split_concat || exit 1  # no-op unless SPLIT_CONCAT=1
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
