#!/bin/bash
# =============================================================================
# 08_phylogeny.slurm — cohort phylogeny by pruning the GG2 reference tree
#
# Step 2 of cohort assembly (depends on 07_merge). The GG2 backbone phylogeny
# already contains every mapped feature as a tip, so we don't build a tree — we
# PRUNE the reference tree (GG2_PHYLOGENY) down to the cohort's merged features.
# The result is a rooted tree spanning exactly the cohort table, ready for
# phylogenetic diversity (Faith's PD, UniFrac) in core-metrics-phylogenetic.
#
# We do the prune with chpc/lib/prune_gg2_tree.py (bp / iow "shear") instead of
# `qiime phylogeny filter-tree`. filter-tree inflates the whole 23.4M-tip GG2
# tree into a scikit-bio object graph (~80-150 GB RAM) before pruning to the
# cohort's ~5k features — that is what forced this stage onto a 240 GB node and
# made it slow. The bp succinct structure holds the same tree in ~2-4 GB, so the
# prune runs in minutes on an ordinary shared node. The pruned tree is identical;
# the script emits Newick, and we re-import it to a .qza here (trivial — only a
# few thousand tips).
#
# bp (iow) + biom ship in the personal q2-greengenes2 env (GG2_ENV), so this job
# uses load_qiime2_gg2_env (same env as 09_taxonomy_gg). Its compiled deps use
# AVX2, so run on a modern node (notchpeak-shared-short), not old lonepeak cores.
#
# Depends only on the merge output; taxonomy (09) is independent of this step.
#
# Outputs -> Merging/<cohort>/ :
#   merged-tree.nwk    GG2 tree pruned to the cohort features (Newick)
#   merged-tree.qza    same tree wrapped as Phylogeny[Rooted]
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
#SBATCH --time=01:00:00
#SBATCH --output=chpc/logs/phylo_%j.out
#SBATCH --error=chpc/logs/phylo_%j.err

set -euo pipefail

: "${COHORT_FILE:?COHORT_FILE must be exported (e.g. merging/full_cohort.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$COHORT_FILE"

load_qiime2_gg2_env

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

MERGED_TABLE="$MDEST/merged-table.qza"
PRUNE_SCRIPT="$REPO_ROOT/chpc/lib/prune_gg2_tree.py"

# --- Preconditions ----------------------------------------------------------
for f in "$MERGED_TABLE" "$GG2_PHYLOGENY" "$PRUNE_SCRIPT"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required input not found: $f" >&2
        [[ "$f" == "$MERGED_TABLE" ]]  && echo "       Run the merge stage first:  ./chpc/merge.sh $COHORT merge" >&2
        [[ "$f" == "$GG2_PHYLOGENY" ]] && echo "       GG2 phylogeny is set in chpc/config.sh (GG2_PHYLOGENY)." >&2
        [[ "$f" == "$PRUNE_SCRIPT" ]]  && echo "       Expected the pruning helper at chpc/lib/prune_gg2_tree.py." >&2
        exit 1
    fi
done

echo "==== Prune GG2 tree to cohort '$COHORT' (bp shear) ===="
echo "tree  : $GG2_PHYLOGENY"
echo "table : $MERGED_TABLE"
echo "script: $PRUNE_SCRIPT"

# --- Prune the reference phylogeny to the cohort's features ------------------
python "$PRUNE_SCRIPT" \
    --tree  "$GG2_PHYLOGENY" \
    --table "$MERGED_TABLE" \
    --out   "$MW/merged-tree.nwk"

# --- Wrap the small pruned tree into a QIIME2 artifact (fast; few-k tips) ----
rm -f "$MW/merged-tree.qza"
qiime tools import \
    --input-path "$MW/merged-tree.nwk" \
    --output-path "$MW/merged-tree.qza" \
    --type 'Phylogeny[Rooted]'

cp -f "$MW"/merged-tree.nwk "$MDEST"/
cp -f "$MW"/merged-tree.qza "$MDEST"/

echo "==== Done. merged-tree.nwk + merged-tree.qza in $MDEST ===="
echo "Next: ./chpc/merge.sh $COHORT tax-gg"
