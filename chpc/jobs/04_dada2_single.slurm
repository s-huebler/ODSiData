#!/bin/bash
# =============================================================================
# 04_dada2_single.slurm — SINGLE-END / un-merged Illumina denoising via
# `qiime dada2 denoise-single` (DADA2's standard Illumina error model).
#
# The single-end analogue of 04_dada2_paired.slurm, and the DADA2 counterpart to
# 04_deblur.slurm. Reads primer-trimmed reads from the trim stage if present,
# otherwise demux.qza from 02_import_single.slurm (both on scratch). Run AFTER
# inspecting the quality plot and setting DADA2S_TRUNC_LEN in the study file.
#
# WHICH single-end denoiser to use:
#   * denoise-single (THIS job) — true single-end, UN-MERGED Illumina reads
#     (single-direction runs, or forward-only reads). Learns the standard DADA2
#     Illumina error model. DADA2 does its own quality filtering, so — unlike
#     04_deblur — there is NO separate quality-filter q-score step.
#   * 04_deblur (Deblur) — PRE-MERGED / joined reads (fwd+rev already joined).
#     denoise-single's error model assumes un-merged reads, so use Deblur for
#     that layout instead.
#   * 04_dada2_pyro (denoise-pyro) — 454 / Ion Torrent variable-length reads.
#
# Primer removal is now a SEPARATE stage (chpc/jobs/03_trim_single.slurm, run
# via `chpc/submit.sh <Study> trim`). When FWD_PRIMER is set in the study file
# this job REQUIRES the trimmed reads it produced (demux_trimmed.qza) and aborts
# if they're missing; only when no primer is set does it read the raw demux.qza.
#
# Pipeline: dada2 denoise-single -> summaries -> export rep-seqs FASTA.
#
# Selected by the study file setting LAYOUT="single" + DENOISER="dada2-single";
# submit via chpc/submit.sh. Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/<Study>.sh chpc/jobs/04_dada2_single.slurm
# =============================================================================
#SBATCH --job-name=qiime-dada2-single
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=32G
#SBATCH --time=24:00:00
#SBATCH --output=chpc/logs/dada2_single_%j.out
#SBATCH --error=chpc/logs/dada2_single_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/<Study>.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for QIIME2/DADA2 intermediates --------------------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD/exported-seqs"

THREADS="${SLURM_CPUS_PER_TASK:-${DADA2S_THREADS:-${DADA2_THREADS:-16}}}"

# --- Study-file parameters (with safe defaults) ------------------------------
# DADA2S_TRUNC_LEN is REQUIRED and has no sensible default — set it from the
# demux length/quality plot. It truncates every read at this position and
# DISCARDS any read shorter than it. Value 0 = NO truncation (keep full length,
# rely on max-ee/trunc-q for quality); the empty/unset state (not 0) triggers
# the guard below.
DADA2S_TRUNC_LEN="${DADA2S_TRUNC_LEN-}"     # note: '-' not ':-' so we can detect unset vs 0
DADA2S_TRIM_LEFT="${DADA2S_TRIM_LEFT:-0}"   # --p-trim-left (5' trim; 0 = primers already removed)
DADA2S_MAX_EE="${DADA2S_MAX_EE:-2.0}"       # --p-max-ee (max expected errors; DADA2 default 2.0)
DADA2S_TRUNC_Q="${DADA2S_TRUNC_Q:-2}"       # --p-trunc-q (truncate at first base <= this q; default 2)
DADA2S_CHIMERA="${DADA2S_CHIMERA:-consensus}" # --p-chimera-method (consensus|pooled|none)

# --- Precondition: demux.qza from the single-end import step must exist ------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import_single.slurm first." >&2
    exit 1
fi
if [[ -z "$DADA2S_TRUNC_LEN" ]]; then
    echo "ERROR: DADA2S_TRUNC_LEN is unset. Inspect demux_viz.qzv and set" >&2
    echo "       DADA2S_TRUNC_LEN in chpc/$STUDY_FILE (a positive length, or 0" >&2
    echo "       to disable truncation and keep full-length reads)." >&2
    exit 1
fi

echo "==== DADA2 denoise-single for $STUDY ===="
echo "Work        : $QD"
echo "trunc-len=$DADA2S_TRUNC_LEN trim-left=$DADA2S_TRIM_LEFT max-ee=$DADA2S_MAX_EE" \
     "trunc-q=$DADA2S_TRUNC_Q chimera=$DADA2S_CHIMERA threads=$THREADS"

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

# --- 2. DADA2 denoise-single ------------------------------------------------
qiime dada2 denoise-single \
    --i-demultiplexed-seqs "$DENOISE_INPUT" \
    --p-trunc-len "$DADA2S_TRUNC_LEN" \
    --p-trim-left "$DADA2S_TRIM_LEFT" \
    --p-max-ee "$DADA2S_MAX_EE" \
    --p-trunc-q "$DADA2S_TRUNC_Q" \
    --p-chimera-method "$DADA2S_CHIMERA" \
    --p-n-threads "$THREADS" \
    --o-table "$QD/table.qza" \
    --o-representative-sequences "$QD/rep-seqs.qza" \
    --o-denoising-stats "$QD/stats.qza"

# --- 3. Summaries -----------------------------------------------------------
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

# --- 4. Export rep-seqs FASTA (input for the local BLAST step) --------------
qiime tools export \
    --input-path "$QD/rep-seqs.qza" \
    --output-path "$QD/exported-seqs"
# -> $QD/exported-seqs/dna-sequences.fasta

# --- 5. Copy small final artifacts back into the repo -----------------------
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST/exported-seqs"
cp -f "$QD"/table.qza "$QD"/rep-seqs.qza "$QD"/stats.qza "$DEST"/
cp -f "$QD"/*.qzv "$DEST"/ 2>/dev/null || true
cp -f "$QD"/exported-seqs/dna-sequences.fasta "$DEST/exported-seqs/"

echo "==== Done. Final artifacts in $DEST ===="
echo "Next: commit, push, pull locally, then run the BLAST Analysis section locally."
