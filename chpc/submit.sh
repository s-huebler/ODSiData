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
# The denoise stage is layout-aware, driven by LAYOUT in the study file:
#   LAYOUT="paired" (default) -> 02_import.slurm        + 03_dada2.slurm
#   LAYOUT="single"           -> 02_import_single.slurm + 03_deblur_single.slurm
# The denoise stage accepts 'dada2', 'deblur', or the generic 'denoise' — all
# route to whichever job matches the study's layout.
#
# 'all' intentionally stops after import so you can inspect the read-quality plot
# and choose truncation / trim lengths before denoising. Run the denoise stage
# separately.
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
    all|fetch|import|dada2|deblur|denoise) ;;
    *) echo "Unknown stage '$STAGE' (expected: all|fetch|import|dada2|deblur|denoise)"; exit 1 ;;
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

# --- Resolve layout -> import/denoise jobs and their resources --------------
LAYOUT="${LAYOUT:-paired}"
case "$LAYOUT" in
    paired)
        IMPORT_JOB="chpc/jobs/02_import.slurm"
        DENOISE_JOB="chpc/jobs/03_dada2.slurm"
        DENOISE_TIME="${DADA2_TIME:?set DADA2_TIME in the study file}"
        DENOISE_THREADS="${DADA2_THREADS:?set DADA2_THREADS in the study file}"
        DENOISE_LABEL="DADA2"
        ;;
    single)
        IMPORT_JOB="chpc/jobs/02_import_single.slurm"
        DENOISE_JOB="chpc/jobs/03_deblur_single.slurm"
        DENOISE_TIME="${DEBLUR_TIME:?set DEBLUR_TIME in the study file}"
        DENOISE_THREADS="${DEBLUR_THREADS:?set DEBLUR_THREADS in the study file}"
        DENOISE_LABEL="Deblur"
        ;;
    *) echo "Unknown LAYOUT '$LAYOUT' in study file (expected: paired|single)"; exit 1 ;;
esac
# Normalize the denoise stage aliases to a single internal trigger.
[[ "$STAGE" == "dada2" || "$STAGE" == "deblur" || "$STAGE" == "denoise" ]] && STAGE="denoise"

N=$(grep -cve '^[[:space:]]*$' "$ACCESSIONS")   # non-blank accession lines
echo "Study=$STUDY_NAME  stage=$STAGE  layout=$LAYOUT  accessions=$N  account=$CHPC_ACCOUNT  partition=$CHPC_PARTITION"

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
    import_id=$("${SB[@]}" "${DEP[@]}" --time="${IMPORT_TIME:-04:00:00}" "$IMPORT_JOB")
    echo "Submitted import: job $import_id ${fetch_id:+(after $fetch_id)}  [$IMPORT_JOB]"
fi

# --- denoise (run manually AFTER inspecting demux_viz.qzv + setting lengths) --
if [[ "$STAGE" == "denoise" ]]; then
    denoise_id=$("${SB[@]}" --time="$DENOISE_TIME" --cpus-per-task="$DENOISE_THREADS" "$DENOISE_JOB")
    echo "Submitted $DENOISE_LABEL: job $denoise_id  [$DENOISE_JOB]"
fi

if [[ "$STAGE" == "all" || "$STAGE" == "import" ]]; then
    echo
    echo "NEXT: when import finishes, inspect $STUDY_NAME/QiimeData/demux_viz.qzv,"
    if [[ "$LAYOUT" == "single" ]]; then
        echo "      set TRIM_LENGTH in chpc/$STUDY_FILE, then:"
        echo "      ./chpc/submit.sh $STUDY_NAME deblur"
    else
        echo "      set TRUNC_LEN_F/TRUNC_LEN_R in chpc/$STUDY_FILE, then:"
        echo "      ./chpc/submit.sh $STUDY_NAME dada2"
    fi
fi

echo "Track with: squeue -u \$USER   |   logs in chpc/logs/"
