#!/usr/bin/env bash
# =============================================================================
# chpc/submit.sh — submit a study's preprocessing stages.
# Stages: fetch (SRA download array) -> import (QIIME2 import + demux summary)
#         -> [INSPECT demux_viz.qzv, set trunc lengths] -> dada2 (denoise+export)
#
# Usage (run from the repo root on CHPC):
#   ./chpc/submit.sh Artacho2024              # 'all' = fetch -> import, then STOP
#   ./chpc/submit.sh Artacho2024 fetch        # download only
#   ./chpc/submit.sh Artacho2024 import       # import + demux summary only
#   ./chpc/submit.sh Artacho2024 dada2        # denoise (after you set trunc lens)
#
# 'all' intentionally stops after import so you can inspect the read-quality plot
# and choose DADA2 truncation lengths before denoising. Run 'dada2' separately.
#
# Override allocation on the fly:
#   CHPC_ACCOUNT=my-alloc CHPC_PARTITION=notchpeak ./chpc/submit.sh Artacho2024
#
# Download array concurrency is controlled by ARRAY_THROTTLE (default 20).
# =============================================================================
set -euo pipefail

STUDY_NAME="${1:?usage: submit.sh <StudyName> [all|fetch|import|dada2]}"
STAGE="${2:-all}"
ARRAY_THROTTLE="${ARRAY_THROTTLE:-20}"

case "$STAGE" in
    all|fetch|import|dada2) ;;
    *) echo "Unknown stage '$STAGE' (expected: all|fetch|import|dada2)"; exit 1 ;;
esac

# Resolve repo root as the parent of this script's dir; run from there.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

STUDY_FILE="studies/${STUDY_NAME}.sh"
[[ -f "chpc/$STUDY_FILE" ]] || { echo "No study file at chpc/$STUDY_FILE"; exit 1; }

# Load config + study to read allocation, accession count, and walltimes.
source chpc/config.sh
source "chpc/$STUDY_FILE"
check_allocation

N=$(grep -cve '^[[:space:]]*$' "$ACCESSIONS")   # non-blank accession lines
echo "Study=$STUDY_NAME  stage=$STAGE  accessions=$N  account=$CHPC_ACCOUNT  partition=$CHPC_PARTITION"

SB=(sbatch -A "$CHPC_ACCOUNT" -p "$CHPC_PARTITION" --parsable --export=ALL,STUDY_FILE="$STUDY_FILE")

# --- fetch (job array over accessions) --------------------------------------
fetch_id=""
if [[ "$STAGE" == "all" || "$STAGE" == "fetch" ]]; then
    fetch_id=$("${SB[@]}" --array="1-${N}%${ARRAY_THROTTLE}" --time="$FETCH_TIME" chpc/jobs/01_fetch.slurm)
    echo "Submitted fetch array: job $fetch_id (1-$N, throttle $ARRAY_THROTTLE)"
fi

# --- import (chains after fetch in 'all'); STOP here to inspect demux_viz -----
if [[ "$STAGE" == "all" || "$STAGE" == "import" ]]; then
    DEP=()
    [[ -n "$fetch_id" ]] && DEP=(--dependency="afterok:${fetch_id}")
    import_id=$("${SB[@]}" "${DEP[@]}" --time="${IMPORT_TIME:-04:00:00}" chpc/jobs/02_import.slurm)
    echo "Submitted import: job $import_id ${fetch_id:+(after $fetch_id)}"
fi

# --- dada2 (run manually AFTER inspecting demux_viz.qzv + setting trunc lens) -
if [[ "$STAGE" == "dada2" ]]; then
    dada2_id=$("${SB[@]}" --time="$DADA2_TIME" --cpus-per-task="$DADA2_THREADS" chpc/jobs/03_dada2.slurm)
    echo "Submitted DADA2: job $dada2_id"
fi

if [[ "$STAGE" == "all" || "$STAGE" == "import" ]]; then
    echo
    echo "NEXT: when import finishes, inspect $STUDY_NAME/QiimeData/demux_viz.qzv,"
    echo "      set TRUNC_LEN_F/TRUNC_LEN_R in chpc/$STUDY_FILE, then:"
    echo "      ./chpc/submit.sh $STUDY_NAME dada2"
fi

echo "Track with: squeue -u \$USER   |   logs in chpc/logs/"
