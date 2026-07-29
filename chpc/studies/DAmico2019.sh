#!/bin/bash
# =============================================================================
# chpc/studies/DAmico2019.sh
# D'Amico et al. 2019 — allo-HSCT / GVHD gut microbiome, 16S V3-V4.
# Library layout in SRA metadata = SINGLE, but the deposited reads are already
# MERGED (forward+reverse joined): variable ~458 bp amplicons that still carry
# the 341F primer at the 5' end. So this study uses the single-end / Deblur
# pipeline (02_import_single -> 03_deblur_single), NOT DADA2 denoise-paired.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="DAmico2019"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: route submit.sh to the single-end / Deblur jobs ----------------
LAYOUT="single"

# --- Deblur denoise-16S parameters ------------------------------------------
# TRIM_LENGTH: Deblur trims EVERY read to this fixed length and DISCARDS any
# read shorter than it. These reads are merged and vary (~458 bp), so pick a
# length from demux_viz.qzv that retains most reads while cutting the low-
# quality 3' tail. 0 = unset (job will refuse to run); use -1 to disable.
# !! VERIFY against demux_viz.qzv before trusting.
TRIM_LENGTH=0

# LEFT_TRIM_LEN: 5' bases Deblur removes before denoising. Leave 0 if you strip
# primers with cutadapt below (FWD_PRIMER); otherwise set to the forward primer
# length (341F = 17 nt) to remove the primer by fixed length.
LEFT_TRIM_LEN=0

# Quality-filter q-score minimum (Deblur tutorial default = 4).
MIN_QUALITY=4

# --- Optional primer removal (cutadapt trim-single) -------------------------
# The observed read start (CCTACGGGTGGCAGCAG...) matches the Klindworth 341F
# primer for V3-V4. FWD_PRIMER (5') and REV_PRIMER_RC (revcomp of the reverse
# primer, found at the 3' end of a merged read) are the standard 341F/805R pair.
# !! VERIFY these against the D'Amico 2019 methods — set to "" to skip cutadapt
#    and instead strip the primer via LEFT_TRIM_LEN.
FWD_PRIMER="CCTACGGGNGGCWGCAG"          # 341F
REV_PRIMER_RC="GGATTAGATACCCBDGTAGTC"   # revcomp of 805R (GACTACHVGGGTATCTAATCC)

# CPU threads for Deblur (match --cpus-per-task in 03_deblur_single.slurm).
DEBLUR_THREADS=16

# QIIME sample-metadata TSV for feature-table summarize.
# NOTE: damico_meta_qiime.tsv currently has "Run" as its first-column header;
# QIIME requires a recognized ID header (e.g. "sample-id"). Fix that header (or
# set METADATA="") if feature-table summarize errors on the ID column.
METADATA="$REPO_ROOT/$STUDY/Metadata/damico_meta_qiime.tsv"

# Walltime hints (edit per dataset size). Used by submit.sh. 104 runs.
FETCH_TIME="12:00:00"
IMPORT_TIME="04:00:00"
DEBLUR_TIME="24:00:00"
