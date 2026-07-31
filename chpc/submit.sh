#!/usr/bin/env bash
# =============================================================================
# chpc/submit.sh — submit a study's preprocessing stages.
# Stages: fetch (SRA download array) -> import (QIIME2 import + demux summary)
#         -> [INSPECT demux_viz.qzv] -> trim (cutadapt primer removal)
#         -> [INSPECT demux_trimmed_viz.qzv, set trunc lengths]
#         -> denoise (denoise + export)
#
# Usage (run from the repo root on CHPC):
#   ./chpc/submit.sh Artacho2024              # 'all' = fetch -> import, then STOP
#   ./chpc/submit.sh Artacho2024 fetch        # download only
#   ./chpc/submit.sh Artacho2024 import       # import + demux summary only
#   ./chpc/submit.sh Artacho2024 trim         # cutadapt primer removal only
#   ./chpc/submit.sh Artacho2024 denoise      # denoise (after you set trunc lens)
#
# Both the trim and denoise stages are layout-aware, driven by LAYOUT in the
# study file:
#   LAYOUT="paired" (default) -> 02_import.slurm        + 03_trim_paired.slurm
#                                + 04_dada2_paired.slurm
#   LAYOUT="single"           -> 02_import_single.slurm + 03_trim_single.slurm
#                                + 04_<denoiser>.slurm
# Within LAYOUT="single", the denoiser is selectable via DENOISER in the study
# file (default "deblur"):
#   DENOISER="deblur"       -> 04_deblur.slurm       (Deblur; pre-merged reads)
#   DENOISER="pyro"         -> 04_dada2_pyro.slurm   (DADA2 denoise-pyro; 454/IonT)
#   DENOISER="dada2-single" -> 04_dada2_single.slurm (DADA2 denoise-single;
#                              true single-end / un-merged Illumina)
# The study file therefore declares WHICH denoise job to run; just call the
# generic 'denoise' stage. Legacy aliases 'dada2', 'dada2-single', 'deblur',
# 'pyro' are still accepted and route to the study's configured denoise job.
#
# The trim stage strips primers by sequence (paired: PRIMER_F/PRIMER_R;
# single: FWD_PRIMER/REV_PRIMER_RC) into demux_trimmed.qza; the denoise job
# auto-detects and prefers it. If no primers are set the trim stage is a no-op
# and denoise falls back to the raw demux.qza — so studies whose primers are
# already stripped upstream (e.g. Ingham2019) can skip 'trim' entirely.
#
# 'all' intentionally stops after import so you can inspect the read-quality plot
# before trimming/denoising. Run the trim and denoise stages separately.
#
# Override allocation on the fly:
#   CHPC_ACCOUNT=my-alloc CHPC_PARTITION=notchpeak ./chpc/submit.sh Artacho2024
#
# Download array concurrency is controlled by ARRAY_THROTTLE (default 20).
# =============================================================================
set -euo pipefail

STUDY_NAME="${1:?usage: submit.sh <StudyName> [all|fetch|import|trim|denoise]}"
STAGE="${2:-all}"
ARRAY_THROTTLE="${ARRAY_THROTTLE:-20}"

case "$STAGE" in
    all|fetch|import|trim|denoise|dada2|dada2-single|deblur|pyro) ;;
    *) echo "Unknown stage '$STAGE' (expected: all|fetch|import|trim|denoise)"; exit 1 ;;
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

# --- Resolve layout -> import/trim/denoise jobs and their resources ---------
LAYOUT="${LAYOUT:-paired}"
# Trim (cutadapt) resources are shared across denoisers; light + quick.
TRIM_TIME="${TRIM_TIME:-04:00:00}"
TRIM_THREADS="${TRIM_THREADS:-${CUTADAPT_THREADS:-8}}"
case "$LAYOUT" in
    paired)
        IMPORT_JOB="chpc/jobs/02_import.slurm"
        TRIM_JOB="chpc/jobs/03_trim_paired.slurm"
        DENOISE_JOB="chpc/jobs/04_dada2_paired.slurm"
        DENOISE_TIME="${DADA2_TIME:?set DADA2_TIME in the study file}"
        DENOISE_THREADS="${DADA2_THREADS:?set DADA2_THREADS in the study file}"
        DENOISE_LABEL="DADA2"
        ;;
    single)
        IMPORT_JOB="chpc/jobs/02_import_single.slurm"
        TRIM_JOB="chpc/jobs/03_trim_single.slurm"
        # Denoiser is selectable within the single layout (default deblur).
        case "${DENOISER:-deblur}" in
            deblur)
                DENOISE_JOB="chpc/jobs/04_deblur.slurm"
                DENOISE_TIME="${DEBLUR_TIME:?set DEBLUR_TIME in the study file}"
                DENOISE_THREADS="${DEBLUR_THREADS:?set DEBLUR_THREADS in the study file}"
                DENOISE_LABEL="Deblur"
                ;;
            pyro)
                DENOISE_JOB="chpc/jobs/04_dada2_pyro.slurm"
                DENOISE_TIME="${PYRO_TIME:-${DEBLUR_TIME:?set PYRO_TIME or DEBLUR_TIME in the study file}}"
                DENOISE_THREADS="${PYRO_THREADS:-${DEBLUR_THREADS:?set PYRO_THREADS or DEBLUR_THREADS in the study file}}"
                DENOISE_LABEL="DADA2-pyro"
                ;;
            dada2-single)
                DENOISE_JOB="chpc/jobs/04_dada2_single.slurm"
                DENOISE_TIME="${DADA2S_TIME:-${DADA2_TIME:?set DADA2S_TIME or DADA2_TIME in the study file}}"
                DENOISE_THREADS="${DADA2S_THREADS:-${DADA2_THREADS:?set DADA2S_THREADS or DADA2_THREADS in the study file}}"
                DENOISE_LABEL="DADA2-single"
                ;;
            *) echo "Unknown DENOISER '${DENOISER}' in study file (expected: deblur|pyro|dada2-single)"; exit 1 ;;
        esac
        ;;
    *) echo "Unknown LAYOUT '$LAYOUT' in study file (expected: paired|single)"; exit 1 ;;
esac
# Normalize the denoise stage aliases to a single internal trigger.
[[ "$STAGE" == "dada2" || "$STAGE" == "dada2-single" || "$STAGE" == "deblur" || "$STAGE" == "pyro" || "$STAGE" == "denoise" ]] && STAGE="denoise"

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

# --- trim (cutadapt primer removal; run AFTER import) ------------------------
if [[ "$STAGE" == "trim" ]]; then
    trim_id=$("${SB[@]}" --time="$TRIM_TIME" --cpus-per-task="$TRIM_THREADS" "$TRIM_JOB")
    echo "Submitted trim (cutadapt): job $trim_id  [$TRIM_JOB]"
fi

# --- denoise (run manually AFTER trim + inspecting the quality plot) ---------
if [[ "$STAGE" == "denoise" ]]; then
    denoise_id=$("${SB[@]}" --time="$DENOISE_TIME" --cpus-per-task="$DENOISE_THREADS" "$DENOISE_JOB")
    echo "Submitted $DENOISE_LABEL: job $denoise_id  [$DENOISE_JOB]"
fi

# Length variable(s) the denoise stage needs, per layout/denoiser.
case "$LAYOUT" in
    paired) LEN_VAR="TRUNC_LEN_F/TRUNC_LEN_R" ;;
    single)
        case "${DENOISER:-deblur}" in
            pyro)         LEN_VAR="PYRO_TRUNC_LEN" ;;
            dada2-single) LEN_VAR="DADA2S_TRUNC_LEN" ;;
            *)            LEN_VAR="TRIM_LENGTH" ;;
        esac
        ;;
esac

if [[ "$STAGE" == "all" || "$STAGE" == "import" ]]; then
    echo
    echo "NEXT: when import finishes, inspect $STUDY_NAME/QiimeData/demux_viz.qzv, then"
    echo "      strip primers:   ./chpc/submit.sh $STUDY_NAME trim"
    echo "      (no-op if no primers set in chpc/$STUDY_FILE — go straight to denoise)"
    echo "      then set $LEN_VAR in chpc/$STUDY_FILE and:"
    echo "                       ./chpc/submit.sh $STUDY_NAME denoise"
fi

if [[ "$STAGE" == "trim" ]]; then
    echo
    echo "NEXT: when trim finishes, inspect $STUDY_NAME/QiimeData/demux_trimmed_viz.qzv,"
    echo "      set $LEN_VAR in chpc/$STUDY_FILE, then:"
    echo "                       ./chpc/submit.sh $STUDY_NAME denoise"
fi

echo "Track with: squeue -u \$USER   |   logs in chpc/logs/"
