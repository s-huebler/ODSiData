#!/bin/bash
# =============================================================================
# 03_denoise_pyro.slurm — SINGLE-END 454 / Ion Torrent denoising via
# `qiime dada2 denoise-pyro` (DADA2's pyrosequencing error model).
#
# This is the highest-fidelity denoiser for 454 data: unlike Deblur (which trims
# every read to one fixed length and DISCARDS shorter reads — lossy on the
# 200-1000 bp variable-length 454 reads in Ingham2019), denoise-pyro learns a
# 454-specific error model that tolerates homopolymer indels and variable read
# length. It is the QIIME2 successor to the paper's flowgram denoise_wrapper.py.
#
# Reads demux.qza from 02_import_single.slurm (single-end import; on scratch).
# Run AFTER inspecting demux_viz.qzv and setting PYRO_TRUNC_LEN in the study
# file. DADA2 does its own quality filtering, so — unlike 03_deblur_single —
# there is NO separate quality-filter step here.
#
# Selected by the study file setting LAYOUT="single" + DENOISER="pyro"; submit
# via chpc/submit.sh. Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/Ingham2019.sh chpc/jobs/03_denoise_pyro.slurm
# =============================================================================
#SBATCH --job-name=qiime-pyro
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=chpc/logs/pyro_%j.out
#SBATCH --error=chpc/logs/pyro_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Ingham2019.sh)}"
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

THREADS="${SLURM_CPUS_PER_TASK:-${PYRO_THREADS:-${DEBLUR_THREADS:-16}}}"

# --- Study-file parameters (with safe defaults) ------------------------------
# PYRO_TRUNC_LEN is REQUIRED and has no sensible default — set it from the demux
# length/quality plot. It truncates every read at this position and DISCARDS any
# read shorter than it, so on variable-length 454 reads choose it to balance
# quality vs. read retention. Value 0 = NO truncation (keep full length, rely on
# max-ee/trunc-q for quality) — a legitimate choice for 454; the empty/unset
# state (not 0) is what triggers the guard below.
PYRO_TRUNC_LEN="${PYRO_TRUNC_LEN-}"       # note: '-' not ':-' so we can detect unset vs 0
PYRO_TRIM_LEFT="${PYRO_TRIM_LEFT:-0}"     # --p-trim-left (5' trim; 0 = primers already removed)
PYRO_MAX_LEN="${PYRO_MAX_LEN:-0}"         # --p-max-len (drop reads longer than this pre-trim; 0 = off)
PYRO_MAX_EE="${PYRO_MAX_EE:-2.0}"         # --p-max-ee (max expected errors; DADA2 default 2.0)
PYRO_TRUNC_Q="${PYRO_TRUNC_Q:-2}"         # --p-trunc-q (truncate at first base <= this q; default 2)
PYRO_CHIMERA="${PYRO_CHIMERA:-consensus}" # --p-chimera-method (consensus|pooled|none)
FWD_PRIMER="${FWD_PRIMER:-}"              # optional 5' primer for cutadapt (no-op for Ingham2019)
REV_PRIMER_RC="${REV_PRIMER_RC:-}"        # optional 3' adapter = revcomp of reverse primer

# --- Precondition: demux.qza from the single-end import step must exist ------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import_single.slurm first." >&2
    exit 1
fi
if [[ -z "$PYRO_TRUNC_LEN" ]]; then
    echo "ERROR: PYRO_TRUNC_LEN is unset. Inspect demux_viz.qzv and set" >&2
    echo "       PYRO_TRUNC_LEN in chpc/$STUDY_FILE (a positive length, or 0 to" >&2
    echo "       disable truncation and keep full-length 454 reads)." >&2
    exit 1
fi

echo "==== DADA2 denoise-pyro for $STUDY ===="
echo "Work        : $QD"
echo "trunc-len=$PYRO_TRUNC_LEN trim-left=$PYRO_TRIM_LEFT max-len=$PYRO_MAX_LEN" \
     "max-ee=$PYRO_MAX_EE trunc-q=$PYRO_TRUNC_Q chimera=$PYRO_CHIMERA threads=$THREADS"
echo "primers     : fwd='${FWD_PRIMER:-none}' rev_rc='${REV_PRIMER_RC:-none}'"

# --- 1. Optional primer removal with cutadapt (skipped when FWD_PRIMER empty)-
# NO-OP for Ingham2019: primers are already stripped upstream by
# prep_ingham_454.sh, so FWD_PRIMER/REV_PRIMER_RC are empty in that study file.
# Kept for reuse by other single-end 454/Ion Torrent studies.
DENOISE_INPUT="$QD/demux.qza"
if [[ -n "$FWD_PRIMER" ]]; then
    CUTADAPT_ARGS=(--i-demultiplexed-sequences "$QD/demux.qza"
                   --p-front "$FWD_PRIMER"
                   --p-cores "$THREADS"
                   --p-discard-untrimmed
                   --o-trimmed-sequences "$QD/demux-trimmed.qza"
                   --verbose)
    [[ -n "$REV_PRIMER_RC" ]] && CUTADAPT_ARGS+=(--p-adapter "$REV_PRIMER_RC")
    qiime cutadapt trim-single "${CUTADAPT_ARGS[@]}"
    qiime demux summarize \
        --i-data "$QD/demux-trimmed.qza" \
        --o-visualization "$QD/demux_trimmed_viz.qzv"
    DENOISE_INPUT="$QD/demux-trimmed.qza"
fi

# --- 2. DADA2 denoise-pyro --------------------------------------------------
qiime dada2 denoise-pyro \
    --i-demultiplexed-seqs "$DENOISE_INPUT" \
    --p-trunc-len "$PYRO_TRUNC_LEN" \
    --p-trim-left "$PYRO_TRIM_LEFT" \
    --p-max-len "$PYRO_MAX_LEN" \
    --p-max-ee "$PYRO_MAX_EE" \
    --p-trunc-q "$PYRO_TRUNC_Q" \
    --p-chimera-method "$PYRO_CHIMERA" \
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
