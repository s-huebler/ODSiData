#!/bin/bash
# =============================================================================
# 07_merge.slurm — merge mapped tables + rep-seqs across a cohort of studies
#
# Step 1 of the cohort-assembly phase (driven by chpc/merge.sh, NOT submit.sh).
# Reads each study's GG2-mapped artifacts (from 06_gg2_map.slurm) and merges them
# into one cohort table + one cohort rep-seqs set. Because every study was mapped
# into the SAME GG2 backbone namespace, a feature shared across studies has the
# same ID here, so the merge is biologically meaningful (not just block-stacked).
#
# The cohort — which studies, and which artifact per study — is defined in
# chpc/merging/<cohort>.sh (STUDIES=(...), TABLE_OVERRIDE / SEQS_OVERRIDE).
#
# Outputs -> Merging/<cohort>/ :
#   merged-table.qza   cohort feature table (GG2 backbone namespace)
#   merged-seqs.qza    cohort representative sequences
#   *.qzv              table summary + rep-seqs tabulation
#
# Submit via chpc/merge.sh:  ./chpc/merge.sh <cohort> merge
# Standalone:
#   sbatch -A <acct> -p <part> \
#          --export=ALL,COHORT_FILE=merging/<cohort>.sh chpc/jobs/07_merge.slurm
# =============================================================================
#SBATCH --job-name=qiime-merge
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=chpc/logs/merge_%j.out
#SBATCH --error=chpc/logs/merge_%j.err

set -euo pipefail

: "${COHORT_FILE:?COHORT_FILE must be exported (e.g. merging/full_cohort.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$COHORT_FILE"

load_qiime2_env

if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

: "${COHORT:?set COHORT in the cohort file}"
: "${STUDIES:?set STUDIES=(...) in the cohort file}"
MAPPED_TABLE_NAME="${MAPPED_TABLE_NAME:-mapped-table.qza}"
MAPPED_SEQS_NAME="${MAPPED_SEQS_NAME:-mapped-seqs.qza}"
# Tolerate a cohort file that doesn't declare the override maps.
declare -p TABLE_OVERRIDE >/dev/null 2>&1 || declare -A TABLE_OVERRIDE=()
declare -p SEQS_OVERRIDE  >/dev/null 2>&1 || declare -A SEQS_OVERRIDE=()

MW="$WORK_BASE/Merging/$COHORT"      # scratch working dir
MDEST="$REPO_ROOT/Merging/$COHORT"   # committed cohort outputs
mkdir -p "$MW" "$MDEST"

# --- Resolve per-study inputs (override wins; else <Study>/Mapped/<name>) -----
tables=(); seqs=()
echo "==== Merge cohort '$COHORT' (${#STUDIES[@]} studies) ===="
for s in "${STUDIES[@]}"; do
    t="${TABLE_OVERRIDE[$s]:-$REPO_ROOT/$s/Mapped/$MAPPED_TABLE_NAME}"
    q="${SEQS_OVERRIDE[$s]:-$REPO_ROOT/$s/Mapped/$MAPPED_SEQS_NAME}"
    [[ -f "$t" ]] || { echo "ERROR: missing mapped table for $s: $t" >&2; echo "       Run: ./chpc/submit.sh $s map" >&2; exit 1; }
    [[ -f "$q" ]] || { echo "ERROR: missing mapped seqs  for $s: $q" >&2; echo "       Run: ./chpc/submit.sh $s map" >&2; exit 1; }
    echo "  $s -> $t | $q"
    tables+=("$t"); seqs+=("$q")
done

# --- 1. Merge tables + rep-seqs ---------------------------------------------
# Sample IDs are distinct across studies (default overlap method errors if not,
# which is the safety we want); features shared via the backbone namespace union.
qiime feature-table merge \
    --i-tables "${tables[@]}" \
    --o-merged-table "$MW/merged-table.qza"

qiime feature-table merge-seqs \
    --i-data "${seqs[@]}" \
    --o-merged-data "$MW/merged-seqs.qza"

# --- 2. Summaries -----------------------------------------------------------
if [[ -n "${METADATA:-}" && -f "${METADATA:-}" ]]; then
    qiime feature-table summarize \
        --i-table "$MW/merged-table.qza" \
        --m-sample-metadata-file "$METADATA" \
        --o-visualization "$MW/merged-table_viz.qzv"
else
    qiime feature-table summarize \
        --i-table "$MW/merged-table.qza" \
        --o-visualization "$MW/merged-table_viz.qzv"
fi

qiime feature-table tabulate-seqs \
    --i-data "$MW/merged-seqs.qza" \
    --o-visualization "$MW/merged-seqs_viz.qzv"

# --- 3. Copy final artifacts into the repo ----------------------------------
cp -f "$MW"/merged-table.qza "$MW"/merged-seqs.qza "$MDEST"/
cp -f "$MW"/*.qzv "$MDEST"/ 2>/dev/null || true

echo "==== Done. Cohort artifacts in $MDEST ===="
echo "Next: ./chpc/merge.sh $COHORT phylogeny   (or run the full chain with 'all')"
