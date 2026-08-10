#!/bin/bash
# =============================================================================
# 08_phylogeny.slurm — cohort phylogeny by filtering the GG2 reference tree
#
# Step 2 of cohort assembly (depends on 07_merge). The GG2 backbone phylogeny
# already contains every mapped feature as a tip, so we don't build a tree — we
# FILTER the reference tree (GG2_PHYLOGENY) down to the cohort's merged features.
# The result is a rooted tree spanning exactly the cohort table, ready for
# phylogenetic diversity (Faith's PD, UniFrac) in core-metrics-phylogenetic.
#
# Depends only on the merge output; taxonomy (09) is independent of this step.
#
# Outputs -> Merging/<cohort>/ :
#   merged-tree.qza    GG2 tree filtered to the cohort features
#
# Submit via chpc/merge.sh:  ./chpc/merge.sh <cohort> phylogeny
# Standalone:
#   sbatch -A <acct> -p <part> \
#          --export=ALL,COHORT_FILE=merging/<cohort>.sh chpc/jobs/08_phylogeny.slurm
# =============================================================================
#SBATCH --job-name=qiime-phylo
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=02:00:00
#SBATCH --output=chpc/logs/phylo_%j.out
#SBATCH --error=chpc/logs/phylo_%j.err

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
trap 'rm -rf "$TMPDIR"' EXIT

: "${COHORT:?set COHORT in the cohort file}"
MW="$WORK_BASE/Merging/$COHORT"
MDEST="$REPO_ROOT/Merging/$COHORT"
mkdir -p "$MW" "$MDEST"

MERGED_TABLE="$MDEST/merged-table.qza"

# --- Preconditions ----------------------------------------------------------
for f in "$MERGED_TABLE" "$GG2_PHYLOGENY"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required input not found: $f" >&2
        [[ "$f" == "$MERGED_TABLE" ]]  && echo "       Run the merge stage first:  ./chpc/merge.sh $COHORT merge" >&2
        [[ "$f" == "$GG2_PHYLOGENY" ]] && echo "       GG2 phylogeny is set in chpc/config.sh (GG2_PHYLOGENY)." >&2
        exit 1
    fi
done

echo "==== Filter GG2 tree to cohort '$COHORT' ===="
echo "tree  : $GG2_PHYLOGENY"
echo "table : $MERGED_TABLE"

# --- Filter the reference phylogeny to the cohort's features -----------------
qiime phylogeny filter-tree \
    --i-tree "$GG2_PHYLOGENY" \
    --i-table "$MERGED_TABLE" \
    --o-filtered-tree "$MW/merged-tree.qza"

cp -f "$MW"/merged-tree.qza "$MDEST"/

echo "==== Done. merged-tree.qza in $MDEST ===="
echo "Next: ./chpc/merge.sh $COHORT tax-gg"
