#!/bin/bash
# =============================================================================
# 04_dada2_paired.slurm — DADA2 denoise (paired-end), summaries, export
# rep-seqs FASTA.
# Reads primer-trimmed reads from the trim stage if present, otherwise the raw
# demux.qza produced by 02_import.slurm (both on scratch). Run AFTER you've
# inspected the quality plot and set TRUNC_LEN_F/R in the study file. Covers
# everything up to (not including) the local BLAST Analysis section.
#
# Primer removal is now a SEPARATE stage (chpc/jobs/03_trim_paired.slurm, run
# via `chpc/submit.sh <Study> trim`). When PRIMER_F/PRIMER_R are set in the study
# file this job REQUIRES the trimmed reads that stage produced
# (demux_trimmed.qza) and aborts if they're missing — it will NOT silently
# denoise primer-containing raw reads. Set TRIM_LEFT_F/R = 0 in the study file so
# primers aren't double-trimmed. Only when no primers are set does this job read
# the raw demux.qza.
#
# Submit via chpc/submit.sh. Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/Artacho2024.sh chpc/jobs/04_dada2_paired.slurm
# =============================================================================
#SBATCH --job-name=qiime-dada2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=chpc/logs/dada2_%j.out
#SBATCH --error=chpc/logs/dada2_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Artacho2024.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for QIIME2/DADA2/vsearch intermediates ------------------
# QIIME2 writes large temp files to $TMPDIR during DADA2, summaries, and export.
# If node-local disk is too small for your dataset, drop this block to fall back
# to a dir under $WORK_BASE (network, slower but larger).
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD/exported-seqs"

THREADS="${SLURM_CPUS_PER_TASK:-$DADA2_THREADS}"

# --- Precondition: demux.qza from the import step must exist -----------------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import.slurm first." >&2
    exit 1
fi

echo "==== DADA2 for $STUDY ===="
echo "Work    : $QD"
echo "trim L f/r = $TRIM_LEFT_F/$TRIM_LEFT_R ; trunc f/r = $TRUNC_LEN_F/$TRUNC_LEN_R ; threads=$THREADS"

# --- 0. Input selection: use the primer-trimmed reads -----------------------
# Primer removal is a separate stage (03_trim_paired.slurm, `submit.sh <Study>
# trim`). When primers are configured we denoise the reads that stage produced
# (demux_trimmed.qza) and REFUSE to fall back to the primer-containing raw
# demux — a missing trimmed file means the trim stage wasn't run. Only when no
# primers are set (nothing to trim) do we read the raw demux.qza.
if [[ -n "${PRIMER_F:-}" && -n "${PRIMER_R:-}" ]]; then
    if [[ ! -f "$QD/demux_trimmed.qza" ]]; then
        echo "ERROR: PRIMER_F/PRIMER_R are set but $QD/demux_trimmed.qza is missing." >&2
        echo "       Run the trim stage first:  ./chpc/submit.sh $STUDY trim" >&2
        exit 1
    fi
    DENOISE_INPUT="$QD/demux_trimmed.qza"
    echo "---- using primer-trimmed reads from the trim stage: $DENOISE_INPUT ----"
else
    DENOISE_INPUT="$QD/demux.qza"
    echo "---- no primers set; using raw demux: $DENOISE_INPUT ----"
fi

# --- 1. DADA2 denoise-paired ------------------------------------------------
qiime dada2 denoise-paired \
    --i-demultiplexed-seqs "$DENOISE_INPUT" \
    --p-trim-left-f "$TRIM_LEFT_F" \
    --p-trim-left-r "$TRIM_LEFT_R" \
    --p-trunc-len-f "$TRUNC_LEN_F" \
    --p-trunc-len-r "$TRUNC_LEN_R" \
    --p-n-threads "$THREADS" \
    --o-table "$QD/table.qza" \
    --o-representative-sequences "$QD/rep-seqs.qza" \
    --o-denoising-stats "$QD/stats.qza"

# --- 2. Summaries -----------------------------------------------------------
qiime metadata tabulate \
    --m-input-file "$QD/stats.qza" \
    --o-visualization "$QD/stats_viz.qzv"

if [[ -n "$METADATA" && -f "$METADATA" ]]; then
    qiime feature-table summarize \
        --i-table "$QD/table.qza" \
        --m-sample-metadata-file "$METADATA" \
        --o-visualization "$QD/table_viz.qzv"
else
    qiime feature-table summarize \
        --i-table "$QD/table.qza" \
        --o-visualization "$QD/table_viz.qzv"
fi

qiime feature-table tabulate-seqs \
    --i-data "$QD/rep-seqs.qza" \
    --o-visualization "$QD/rep-seqs_viz.qzv"

# --- 3. Export rep-seqs FASTA (input for the local BLAST step) ---------------
qiime tools export \
    --input-path "$QD/rep-seqs.qza" \
    --output-path "$QD/exported-seqs"
# -> $QD/exported-seqs/dna-sequences.fasta

# --- 4. Copy small final artifacts back into the repo -----------------------
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST/exported-seqs"
cp -f "$QD"/table.qza "$QD"/rep-seqs.qza "$QD"/stats.qza "$DEST"/
cp -f "$QD"/*.qzv "$DEST"/ 2>/dev/null || true
cp -f "$QD"/exported-seqs/dna-sequences.fasta "$DEST/exported-seqs/"

echo "==== Done. Final artifacts in $DEST ===="
echo "Next: commit, push, pull locally, then run the BLAST Analysis section locally."
