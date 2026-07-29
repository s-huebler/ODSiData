#!/bin/bash
# =============================================================================
# 03_deblur_single.slurm — SINGLE-END / pre-merged layout denoising via Deblur.
# The single-end analogue of 03_dada2.slurm. Reads demux.qza from
# 02_import_single.slurm (on scratch). Run AFTER inspecting demux_viz.qzv and
# setting TRIM_LENGTH in the study file.
#
# Why Deblur (not DADA2) for this layout: these reads are already merged
# (forward+reverse joined), so DADA2's paired error model does not apply and
# denoise-single's error model assumes un-merged reads. Deblur denoises against
# a positive 16S reference and takes pre-joined reads cleanly.
#
# Pipeline: [optional cutadapt primer removal] -> quality-filter q-score
#           -> deblur denoise-16S -> visualize-stats -> export rep-seqs FASTA.
# Exports dna-sequences.fasta (input for the local BLAST Analysis section) plus
# table.qza / rep-seqs.qza / stats.qza and the .qzv summaries.
#
# Submit via chpc/submit.sh (routes here when the study sets LAYOUT="single").
# Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/DAmico2019.sh chpc/jobs/03_deblur_single.slurm
# =============================================================================
#SBATCH --job-name=qiime-deblur
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=chpc/logs/deblur_%j.out
#SBATCH --error=chpc/logs/deblur_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/DAmico2019.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for QIIME2/deblur/vsearch intermediates -----------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD/exported-seqs"

THREADS="${SLURM_CPUS_PER_TASK:-${DEBLUR_THREADS:-16}}"

# Study-file parameters (with safe defaults).
TRIM_LENGTH="${TRIM_LENGTH:-0}"           # deblur --p-trim-length; MUST be set (>0 or -1)
LEFT_TRIM_LEN="${LEFT_TRIM_LEN:-0}"       # deblur --p-left-trim-len (5' trim, e.g. primer len)
MIN_QUALITY="${MIN_QUALITY:-4}"           # quality-filter q-score min (Deblur default = 4)
FWD_PRIMER="${FWD_PRIMER:-}"              # optional: 5' primer for cutadapt trim-single
REV_PRIMER_RC="${REV_PRIMER_RC:-}"        # optional: 3' adapter = revcomp of reverse primer

# --- Precondition: demux.qza from the import step must exist -----------------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import_single.slurm first." >&2
    exit 1
fi
if [[ "$TRIM_LENGTH" == "0" ]]; then
    echo "ERROR: TRIM_LENGTH is 0. Inspect demux_viz.qzv and set TRIM_LENGTH in" >&2
    echo "       chpc/$STUDY_FILE (a positive length, or -1 to disable trimming)." >&2
    exit 1
fi

echo "==== Deblur for $STUDY ===="
echo "Work        : $QD"
echo "trim-length : $TRIM_LENGTH ; left-trim : $LEFT_TRIM_LEN ; min-quality : $MIN_QUALITY ; threads : $THREADS"
echo "primers     : fwd='${FWD_PRIMER:-none}' rev_rc='${REV_PRIMER_RC:-none}'"

# --- 1. Optional primer removal with cutadapt -------------------------------
# Merged V3-V4 reads still carry the forward primer at the 5' end and the
# reverse-complement of the reverse primer at the 3' end. If FWD_PRIMER is set,
# strip primers here; otherwise skip and rely on LEFT_TRIM_LEN / TRIM_LENGTH.
DENOISE_INPUT="$QD/demux.qza"
if [[ -n "$FWD_PRIMER" ]]; then
    CUTADAPT_ARGS=(--i-demultiplexed-sequences "$QD/demux.qza"
                   --p-front "$FWD_PRIMER"
                   --p-cores "$THREADS"
                   --p-discard-untrimmed
                   --o-trimmed-sequences "$QD/demux-trimmed.qza"
                   --verbose)
    [[ -n "$REV_PRIMER_RC" ]] && CUTADAPT_ARGS+=(--p-adapter "$REV_PRIMER_RC")
    qiime cutadapt trim-single "${CUTADAPT_ARGS[@]}"
    DENOISE_INPUT="$QD/demux-trimmed.qza"
fi

# --- 2. Quality filter (Deblur expects q-score-filtered input) --------------
qiime quality-filter q-score \
    --i-demux "$DENOISE_INPUT" \
    --p-min-quality "$MIN_QUALITY" \
    --o-filtered-sequences "$QD/demux-filtered.qza" \
    --o-filter-stats "$QD/filter-stats.qza"

# --- 3. Deblur denoise against positive 16S reference -----------------------
qiime deblur denoise-16S \
    --i-demultiplexed-seqs "$QD/demux-filtered.qza" \
    --p-trim-length "$TRIM_LENGTH" \
    --p-left-trim-len "$LEFT_TRIM_LEN" \
    --p-jobs-to-start "$THREADS" \
    --p-sample-stats \
    --o-representative-sequences "$QD/rep-seqs.qza" \
    --o-table "$QD/table.qza" \
    --o-stats "$QD/stats.qza"

# --- 4. Summaries -----------------------------------------------------------
qiime metadata tabulate \
    --m-input-file "$QD/filter-stats.qza" \
    --o-visualization "$QD/filter-stats_viz.qzv"

qiime deblur visualize-stats \
    --i-deblur-stats "$QD/stats.qza" \
    --o-visualization "$QD/stats_viz.qzv"

if [[ -n "$METADATA" && -f "$METADATA" ]]; then
    qiime feature-table summarize \
        --i-table "$QD/table.qza" \
        --m-sample-metadata-file "$METADATA" \
        --o-visualization "$QD/table_viz.qzv"
else
    qiime feature-table summarize \
        --i-table "$QD/table.qza" \
        --o-visualization "$QD/table_viz.qzv"
fi

qiime feature-table tabulate-seqs \
    --i-data "$QD/rep-seqs.qza" \
    --o-visualization "$QD/rep-seqs_viz.qzv"

# --- 5. Export rep-seqs FASTA (input for the local BLAST step) --------------
qiime tools export \
    --input-path "$QD/rep-seqs.qza" \
    --output-path "$QD/exported-seqs"
# -> $QD/exported-seqs/dna-sequences.fasta

# --- 6. Copy small final artifacts back into the repo -----------------------
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST/exported-seqs"
cp -f "$QD"/table.qza "$QD"/rep-seqs.qza "$QD"/stats.qza "$DEST"/
cp -f "$QD"/*.qzv "$DEST"/ 2>/dev/null || true
cp -f "$QD"/exported-seqs/dna-sequences.fasta "$DEST/exported-seqs/"

echo "==== Done. Final artifacts in $DEST ===="
echo "Next: commit, push, pull locally, then run the BLAST Analysis section locally."
