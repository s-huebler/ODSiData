#!/usr/bin/env bash
# =============================================================================
# chpc/submit.sh — one-command submission for a study's preprocessing.
# Chains: 01_fetch (job array over accessions) -> 02_import_dada2 (runs only if
# the fetch array succeeds, via SLURM --dependency=afterok).
#
# Usage (run from the repo root on CHPC):
#   ./chpc/submit.sh Artacho2024              # both steps
#   ./chpc/submit.sh Artacho2024 fetch        # download only
#   ./chpc/submit.sh Artacho2024 dada2        # import+DADA2 only (FASTQs present)
#
# Override allocation on the fly:
#   CHPC_ACCOUNT=my-alloc CHPC_PARTITION=notchpeak ./chpc/submit.sh Artacho2024
#
# Concurrency of the download array is controlled by ARRAY_THROTTLE (default 20).
# =============================================================================
set -euo pipefail

STUDY_NAME="${1:?usage: submit.sh <StudyName> [fetch|dada2|all]}"
STAGE="${2:-all}"
ARRAY_THROTTLE="${ARRAY_THROTTLE:-20}"

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
echo "Study=$STUDY_NAME  accessions=$N  account=$CHPC_ACCOUNT  partition=$CHPC_PARTITION"

SB=(sbatch -A "$CHPC_ACCOUNT" -p "$CHPC_PARTITION" --parsable --export=ALL,STUDY_FILE="$STUDY_FILE")

fetch_id=""
if [[ "$STAGE" == "all" || "$STAGE" == "fetch" ]]; then
    fetch_id=$("${SB[@]}" --array="1-${N}%${ARRAY_THROTTLE}" --time="$FETCH_TIME" chpc/jobs/01_fetch.slurm)
    echo "Submitted fetch array: job $fetch_id (1-$N, throttle $ARRAY_THROTTLE)"
fi

if [[ "$STAGE" == "all" || "$STAGE" == "dada2" ]]; then
    DEP=()
    [[ -n "$fetch_id" ]] && DEP=(--dependency="afterok:${fetch_id}")
    dada2_id=$("${SB[@]}" "${DEP[@]}" --time="$DADA2_TIME" --cpus-per-task="$DADA2_THREADS" chpc/jobs/02_import_dada2.slurm)
    echo "Submitted DADA2: job $dada2_id ${DEP:+(after $fetch_id)}"
fi

echo "Track with: squeue -u \$USER   |   logs in chpc/logs/"
