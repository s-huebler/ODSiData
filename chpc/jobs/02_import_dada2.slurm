#!/bin/bash
# =============================================================================
# 02_import_dada2.slurm — import FASTQs, DADA2 denoise, summarize, export.
# Runs everything from the Fujimoto Preprocessing.qmd up to (not including) the
# BLAST Analysis section. Reads FASTQs from scratch, writes QIIME artifacts to
# scratch, then copies the small final artifacts back into the repo.
#
# Submit via chpc/submit.sh. Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/Artacho2024.sh chpc/jobs/02_import_dada2.slurm
# =============================================================================
#SBATCH --job-name=qiime-dada2
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
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
# Point it at fast node-local disk instead of the network filesystem. Cleaned up
# on exit. If node-local disk is too small for your dataset, drop this block and
# fall back to a dir under $WORK_BASE (network, slower but larger).
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

RAW_DIR="$WORK_BASE/$STUDY/RawData"
QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD/exported-seqs"

THREADS="${SLURM_CPUS_PER_TASK:-$DADA2_THREADS}"

echo "==== Import -> DADA2 for $STUDY ===="
echo "RawData : $RAW_DIR"
echo "Work    : $QD"
echo "trim  L f/r = $TRIM_LEFT_F/$TRIM_LEFT_R ; trunc f/r = $TRUNC_LEN_F/$TRUNC_LEN_R ; threads=$THREADS"

# --- 1. Manifest ------------------------------------------------------------
bash chpc/lib/make_manifest_paired.sh "$RAW_DIR" "$QD/manifest.tsv"

# --- 2. Import to QIIME2 ----------------------------------------------------
qiime tools import \
    --type 'SampleData[PairedEndSequencesWithQuality]' \
    --input-path "$QD/manifest.tsv" \
    --output-path "$QD/demux.qza" \
    --input-format PairedEndFastqManifestPhred33V2

qiime demux summarize \
    --i-data "$QD/demux.qza" \
    --o-visualization "$QD/demux_viz.qzv"

# --- 3. DADA2 denoise-paired ------------------------------------------------
qiime dada2 denoise-paired \
    --i-demultiplexed-seqs "$QD/demux.qza" \
    --p-trim-left-f "$TRIM_LEFT_F" \
    --p-trim-left-r "$TRIM_LEFT_R" \
    --p-trunc-len-f "$TRUNC_LEN_F" \
    --p-trunc-len-r "$TRUNC_LEN_R" \
    --p-n-threads "$THREADS" \
    --o-table "$QD/table.qza" \
    --o-representative-sequences "$QD/rep-seqs.qza" \
    --o-denoising-stats "$QD/stats.qza"

# --- 4. Summaries -----------------------------------------------------------
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

# --- 5. Export rep-seqs FASTA (input for the local BLAST step) ---------------
qiime tools export \
    --input-path "$QD/rep-seqs.qza" \
    --output-path "$QD/exported-seqs"
# -> $QD/exported-seqs/dna-sequences.fasta

# --- 6. Copy small final artifacts back into the repo -----------------------
# FASTQ and demux.qza stay on scratch (gitignored / too large). We keep the
# denoised table, rep-seqs, stats, the exported FASTA, and the .qzv summaries.
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST/exported-seqs"
cp -f "$QD"/table.qza "$QD"/rep-seqs.qza "$QD"/stats.qza "$DEST"/
cp -f "$QD"/*.qzv "$DEST"/ 2>/dev/null || true
cp -f "$QD"/manifest.tsv "$DEST"/
cp -f "$QD"/exported-seqs/dna-sequences.fasta "$DEST/exported-seqs/"

echo "==== Done. Final artifacts in $DEST ===="
echo "Next: commit, push, pull locally, then run the BLAST Analysis section locally."
