#!/bin/bash
# =============================================================================
# 03_dada2.slurm — (optional cutadapt primer removal) DADA2 denoise, summaries,
# export rep-seqs FASTA.
# Reads demux.qza produced by 02_import.slurm (on scratch). Run AFTER you've
# inspected demux_viz.qzv and set TRUNC_LEN_F/R in the study file. Covers
# everything up to (not including) the local BLAST Analysis section.
#
# If PRIMER_F/PRIMER_R are set in the study file, primers are stripped by
# SEQUENCE with `qiime cutadapt trim-paired` before denoising (more robust than
# positional --p-trim-left when read lengths vary). In that case set
# TRIM_LEFT_F/R = 0 in the study file so primers aren't double-trimmed. Leave
# PRIMER_F/PRIMER_R empty to skip cutadapt entirely.
#
# Submit via chpc/submit.sh. Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/Artacho2024.sh chpc/jobs/03_dada2.slurm
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
# If node-local disk is too small for your dataset, drop this block to fall back
# to a dir under $WORK_BASE (network, slower but larger).
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

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

# --- 0. Optional primer removal with cutadapt -------------------------------
# Runs only when PRIMER_F and PRIMER_R are both set in the study file. Primers
# are treated as 5' "front" adapters on each read; degenerate IUPAC bases
# (N/W/H/V ...) are matched by default (--p-match-adapter-wildcards is on).
# Produces demux_trimmed.qza + a fresh quality plot (demux_trimmed_viz.qzv) so
# you can re-pick TRUNC_LEN_F/R on the primer-free reads.
DENOISE_INPUT="$QD/demux.qza"
if [[ -n "${PRIMER_F:-}" && -n "${PRIMER_R:-}" ]]; then
    echo "---- cutadapt trim-paired: removing primers by sequence ----"
    echo "  front-f (fwd primer) = $PRIMER_F"
    echo "  front-r (rev primer) = $PRIMER_R"
    echo "  error-rate=${CUTADAPT_ERROR_RATE:-0.1} overlap=${CUTADAPT_OVERLAP:-3}" \
         "min-length=${CUTADAPT_MIN_LENGTH:-1} discard-untrimmed=${CUTADAPT_DISCARD_UNTRIMMED:-true}"

    CUTADAPT_ARGS=(
        --i-demultiplexed-sequences "$QD/demux.qza"
        --p-front-f "$PRIMER_F"
        --p-front-r "$PRIMER_R"
        --p-error-rate "${CUTADAPT_ERROR_RATE:-0.1}"
        --p-overlap "${CUTADAPT_OVERLAP:-3}"
        --p-minimum-length "${CUTADAPT_MIN_LENGTH:-1}"
        --p-cores "$THREADS"
        --o-trimmed-sequences "$QD/demux_trimmed.qza"
        --verbose
    )
    # Drop read pairs where a primer wasn't found (recommended for amplicon data).
    if [[ "${CUTADAPT_DISCARD_UNTRIMMED:-true}" == "true" ]]; then
        CUTADAPT_ARGS+=(--p-discard-untrimmed)
    else
        CUTADAPT_ARGS+=(--p-no-discard-untrimmed)
    fi
    # Escape hatch: any extra raw flags from the study file (space-separated),
    # e.g. CUTADAPT_EXTRA="--p-indels --p-times 2".
    if [[ -n "${CUTADAPT_EXTRA:-}" ]]; then
        # shellcheck disable=SC2206
        CUTADAPT_ARGS+=(${CUTADAPT_EXTRA})
    fi

    qiime cutadapt trim-paired "${CUTADAPT_ARGS[@]}"

    # Post-trim quality plot — inspect before trusting TRUNC_LEN_F/R.
    qiime demux summarize \
        --i-data "$QD/demux_trimmed.qza" \
        --o-visualization "$QD/demux_trimmed_viz.qzv"

    DENOISE_INPUT="$QD/demux_trimmed.qza"
    echo "  -> primer-trimmed reads: $DENOISE_INPUT"
else
    echo "---- cutadapt skipped (PRIMER_F/PRIMER_R not set); using raw demux ----"
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
