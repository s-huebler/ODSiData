#!/bin/bash
# =============================================================================
# 05_qc.slurm — high-confidence assignment gate (classify-consensus-vsearch)
#
# Step 1 of the Greengenes2 mapping pipeline. Takes a study's ASV table +
# rep-seqs, classifies every ASV against the GG2 backbone with vsearch under an
# identity + query-coverage threshold, and DROPS anything that fails to assign
# (Unassigned). The point is to keep only reads with a high probability of a
# confident taxonomic assignment — no rare / novel-taxa tail — before the
# closed-reference mapping in 06_gg2_map.slurm.
#
# Inputs (defaults resolved below; override in chpc/studies/<Study>.sh):
#   QC_INPUT_TABLE  default $REPO_ROOT/<Study>/QiimeData/table.qza
#   QC_INPUT_SEQS   default $REPO_ROOT/<Study>/QiimeData/rep-seqs.qza
#   GG2_REF_SEQS / GG2_REF_TAX  the GG2 backbone seqs + taxonomy (config.sh)
#
# Outputs -> <Study>/Mapped/ (new subfolder, created here):
#   qc-taxonomy.qza     per-ASV vsearch classification
#   qc-search.qza       vsearch search results (hits behind each call)
#   qc-table.qza        input table filtered to confidently-assigned features
#   qc-seqs.qza         input rep-seqs filtered to the same features
#   *.qzv               taxonomy + filtered-table summaries
#
# Submit via chpc/submit.sh (per study):
#   ./chpc/submit.sh <Study> qc
# Standalone:
#   sbatch -A <acct> -p <part> \
#          --export=ALL,STUDY_FILE=studies/<Study>.sh chpc/jobs/05_qc.slurm
# =============================================================================
#SBATCH --job-name=qiime-qc
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --output=chpc/logs/qc_%j.out
#SBATCH --error=chpc/logs/qc_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/Liu2017.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for vsearch intermediates ------------------------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

THREADS="${SLURM_CPUS_PER_TASK:-${QC_THREADS:-8}}"

# --- Resolve inputs (study file may override; else this study's DADA2 out) ---
QC_INPUT_TABLE="${QC_INPUT_TABLE:-$REPO_ROOT/$STUDY/QiimeData/table.qza}"
QC_INPUT_SEQS="${QC_INPUT_SEQS:-$REPO_ROOT/$STUDY/QiimeData/rep-seqs.qza}"

# --- Classification thresholds (config.sh defaults; study file may override) --
QC_PERC_IDENTITY="${QC_PERC_IDENTITY:-0.97}"
QC_QUERY_COV="${QC_QUERY_COV:-0.90}"
QC_MAXACCEPTS="${QC_MAXACCEPTS:-10}"
QC_MIN_CONSENSUS="${QC_MIN_CONSENSUS:-0.51}"
QC_TOP_HITS_ONLY="${QC_TOP_HITS_ONLY:-false}"
QC_EXCLUDE="${QC_EXCLUDE:-Unassigned}"

# --- Preconditions ----------------------------------------------------------
for f in "$QC_INPUT_TABLE" "$QC_INPUT_SEQS" "$GG2_REF_SEQS" "$GG2_REF_TAX"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required input not found: $f" >&2
        if [[ "$f" == "$GG2_REF_SEQS" || "$f" == "$GG2_REF_TAX" ]]; then
            echo "       GG2 backbone reference artifacts are set in chpc/config.sh" >&2
            echo "       (GG2_REF_SEQS / GG2_REF_TAX). Download the ${GG2_VERSION} release from" >&2
            echo "       ftp.microbio.me/greengenes_release/${GG2_VERSION}/ into $GG2_REF_DIR/" >&2
        fi
        exit 1
    fi
done

MW="$WORK_BASE/$STUDY/Mapped"      # scratch working dir
mkdir -p "$MW"

echo "==== QC gate (classify-consensus-vsearch) for $STUDY ===="
echo "table   : $QC_INPUT_TABLE"
echo "seqs    : $QC_INPUT_SEQS"
echo "ref     : $GG2_REF_SEQS  (+ $GG2_REF_TAX)"
echo "thresh  : perc_identity=$QC_PERC_IDENTITY query_cov=$QC_QUERY_COV min_consensus=$QC_MIN_CONSENSUS maxaccepts=$QC_MAXACCEPTS top_hits_only=$QC_TOP_HITS_ONLY"
echo "exclude : $QC_EXCLUDE   threads=$THREADS"

# --- 1. Classify ASVs against the GG2 backbone ------------------------------
TOP_HITS_FLAG="--p-no-top-hits-only"
[[ "$QC_TOP_HITS_ONLY" == "true" ]] && TOP_HITS_FLAG="--p-top-hits-only"

qiime feature-classifier classify-consensus-vsearch \
    --i-query "$QC_INPUT_SEQS" \
    --i-reference-reads "$GG2_REF_SEQS" \
    --i-reference-taxonomy "$GG2_REF_TAX" \
    --p-perc-identity "$QC_PERC_IDENTITY" \
    --p-query-cov "$QC_QUERY_COV" \
    --p-maxaccepts "$QC_MAXACCEPTS" \
    --p-min-consensus "$QC_MIN_CONSENSUS" \
    $TOP_HITS_FLAG \
    --p-threads "$THREADS" \
    --o-classification "$MW/qc-taxonomy.qza" \
    --o-search-results "$MW/qc-search.qza"

# --- 2. Drop features that failed to assign (the high-confidence gate) -------
qiime taxa filter-table \
    --i-table "$QC_INPUT_TABLE" \
    --i-taxonomy "$MW/qc-taxonomy.qza" \
    --p-exclude "$QC_EXCLUDE" \
    --o-filtered-table "$MW/qc-table.qza"

qiime taxa filter-seqs \
    --i-sequences "$QC_INPUT_SEQS" \
    --i-taxonomy "$MW/qc-taxonomy.qza" \
    --p-exclude "$QC_EXCLUDE" \
    --o-filtered-sequences "$MW/qc-seqs.qza"

# --- 3. Summaries -----------------------------------------------------------
qiime metadata tabulate \
    --m-input-file "$MW/qc-taxonomy.qza" \
    --o-visualization "$MW/qc-taxonomy_viz.qzv"

qiime feature-table summarize \
    --i-table "$MW/qc-table.qza" \
    --o-visualization "$MW/qc-table_viz.qzv"

# --- 4. Copy final artifacts back into the repo -----------------------------
DEST="$REPO_ROOT/$STUDY/Mapped"
mkdir -p "$DEST"
cp -f "$MW"/qc-taxonomy.qza "$MW"/qc-search.qza "$MW"/qc-table.qza "$MW"/qc-seqs.qza "$DEST"/
cp -f "$MW"/*.qzv "$DEST"/ 2>/dev/null || true

echo "==== Done. Filtered artifacts in $DEST ===="
echo "Next: inspect $STUDY/Mapped/qc-taxonomy_viz.qzv + qc-table_viz.qzv, then map:"
echo "      ./chpc/submit.sh $STUDY map"
