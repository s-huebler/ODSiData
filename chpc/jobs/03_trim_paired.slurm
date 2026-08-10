#!/bin/bash
# =============================================================================
# 03_trim_paired.slurm — PAIRED-END primer removal with cutadapt.
# Strips primers BY SEQUENCE from the paired demux.qza produced by
# 02_import.slurm (on scratch) using `qiime cutadapt trim-paired`, then writes
# demux_trimmed.qza + a fresh quality plot (demux_trimmed_viz.qzv). This is the
# standalone `trim` stage that used to live inside the paired denoise job (now
# 04_dada2_paired.slurm).
#
# WORKFLOW: import -> [inspect demux_viz.qzv] -> trim (THIS job) -> [inspect
# demux_trimmed_viz.qzv, set TRUNC_LEN_F/R] -> denoise (04_dada2_paired.slurm).
# The denoise job auto-detects demux_trimmed.qza and prefers it; set
# TRIM_LEFT_F/R = 0 in the study file so primers aren't double-trimmed.
#
# Runs only when PRIMER_F and PRIMER_R are both set in the study file. Primers
# are treated as 5' "front" adapters on each read; degenerate IUPAC bases
# (N/W/H/V ...) are matched by default (--p-match-adapter-wildcards is on). If
# neither primer is set the job is a NO-OP (prints a note and exits 0); denoise
# then falls back to the raw demux.qza.
#
# Submit via chpc/submit.sh (routes here when the study sets LAYOUT="paired").
# Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/Artacho2024.sh chpc/jobs/03_trim_paired.slurm
# =============================================================================
#SBATCH --job-name=qiime-trim-paired
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=chpc/logs/trim_paired_%j.out
#SBATCH --error=chpc/logs/trim_paired_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Artacho2024.sh)}"
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

# --- Precondition: demux.qza from the import step must exist -----------------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import.slurm first." >&2
    exit 1
fi

echo "==== cutadapt trim-paired for $STUDY ===="
echo "Work    : $QD"

# --- No primers set -> nothing to trim --------------------------------------
if [[ -z "${PRIMER_F:-}" || -z "${PRIMER_R:-}" ]]; then
    echo "PRIMER_F/PRIMER_R not both set in the study file — nothing to trim."
    echo "Skipping cutadapt; the denoise job will fall back to the raw demux.qza."
    exit 0
fi

echo "---- removing primers by sequence ----"
echo "  front-f (fwd primer) = $PRIMER_F"
echo "  front-r (rev primer) = $PRIMER_R"
echo "  error-rate=${CUTADAPT_ERROR_RATE:-0.1} overlap=${CUTADAPT_OVERLAP:-3}" \
     "min-length=${CUTADAPT_MIN_LENGTH:-1} discard-untrimmed=${CUTADAPT_DISCARD_UNTRIMMED:-true} threads=$THREADS"

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

# --- Post-trim quality plot — inspect before setting TRUNC_LEN_F/R -----------
qiime demux summarize \
    --i-data "$QD/demux_trimmed.qza" \
    --o-visualization "$QD/demux_trimmed_viz.qzv"

# --- Copy the inspectable plot back into the repo ----------------------------
# demux_trimmed.qza stays on scratch (large / gitignored). Bring back only the
# quality-plot visualization so you can view it locally and set trunc lengths.
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST"
cp -f "$QD/demux_trimmed_viz.qzv" "$DEST/"

echo "==== Trim done. Primer-trimmed reads: $QD/demux_trimmed.qza ===="
echo "Inspect $DEST/demux_trimmed_viz.qzv (view.qiime2.org or 'qiime tools view'),"
echo "set TRUNC_LEN_F / TRUNC_LEN_R in chpc/$STUDY_FILE, then: submit.sh $STUDY denoise"
