#!/bin/bash
# =============================================================================
# 09_taxonomy_classifier.slurm — classifier taxonomy for the cohort (sklearn)
#
# Step 4 of cohort assembly. Classifies the merged rep-seqs with the full-length
# Greengenes2 naive-Bayes classifier (GG2_CLASSIFIER) via classify-sklearn — the
# SECOND taxonomy source, to compare against the tree-based one from
# 09_taxonomy_gg.slurm. Confidence defaults to 0.9 (matches Merging.qmd).
#
# Uses the qiime2 module (classify-sklearn is core; no plugin needed). Routed by
# merge.sh to notchpeak-shared-short so the AVX2 scikit-learn stack doesn't SIGILL
# on old lonepeak cores (same lesson as the qc stage).
#
# Outputs -> Merging/<cohort>/ :
#   taxonomy-classifier.qza        per-feature classifier lineages
#   taxonomy-classifier_viz.qzv    tabulated taxonomy
#   taxa-bar-classifier.qzv        stacked barplot (if METADATA set)
#
# Submit via chpc/merge.sh:  ./chpc/merge.sh <cohort> tax-classifier
# Standalone:
#   sbatch -A <acct> -p <part> \
#          --export=ALL,COHORT_FILE=merging/<cohort>.sh chpc/jobs/09_taxonomy_classifier.slurm
# =============================================================================
#SBATCH --job-name=qiime-taxcl
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --output=chpc/logs/taxcl_%j.out
#SBATCH --error=chpc/logs/taxcl_%j.err

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
MW="$WORK_BASE/Merging/$COHORT"
MDEST="$REPO_ROOT/Merging/$COHORT"
mkdir -p "$MW" "$MDEST"

MERGED_SEQS="$MDEST/merged-seqs.qza"
MERGED_TABLE="$MDEST/merged-table.qza"
CLASSIFIER_CONFIDENCE="${CLASSIFIER_CONFIDENCE:-0.9}"
THREADS="${SLURM_CPUS_PER_TASK:-${TAXCL_THREADS:-8}}"

# --- Preconditions ----------------------------------------------------------
for f in "$MERGED_SEQS" "$GG2_CLASSIFIER"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required input not found: $f" >&2
        [[ "$f" == "$MERGED_SEQS" ]]   && echo "       Run the merge stage first:  ./chpc/merge.sh $COHORT merge" >&2
        [[ "$f" == "$GG2_CLASSIFIER" ]] && echo "       GG2_CLASSIFIER is set in chpc/config.sh." >&2
        exit 1
    fi
done

echo "==== Classifier taxonomy (classify-sklearn) for cohort '$COHORT' ===="
echo "seqs       : $MERGED_SEQS"
echo "classifier : $GG2_CLASSIFIER"
echo "confidence : $CLASSIFIER_CONFIDENCE   n-jobs=$THREADS"

# --- 1. classify-sklearn ----------------------------------------------------
qiime feature-classifier classify-sklearn \
    --i-classifier "$GG2_CLASSIFIER" \
    --i-reads "$MERGED_SEQS" \
    --p-confidence "$CLASSIFIER_CONFIDENCE" \
    --p-n-jobs "$THREADS" \
    --o-classification "$MW/taxonomy-classifier.qza"

# --- 2. Summaries -----------------------------------------------------------
qiime metadata tabulate \
    --m-input-file "$MW/taxonomy-classifier.qza" \
    --o-visualization "$MW/taxonomy-classifier_viz.qzv"

if [[ -n "${METADATA:-}" && -f "${METADATA:-}" && -f "$MERGED_TABLE" ]]; then
    qiime taxa barplot \
        --i-table "$MERGED_TABLE" \
        --i-taxonomy "$MW/taxonomy-classifier.qza" \
        --m-metadata-file "$METADATA" \
        --o-visualization "$MW/taxa-bar-classifier.qzv"
fi

# --- 3. Copy final artifacts into the repo ----------------------------------
cp -f "$MW"/taxonomy-classifier.qza "$MDEST"/
cp -f "$MW"/taxonomy-classifier_viz.qzv "$MDEST"/ 2>/dev/null || true
cp -f "$MW"/taxa-bar-classifier.qzv "$MDEST"/ 2>/dev/null || true

echo "==== Done. taxonomy-classifier.qza in $MDEST ===="
echo "Compare against taxonomy-gg.qza (e.g. rescript evaluate-taxonomy, or the two barplots)."
