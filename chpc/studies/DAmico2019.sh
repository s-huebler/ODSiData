#!/bin/bash
# =============================================================================
# chpc/studies/DAmico2019.sh
# D'Amico et al. 2019 — allo-HSCT / GVHD gut microbiome, 16S V3-V4.
#
# SRA metadata reports layout=SINGLE, and the deposited reads are pre-joined:
# each spot is one ~458 bp sequence = forward_R1 + revcomp(reverse), a near
# full-length V3-V4 amplicon in forward orientation (341F at the 5' end,
# revcomp(785R) at the 3' end). `fasterq-dump --split-files` returns a single
# FASTQ per run.
#
# TREATMENT: keep these as single-end / pre-merged reads and denoise with Deblur
# (02_import_single -> 04_deblur). We tried splitting them back into
# paired R1/R2 for DADA2, but the recovered reverse reads are too short for a
# reliable overlap on the ~464 bp amplicon, so single-end is the correct call.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="DAmico2019"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: route submit.sh to the single-end / Deblur jobs ----------------
LAYOUT="single"

# --- Concatenated-read split: OFF for this study ----------------------------
# The split infrastructure in 01_fetch.slurm / chpc/lib/split_concat_16s.py stays
# available, but we intentionally do NOT split here — each run is kept as one
# ${SRR}.fastq and treated as a single-end merged amplicon.
SPLIT_CONCAT=0

# --- Primer removal (cutadapt trim-single, 'trim' stage: 03_trim_single.slurm) -
# Paper §2.3: V3-V4 amplified with 341F / 785R (Klindworth et al. 2013), MiSeq
# 2x250. Confirmed against the reads: they start with 341F and end with the
# reverse-complement of 785R. cutadapt strips the 5' forward primer (--p-front)
# and the 3' reverse-primer revcomp (--p-adapter).
FWD_PRIMER="CCTACGGGNGGCWGCAG"          # 341F (5' front, 17 nt)
REV_PRIMER_RC="GGATTAGATACCCBDGTAGTC"   # revcomp of 785R (3' adapter, 21 nt)

# --- Deblur denoise-16S parameters ------------------------------------------
# TRIM_LENGTH: Deblur trims EVERY read to this fixed length and DISCARDS any
# read shorter than it. Reads are ~458 bp but variable. Set MANUALLY from
# demux_viz.qzv (length/quality plot) to retain most reads while cutting the
# low-quality 3' tail. 0 = unset (job refuses to run); -1 disables trimming.
#
# Set to 400 (2026-07-30). demux_viz.qzv length summary (PRE-cutadapt):
# 2%=439, 9%=440, 25%=441, 50%=460, 75%=465, 98%=466 nts. Deblur applies
# --p-trim-length AFTER the 'trim' stage's cutadapt strips 341F (17 nt) +
# revcomp(785R) (up to 21 nt, ~38 nt total), so reads entering Deblur are
# shorter than the table above. 400 is deliberately conservative to absorb that
# primer loss and retain reads (a table-derived 439 would discard nearly
# everything post-cutadapt). Inspect demux_trimmed_viz.qzv (from the trim stage)
# to re-check this against the POST-primer lengths.
TRIM_LENGTH=400

# LEFT_TRIM_LEN: 5' bases Deblur removes before denoising. Leave 0 — cutadapt
# above already removes the 341F primer by sequence.
LEFT_TRIM_LEN=0

# Quality-filter q-score minimum (Deblur tutorial default = 4).
MIN_QUALITY=4

# CPU threads for Deblur (match --cpus-per-task in 04_deblur.slurm).
DEBLUR_THREADS=16

# QIIME sample-metadata TSV for feature-table summarize.
# NOTE: damico_meta_qiime.tsv currently has "Run" as its first-column header;
# QIIME requires a recognized ID header (e.g. "sample-id"). Fix that header (or
# set METADATA="") if feature-table summarize errors on the ID column.
METADATA="$REPO_ROOT/$STUDY/Metadata/damico_meta_qiime.tsv"

# Walltime hints per stage (edit per dataset size). Used by submit.sh. 104 runs.
# DENOISE_TIME covers the Deblur job.
FETCH_TIME="12:00:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="04:00:00"
DENOISE_TIME="24:00:00"
