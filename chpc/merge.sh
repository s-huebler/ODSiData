#!/usr/bin/env bash
# =============================================================================
# chpc/merge.sh — cohort-assembly driver (the merge phase).
#
# The sibling of submit.sh. Where submit.sh is PER-STUDY (fetch -> ... -> map),
# merge.sh is PER-COHORT: it merges the GG2-mapped tables/seqs of a SET of
# studies and derives the cohort phylogeny + taxonomies. It shares config.sh with
# submit.sh but is otherwise standalone (its own small sbatch helper) so the two
# drivers stay decoupled.
#
# Stages (run in this order; 'all' chains them with afterok dependencies so each
# starts only if the previous succeeds — kept sequential even though phylogeny
# and the taxonomies are technically independent of one another):
#   merge          -> 07_merge.slurm             (feature-table merge + merge-seqs)
#   phylogeny      -> 08_phylogeny.slurm         (filter GG2 tree to the cohort)
#   tax-gg         -> 09_taxonomy_gg.slurm       (taxonomy-from-table, tree-based)
#   tax-classifier -> 09_taxonomy_classifier.slurm (classify-sklearn, full-length)
#
# The cohort (which studies, which artifact per study, resources) is defined in
# chpc/merging/<cohort>.sh. Outputs go to Merging/<cohort>/.
#
# Usage (run from the repo root on CHPC):
#   ./chpc/merge.sh full_cohort            # 'all' = merge -> phylogeny -> tax-gg -> tax-classifier
#   ./chpc/merge.sh full_cohort merge      # just the merge
#   ./chpc/merge.sh full_cohort phylogeny  # just the tree filter
#   ./chpc/merge.sh full_cohort tax-gg     # just the tree taxonomy
#   ./chpc/merge.sh full_cohort tax-classifier   # just the classifier taxonomy
#
# Override allocation on the fly:
#   MERGE_PARTITION=lonepeak-shared MERGE_CLUSTER=lonepeak ./chpc/merge.sh full_cohort
# =============================================================================
set -euo pipefail

COHORT_NAME="${1:?usage: merge.sh <cohort> [all|merge|phylogeny|tax-gg|tax-classifier]}"
STAGE="${2:-all}"

case "$STAGE" in
    all|merge|phylogeny|tax-gg|tax-classifier) ;;
    *) echo "Unknown stage '$STAGE' (expected: all|merge|phylogeny|tax-gg|tax-classifier)"; exit 1 ;;
esac

# Resolve repo root as the parent of this script's dir; run from there.
REPO_ROOT_LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT_LOCAL"

COHORT_FILE="merging/${COHORT_NAME}.sh"
[[ -f "chpc/$COHORT_FILE" ]] || { echo "No cohort file at chpc/$COHORT_FILE"; exit 1; }

source chpc/config.sh
source "chpc/$COHORT_FILE"
check_allocation

: "${STUDIES:?set STUDIES=(...) in chpc/$COHORT_FILE}"

# --- Compute target ----------------------------------------------------------
# Default the whole merge phase to notchpeak-shared-short: modern (AVX2) nodes,
# free, <=8h walltime — every merge stage fits, and it sidesteps the lonepeak
# Nehalem SIGILL that forced qc/map off lonepeak. Override via env or cohort file.
MERGE_ACCOUNT="${MERGE_ACCOUNT:-notchpeak-shared-short}"
MERGE_PARTITION="${MERGE_PARTITION:-notchpeak-shared-short}"
MERGE_CLUSTER="${MERGE_CLUSTER:-notchpeak}"

# --- Per-stage resources (cohort file may override; else these defaults) ------
MERGE_TIME="${MERGE_TIME:-02:00:00}"; MERGE_MEM="${MERGE_MEM:-16G}"
PHYLO_TIME="${PHYLO_TIME:-02:00:00}"; PHYLO_MEM="${PHYLO_MEM:-256G}"
TAXGG_TIME="${TAXGG_TIME:-04:00:00}"; TAXGG_MEM="${TAXGG_MEM:-24G}"
TAXCL_TIME="${TAXCL_TIME:-08:00:00}"; TAXCL_MEM="${TAXCL_MEM:-32G}"; TAXCL_THREADS="${TAXCL_THREADS:-8}"

MERGE_JOB="chpc/jobs/07_merge.slurm"
PHYLO_JOB="chpc/jobs/08_phylogeny.slurm"
TAXGG_JOB="chpc/jobs/09_taxonomy_gg.slurm"
TAXCL_JOB="chpc/jobs/09_taxonomy_classifier.slurm"

echo "Cohort=$COHORT_NAME  stage=$STAGE  studies=${#STUDIES[@]}  account=$MERGE_ACCOUNT  partition=$MERGE_PARTITION  cluster=${MERGE_CLUSTER:-<login>}"

SB=(sbatch -A "$MERGE_ACCOUNT" -p "$MERGE_PARTITION" --parsable --export=ALL,COHORT_FILE="$COHORT_FILE")
[[ -n "${MERGE_CLUSTER:-}" ]] && SB+=(--clusters="$MERGE_CLUSTER")

# With --clusters, `sbatch --parsable` returns "jobid;cluster"; strip the suffix.
# Each sbatch is its own assignment so a rejected submission trips `set -e`.

merge_id=""; phylo_id=""; taxgg_id=""; taxcl_id=""

# --- merge (07) -------------------------------------------------------------
if [[ "$STAGE" == "all" || "$STAGE" == "merge" ]]; then
    merge_id=$("${SB[@]}" --time="$MERGE_TIME" --mem="$MERGE_MEM" "$MERGE_JOB"); merge_id=${merge_id%%;*}
    echo "Submitted merge (07): job $merge_id  [$MERGE_JOB]"
fi

# --- phylogeny (08); chains after merge in 'all' ----------------------------
if [[ "$STAGE" == "all" || "$STAGE" == "phylogeny" ]]; then
    DEP=(); [[ -n "$merge_id" ]] && DEP=(--dependency="afterok:${merge_id}")
    phylo_id=$("${SB[@]}" "${DEP[@]}" --time="$PHYLO_TIME" --mem="$PHYLO_MEM" "$PHYLO_JOB"); phylo_id=${phylo_id%%;*}
    echo "Submitted phylogeny (08): job $phylo_id ${merge_id:+(after $merge_id)}  [$PHYLO_JOB]"
fi

# --- tax-gg (09); chains after phylogeny in 'all' ---------------------------
if [[ "$STAGE" == "all" || "$STAGE" == "tax-gg" ]]; then
    DEP=(); [[ -n "$phylo_id" ]] && DEP=(--dependency="afterok:${phylo_id}")
    taxgg_id=$("${SB[@]}" "${DEP[@]}" --time="$TAXGG_TIME" --mem="$TAXGG_MEM" "$TAXGG_JOB"); taxgg_id=${taxgg_id%%;*}
    echo "Submitted taxonomy-gg (09): job $taxgg_id ${phylo_id:+(after $phylo_id)}  [$TAXGG_JOB]"
fi

# --- tax-classifier (09); chains after tax-gg in 'all' ----------------------
if [[ "$STAGE" == "all" || "$STAGE" == "tax-classifier" ]]; then
    DEP=(); [[ -n "$taxgg_id" ]] && DEP=(--dependency="afterok:${taxgg_id}")
    taxcl_id=$("${SB[@]}" "${DEP[@]}" --time="$TAXCL_TIME" --mem="$TAXCL_MEM" --cpus-per-task="$TAXCL_THREADS" "$TAXCL_JOB"); taxcl_id=${taxcl_id%%;*}
    echo "Submitted taxonomy-classifier (09): job $taxcl_id ${taxgg_id:+(after $taxgg_id)}  [$TAXCL_JOB]"
fi

echo
echo "Outputs -> Merging/$COHORT_NAME/    Track: squeue -M ${MERGE_CLUSTER:-all} -u \$USER    Logs: chpc/logs/"
