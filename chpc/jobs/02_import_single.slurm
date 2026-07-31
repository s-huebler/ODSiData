#!/bin/bash
# =============================================================================
# 02_import_single.slurm — SINGLE-END / pre-merged layout.
# Build manifest, import FASTQs to QIIME2 as single-end reads, summarize demux.
# Stops at demux_viz.qzv so you can inspect read-quality and length and choose
# the Deblur --p-trim-length (TRIM_LENGTH) before denoising. Then run the trim
# stage (03_trim_single.slurm) and the denoise stage (04_deblur.slurm, or
# 04_dada2_pyro.slurm / 04_dada2_single.slurm per the study's DENOISER).
#
# Use this instead of 02_import.slurm when the SRA library layout is SINGLE, OR
# when reads are already merged and deposited as a single FASTQ per run (e.g.
# DAmico2019: pre-joined V3-V4 amplicons, variable ~458 bp).
#
# Submit via chpc/submit.sh (routes here when the study sets LAYOUT="single").
# Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/DAmico2019.sh chpc/jobs/02_import_single.slurm
# =============================================================================
#SBATCH --job-name=qiime-import-single
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=chpc/logs/import_single_%j.out
#SBATCH --error=chpc/logs/import_single_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/DAmico2019.sh)}"
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

echo "==== Import (single-end) for $STUDY ===="
echo "RawData : $RAW_DIR"
echo "Work    : $QD"

# --- 1. Manifest (single-end) -----------------------------------------------
bash chpc/lib/make_manifest_single.sh "$RAW_DIR" "$QD/manifest.tsv"

# --- 2. Import to QIIME2 as single-end reads --------------------------------
qiime tools import \
    --type 'SampleData[SequencesWithQuality]' \
    --input-path "$QD/manifest.tsv" \
    --output-path "$QD/demux.qza" \
    --input-format SingleEndFastqManifestPhred33V2

# --- 3. Demux summary (the quality/length plot you inspect) -----------------
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
echo "Inspect $DEST/demux_viz.qzv (view.qiime2.org or 'qiime tools view')."
echo "Next: run the trim stage ('submit.sh $STUDY trim'; skip if no primers set)."
echo "Deblur trims every read to a single length and DISCARDS shorter reads, so"
echo "pick TRIM_LENGTH from the length/quality plot to retain most reads, set it"
echo "in chpc/$STUDY_FILE, then 'submit.sh $STUDY denoise'."
