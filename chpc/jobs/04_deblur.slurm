#!/bin/bash
# =============================================================================
# 04_deblur.slurm — SINGLE-END / pre-merged layout denoising via Deblur.
# The single-end analogue of 04_dada2_paired.slurm. Reads primer-trimmed reads
# from the trim stage if present, otherwise demux.qza from 02_import_single.slurm
# (both on scratch). Run AFTER inspecting the quality plot and setting
# TRIM_LENGTH in the study file.
#
# Why Deblur (not DADA2) for this layout: these reads are already merged
# (forward+reverse joined), so DADA2's paired error model does not apply and
# denoise-single's error model assumes un-merged reads. Deblur denoises against
# a positive 16S reference and takes pre-joined reads cleanly.
#
# Primer removal is now a SEPARATE stage (chpc/jobs/03_trim_single.slurm, run
# via `chpc/submit.sh <Study> trim`). When FWD_PRIMER is set in the study file
# this job REQUIRES the trimmed reads it produced (demux_trimmed.qza) and aborts
# if they're missing; only when no primer is set does it read the raw demux.qza.
#
# Pipeline: quality-filter q-score -> deblur denoise-16S -> visualize-stats
#           -> export rep-seqs FASTA. Exports dna-sequences.fasta (input for the
# local BLAST Analysis section) plus table.qza / rep-seqs.qza / stats.qza and
# the .qzv summaries.
#
# Submit via chpc/submit.sh (routes here when the study sets LAYOUT="single").
# Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/DAmico2019.sh chpc/jobs/04_deblur.slurm
# =============================================================================
#SBATCH --job-name=qiime-deblur
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=chpc/logs/deblur_%j.out
#SBATCH --error=chpc/logs/deblur_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/DAmico2019.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for QIIME2/deblur/vsearch intermediates -----------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD/exported-seqs"

THREADS="${SLURM_CPUS_PER_TASK:-${DEBLUR_THREADS:-16}}"

# Study-file parameters (with safe defaults).
TRIM_LENGTH="${TRIM_LENGTH:-0}"           # deblur --p-trim-length; MUST be set (>0 or -1)
LEFT_TRIM_LEN="${LEFT_TRIM_LEN:-0}"       # deblur --p-left-trim-len (5' trim, e.g. primer len)
MIN_QUALITY="${MIN_QUALITY:-4}"           # quality-filter q-score min (Deblur default = 4)

# --- Precondition: demux.qza from the import step must exist -----------------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import_single.slurm first." >&2
    exit 1
fi
if [[ "$TRIM_LENGTH" == "0" ]]; then
    echo "ERROR: TRIM_LENGTH is 0. Inspect demux_viz.qzv and set TRIM_LENGTH in" >&2
    echo "       chpc/$STUDY_FILE (a positive length, or -1 to disable trimming)." >&2
    exit 1
fi

echo "==== Deblur for $STUDY ===="
echo "Work        : $QD"
echo "trim-length : $TRIM_LENGTH ; left-trim : $LEFT_TRIM_LEN ; min-quality : $MIN_QUALITY ; threads : $THREADS"

# --- 1. Input selection: use the primer-trimmed reads -----------------------
# Primer removal is a separate stage (03_trim_single.slurm, `submit.sh <Study>
# trim`). When FWD_PRIMER is configured we denoise the reads that stage produced
# (demux_trimmed.qza) and REFUSE to fall back to the primer-containing raw
# demux — a missing trimmed file means the trim stage wasn't run. Only when no
# primer is set (nothing to trim) do we read the raw demux.qza.
if [[ -n "${FWD_PRIMER:-}" ]]; then
    if [[ ! -f "$QD/demux_trimmed.qza" ]]; then
        echo "ERROR: FWD_PRIMER is set but $QD/demux_trimmed.qza is missing." >&2
        echo "       Run the trim stage first:  ./chpc/submit.sh $STUDY trim" >&2
        exit 1
    fi
    DENOISE_INPUT="$QD/demux_trimmed.qza"
    echo "using primer-trimmed reads from the trim stage: $DENOISE_INPUT"
else
    DENOISE_INPUT="$QD/demux.qza"
    echo "no primer set; using raw demux: $DENOISE_INPUT"
fi

# --- 2. Quality filter (Deblur expects q-score-filtered input) --------------
qiime quality-filter q-score \
    --i-demux "$DENOISE_INPUT" \
    --p-min-quality "$MIN_QUALITY" \
    --o-filtered-sequences "$QD/demux-filtered.qza" \
    --o-filter-stats "$QD/filter-stats.qza"

# --- 3. Deblur denoise against positive 16S reference -----------------------
qiime deblur denoise-16S \
    --i-demultiplexed-seqs "$QD/demux-filtered.qza" \
    --p-trim-length "$TRIM_LENGTH" \
    --p-left-trim-len "$LEFT_TRIM_LEN" \
    --p-jobs-to-start "$THREADS" \
    --p-sample-stats \
    --o-representative-sequences "$QD/rep-seqs.qza" \
    --o-table "$QD/table.qza" \
    --o-stats "$QD/stats.qza"

# --- 4. Summaries -----------------------------------------------------------
qiime metadata tabulate \
    --m-input-file "$QD/filter-stats.qza" \
    --o-visualization "$QD/filter-stats_viz.qzv"

qiime deblur visualize-stats \
    --i-deblur-stats "$QD/stats.qza" \
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

# --- 5. Export rep-seqs FASTA (input for the local BLAST step) --------------
qiime tools export \
    --input-path "$QD/rep-seqs.qza" \
    --output-path "$QD/exported-seqs"
# -> $QD/exported-seqs/dna-sequences.fasta

# --- 6. Copy small final artifacts back into the repo -----------------------
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST/exported-seqs"
cp -f "$QD"/table.qza "$QD"/rep-seqs.qza "$QD"/stats.qza "$DEST"/
cp -f "$QD"/*.qzv "$DEST"/ 2>/dev/null || true
cp -f "$QD"/exported-seqs/dna-sequences.fasta "$DEST/exported-seqs/"

echo "==== Done. Final artifacts in $DEST ===="
echo "Next: commit, push, pull locally, then run the BLAST Analysis section locally."
