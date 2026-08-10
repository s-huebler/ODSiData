#!/bin/bash
# =============================================================================
# 09_taxonomy_gg.slurm — tree-based taxonomy for the cohort (taxonomy-from-table)
#
# Step 3 of cohort assembly. Reads each merged feature's lineage straight off the
# GG2 taxonomy tree (GG2_TAXONOMY_TREE, the .taxonomy.asv.nwk.qza) via
# `qiime greengenes2 taxonomy-from-table`. This is the FIRST of the two taxonomy
# sources for the dissertation comparison; 09_taxonomy_classifier is the second.
#
# Needs the q2-greengenes2 plugin, so it activates the personal GG2 conda env
# (load_qiime2_gg2_env) rather than the qiime2 module.
#
# Outputs -> Merging/<cohort>/ :
#   taxonomy-gg.qza        per-feature tree-derived lineages
#   taxonomy-gg_viz.qzv    tabulated taxonomy
#   taxa-bar-gg.qzv        stacked barplot (if METADATA set)
#
# Submit via chpc/merge.sh:  ./chpc/merge.sh <cohort> tax-gg
# Standalone:
#   sbatch -A <acct> -p <part> \
#          --export=ALL,COHORT_FILE=merging/<cohort>.sh chpc/jobs/09_taxonomy_gg.slurm
# =============================================================================
#SBATCH --job-name=qiime-taxgg
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=24G
#SBATCH --time=04:00:00
#SBATCH --output=chpc/logs/taxgg_%j.out
#SBATCH --error=chpc/logs/taxgg_%j.err

set -euo pipefail

: "${COHORT_FILE:?COHORT_FILE must be exported (e.g. merging/full_cohort.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$COHORT_FILE"

load_qiime2_gg2_env
check_gg2_plugin

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
for f in "$MERGED_TABLE" "$GG2_TAXONOMY_TREE"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required input not found: $f" >&2
        [[ "$f" == "$MERGED_TABLE" ]]      && echo "       Run the merge stage first:  ./chpc/merge.sh $COHORT merge" >&2
        [[ "$f" == "$GG2_TAXONOMY_TREE" ]] && echo "       GG2_TAXONOMY_TREE ($GG2_VERSION.taxonomy.asv.nwk.qza) must be in $GG2_REF_DIR." >&2
        exit 1
    fi
done

echo "==== Tree-based taxonomy (taxonomy-from-table) for cohort '$COHORT' ===="
echo "table : $MERGED_TABLE"
echo "ref   : $GG2_TAXONOMY_TREE"

# --- 1. Pull lineage off the GG2 tree ---------------------------------------
qiime greengenes2 taxonomy-from-table \
    --i-reference-taxonomy "$GG2_TAXONOMY_TREE" \
    --i-table "$MERGED_TABLE" \
    --o-classification "$MW/taxonomy-gg.qza"

# --- 2. Summaries -----------------------------------------------------------
qiime metadata tabulate \
    --m-input-file "$MW/taxonomy-gg.qza" \
    --o-visualization "$MW/taxonomy-gg_viz.qzv"

if [[ -n "${METADATA:-}" && -f "${METADATA:-}" ]]; then
    qiime taxa barplot \
        --i-table "$MERGED_TABLE" \
        --i-taxonomy "$MW/taxonomy-gg.qza" \
        --m-metadata-file "$METADATA" \
        --o-visualization "$MW/taxa-bar-gg.qzv"
fi

# --- 3. Copy final artifacts into the repo ----------------------------------
cp -f "$MW"/taxonomy-gg.qza "$MDEST"/
cp -f "$MW"/taxonomy-gg_viz.qzv "$MDEST"/ 2>/dev/null || true
cp -f "$MW"/taxa-bar-gg.qzv "$MDEST"/ 2>/dev/null || true

echo "==== Done. taxonomy-gg.qza in $MDEST ===="
echo "Next: ./chpc/merge.sh $COHORT tax-classifier   (then compare the two taxonomies)"
