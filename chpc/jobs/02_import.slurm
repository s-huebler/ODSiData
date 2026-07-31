#!/bin/bash
# =============================================================================
# 02_import.slurm — build manifest, import FASTQs to QIIME2, summarize demux.
# Stops at the point where you inspect read quality (demux_viz.qzv). Then run
# the trim stage (03_trim_paired.slurm) and the denoise stage
# (04_dada2_paired.slurm).
#
# Submit via chpc/submit.sh. Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/Artacho2024.sh chpc/jobs/02_import.slurm
# =============================================================================
#SBATCH --job-name=qiime-import
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=chpc/logs/import_%j.out
#SBATCH --error=chpc/logs/import_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Artacho2024.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for QIIME2 import/summarize intermediates ---------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

RAW_DIR="$WORK_BASE/$STUDY/RawData"
QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD"

echo "==== Import for $STUDY ===="
echo "RawData : $RAW_DIR"
echo "Work    : $QD"

# --- 1. Manifest ------------------------------------------------------------
bash chpc/lib/make_manifest_paired.sh "$RAW_DIR" "$QD/manifest.tsv"

# --- 2. Import to QIIME2 ----------------------------------------------------
qiime tools import \
    --type 'SampleData[PairedEndSequencesWithQuality]' \
    --input-path "$QD/manifest.tsv" \
    --output-path "$QD/demux.qza" \
    --input-format PairedEndFastqManifestPhred33V2

# --- 3. Demux summary (the quality plot you inspect) ------------------------
qiime demux summarize \
    --i-data "$QD/demux.qza" \
    --o-visualization "$QD/demux_viz.qzv"

# --- 4. Copy inspectable artifacts back into the repo -----------------------
# demux.qza stays on scratch (large / gitignored). Bring back the manifest and
# the quality-plot visualization so you can view it locally.
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST"
cp -f "$QD/manifest.tsv" "$DEST/"
cp -f "$QD/demux_viz.qzv" "$DEST/"

echo "==== Import done. ===="
echo "Inspect $DEST/demux_viz.qzv (view.qiime2.org or 'qiime tools view'), then run"
echo "the trim stage ('submit.sh $STUDY trim'; skip if no primers set), set"
echo "TRUNC_LEN_F / TRUNC_LEN_R in chpc/$STUDY_FILE, then 'submit.sh $STUDY denoise'."
