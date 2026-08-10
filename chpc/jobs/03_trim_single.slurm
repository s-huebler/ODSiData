#!/bin/bash
# =============================================================================
# 03_trim_single.slurm — SINGLE-END / pre-merged primer removal with cutadapt.
# Strips primers from the single-end demux.qza produced by 02_import_single.slurm
# (on scratch) using `qiime cutadapt trim-single`, then writes demux_trimmed.qza
# + a fresh quality plot (demux_trimmed_viz.qzv). This is the standalone `trim`
# stage that used to live inside the single-end denoise jobs (Deblur / DADA2
# denoise-single / denoise-pyro).
#
# WORKFLOW: import -> [inspect demux_viz.qzv] -> trim (THIS job) -> [inspect
# demux_trimmed_viz.qzv, set the denoiser's trim/trunc length] -> denoise
# (04_deblur.slurm | 04_dada2_single.slurm | 04_dada2_pyro.slurm). The denoise
# job auto-detects demux_trimmed.qza and prefers it.
#
# Strips a 5' forward primer (--p-front FWD_PRIMER) and, if set, the 3'
# reverse-complement of the reverse primer (--p-adapter REV_PRIMER_RC). Merged
# amplicons carry the fwd primer at the 5' end and revcomp(rev primer) at the 3'
# end, so both are relevant. Runs only when FWD_PRIMER is set; if it is empty
# the job is a NO-OP (prints a note and exits 0) and denoise falls back to the
# raw demux.qza — e.g. Ingham2019, whose primers are already stripped upstream
# by prep_ingham_454.sh.
#
# Submit via chpc/submit.sh (routes here when the study sets LAYOUT="single").
# Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/DAmico2019.sh chpc/jobs/03_trim_single.slurm
# =============================================================================
#SBATCH --job-name=qiime-trim-single
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=chpc/logs/trim_single_%j.out
#SBATCH --error=chpc/logs/trim_single_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/DAmico2019.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for QIIME2/cutadapt intermediates -----------------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD"

THREADS="${SLURM_CPUS_PER_TASK:-${CUTADAPT_THREADS:-8}}"

FWD_PRIMER="${FWD_PRIMER:-}"              # 5' forward primer (--p-front)
REV_PRIMER_RC="${REV_PRIMER_RC:-}"        # optional 3' adapter = revcomp of reverse primer

# --- Precondition: demux.qza from the single-end import step must exist ------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import_single.slurm first." >&2
    exit 1
fi

echo "==== cutadapt trim-single for $STUDY ===="
echo "Work    : $QD"
echo "primers : fwd='${FWD_PRIMER:-none}' rev_rc='${REV_PRIMER_RC:-none}' threads=$THREADS"

# --- No forward primer set -> nothing to trim -------------------------------
if [[ -z "$FWD_PRIMER" ]]; then
    echo "FWD_PRIMER not set in the study file — nothing to trim."
    echo "Skipping cutadapt; the denoise job will fall back to the raw demux.qza."
    exit 0
fi

CUTADAPT_ARGS=(--i-demultiplexed-sequences "$QD/demux.qza"
               --p-front "$FWD_PRIMER"
               --p-cores "$THREADS"
               --p-discard-untrimmed
               --o-trimmed-sequences "$QD/demux_trimmed.qza"
               --verbose)
[[ -n "$REV_PRIMER_RC" ]] && CUTADAPT_ARGS+=(--p-adapter "$REV_PRIMER_RC")

qiime cutadapt trim-single "${CUTADAPT_ARGS[@]}"

# --- Post-trim quality plot — inspect before setting the trim/trunc length ---
qiime demux summarize \
    --i-data "$QD/demux_trimmed.qza" \
    --o-visualization "$QD/demux_trimmed_viz.qzv"

# --- Copy the inspectable plot back into the repo ----------------------------
# demux_trimmed.qza stays on scratch (large / gitignored). Bring back only the
# quality-plot visualization so you can view it locally.
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST"
cp -f "$QD/demux_trimmed_viz.qzv" "$DEST/"

echo "==== Trim done. Primer-trimmed reads: $QD/demux_trimmed.qza ===="
echo "Inspect $DEST/demux_trimmed_viz.qzv (view.qiime2.org or 'qiime tools view'),"
echo "set the denoiser's trim/trunc length in chpc/$STUDY_FILE, then: submit.sh $STUDY denoise"
