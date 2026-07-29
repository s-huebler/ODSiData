#!/bin/bash
# =============================================================================
# chpc/studies/DAmico2019.sh
# D'Amico et al. 2019 — allo-HSCT / GVHD gut microbiome, 16S V3-V4.
#
# SRA metadata reports layout=SINGLE, but each deposited read is actually the
# forward and reverse mates CONCATENATED into one spot:
#     read = forward_R1 (fixed 250 bp) + reverse_complement(raw_R2)
# with a quality cliff at the junction (~pos 251) — it is NOT an overlap-merged
# amplicon. `fasterq-dump --split-files` therefore returns a single file and
# cannot separate the mates.
#
# We recover the true paired structure at fetch time (SPLIT_CONCAT below), then
# run the standard paired import + DADA2 denoise-paired path, so DADA2 does real
# per-direction error modelling and overlap merging.  [Supersedes the earlier
# single-end/Deblur workaround.]
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="DAmico2019"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: route submit.sh to the paired / DADA2 jobs ---------------------
LAYOUT="paired"

# --- Concatenated-read split (handled in 01_fetch.slurm) --------------------
# SPLIT_CONCAT=1 turns each downloaded ${SRR}.fastq into ${SRR}_1.fastq /
# ${SRR}_2.fastq (R2 reverse-complemented) via chpc/lib/split_concat_16s.py.
SPLIT_CONCAT=1
SPLIT_R1_LEN=250     # forward-read length = split point. VERIFY per demux plot:
                     # forward quality stays high to ~250 then collapses at 251.
SPLIT_MIN_R2=20      # drop pairs whose reverse tail is shorter than this.

# --- DADA2 denoise-paired parameters ----------------------------------------
# 5' primer trim: 341F = 17 nt, 805R = 21 nt (Klindworth V3-V4 primers).
TRIM_LEFT_F=17
TRIM_LEFT_R=21
# 3' truncation = read length minus low-quality tail. 0 = unset; the denoise job
# will refuse to run until set. Choose from demux_viz.qzv: forward reads are a
# clean 250 bp; reverse reads are variable (~205-215 bp, some shorter) — pick a
# TRUNC_LEN_R that keeps enough length for a ~30+ bp overlap with the forward
# read across the ~465 bp V3-V4 amplicon while dropping the low-quality tail.
# !! VERIFY both against demux_viz.qzv before trusting the run.
TRUNC_LEN_F=0
TRUNC_LEN_R=0

# CPU threads for DADA2 (match --cpus-per-task in 03_dada2.slurm).
DADA2_THREADS=16

# QIIME sample-metadata TSV for feature-table summarize.
# NOTE: damico_meta_qiime.tsv currently has "Run" as its first-column header;
# QIIME requires a recognized ID header (e.g. "sample-id"). Fix that header (or
# set METADATA="") if feature-table summarize errors on the ID column.
METADATA="$REPO_ROOT/$STUDY/Metadata/damico_meta_qiime.tsv"

# Walltime hints (edit per dataset size). Used by submit.sh. 104 runs.
FETCH_TIME="12:00:00"
IMPORT_TIME="04:00:00"
DADA2_TIME="24:00:00"
