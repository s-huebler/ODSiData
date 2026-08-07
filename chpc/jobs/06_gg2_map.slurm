#!/bin/bash
# =============================================================================
# 06_gg2_map.slurm — map ASVs onto the Greengenes2 backbone (non-v4-16s)
#
# Step 2 of the Greengenes2 mapping pipeline. Runs `qiime greengenes2
# non-v4-16s`, a closed-reference OTU pick that characterizes the study's
# (QC-filtered) ASVs against the GG2 backbone and re-expresses features in the
# backbone namespace. This is what makes tables COMPARABLE across primer regions
# (V4 / V3-V4 / V4-V5): after mapping, the same organism from two studies lands
# on the same backbone feature ID and lines up with the GG2 tree
# (<version>.phylogeny.asv.nwk.qza) for merging + UniFrac downstream.
#
# We run non-v4-16s UNIFORMLY on every study (including V4 Liu2017) so the whole
# cohort ends up in one backbone namespace — the deliberate "first try" choice.
#
# Inputs (defaults resolved below; override in chpc/studies/<Study>.sh):
#   MAP_INPUT_TABLE default <Study>/Mapped/qc-table.qza   (from 05_qc.slurm)
#   MAP_INPUT_SEQS  default <Study>/Mapped/qc-seqs.qza     (from 05_qc.slurm)
#   GG2_BACKBONE    the GG2 backbone sequences (config.sh; = GG2_REF_SEQS)
#
# Outputs -> <Study>/Mapped/:
#   mapped-table.qza    feature table in the GG2 backbone namespace
#   mapped-seqs.qza     representative backbone tips
#   *.qzv               mapped-table + rep-seqs summaries
#
# Submit via chpc/submit.sh (per study):
#   ./chpc/submit.sh <Study> map
# Standalone:
#   sbatch -A <acct> -p <part> \
#          --export=ALL,STUDY_FILE=studies/<Study>.sh chpc/jobs/06_gg2_map.slurm
# =============================================================================
#SBATCH --job-name=qiime-gg2map
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=24G
#SBATCH --time=04:00:00
#SBATCH --output=chpc/logs/gg2map_%j.out
#SBATCH --error=chpc/logs/gg2map_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Liu2017.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

# Use the personal conda env that carries q2-greengenes2 (the CHPC qiime2 module
# doesn't ship the plugin). See load_qiime2_gg2_env / GG2_ENV in config.sh. This
# stage is routed to notchpeak-shared-short by submit.sh, so the env's AVX2 deps
# are safe here.
load_qiime2_gg2_env
check_gg2_plugin

# --- Node-local temp for non-v4-16s intermediates ---------------------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

THREADS="${SLURM_CPUS_PER_TASK:-${MAP_THREADS:-8}}"

# --- Resolve inputs (study file may override; else the qc stage outputs) -----
MAP_INPUT_TABLE="${MAP_INPUT_TABLE:-$REPO_ROOT/$STUDY/Mapped/qc-table.qza}"
MAP_INPUT_SEQS="${MAP_INPUT_SEQS:-$REPO_ROOT/$STUDY/Mapped/qc-seqs.qza}"
GG2_MAP_PERC_IDENTITY="${GG2_MAP_PERC_IDENTITY:-0.99}"

# --- Preconditions ----------------------------------------------------------
for f in "$MAP_INPUT_TABLE" "$MAP_INPUT_SEQS" "$GG2_BACKBONE"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required input not found: $f" >&2
        if [[ "$f" == "$MAP_INPUT_TABLE" || "$f" == "$MAP_INPUT_SEQS" ]]; then
            echo "       Run the qc stage first:  ./chpc/submit.sh $STUDY qc" >&2
        elif [[ "$f" == "$GG2_BACKBONE" ]]; then
            echo "       GG2 backbone is set in chpc/config.sh (GG2_BACKBONE). Download the" >&2
            echo "       ${GG2_VERSION} release from ftp.microbio.me/greengenes_release/${GG2_VERSION}/" >&2
        fi
        exit 1
    fi
done

MW="$WORK_BASE/$STUDY/Mapped"      # scratch working dir
mkdir -p "$MW"

echo "==== GG2 non-v4-16s mapping for $STUDY ===="
echo "table    : $MAP_INPUT_TABLE"
echo "seqs     : $MAP_INPUT_SEQS"
echo "backbone : $GG2_BACKBONE"
echo "perc_id  : $GG2_MAP_PERC_IDENTITY   threads=$THREADS"

# --- 1. Closed-reference mapping onto the GG2 backbone -----------------------
qiime greengenes2 non-v4-16s \
    --i-table "$MAP_INPUT_TABLE" \
    --i-sequences "$MAP_INPUT_SEQS" \
    --i-backbone "$GG2_BACKBONE" \
    --p-perc-identity "$GG2_MAP_PERC_IDENTITY" \
    --p-threads "$THREADS" \
    --o-mapped-table "$MW/mapped-table.qza" \
    --o-representatives "$MW/mapped-seqs.qza"

# --- 2. Summaries -----------------------------------------------------------
qiime feature-table summarize \
    --i-table "$MW/mapped-table.qza" \
    --o-visualization "$MW/mapped-table_viz.qzv"

qiime feature-table tabulate-seqs \
    --i-data "$MW/mapped-seqs.qza" \
    --o-visualization "$MW/mapped-seqs_viz.qzv"

# --- 3. Copy final artifacts back into the repo -----------------------------
DEST="$REPO_ROOT/$STUDY/Mapped"
mkdir -p "$DEST"
cp -f "$MW"/mapped-table.qza "$MW"/mapped-seqs.qza "$DEST"/
cp -f "$MW"/mapped-*.qzv "$DEST"/ 2>/dev/null || true

echo "==== Done. Mapped artifacts in $DEST ===="
echo "Next: once every study is mapped, merge the Mapped/mapped-table.qza +"
echo "      mapped-seqs.qza across studies, then dual taxonomy (tree + classifier)."
