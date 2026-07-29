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

# --- Primer removal (cutadapt trim-paired, run inside 03_dada2.slurm) --------
# Paper §2.3: V3-V4 amplified with the 341F / 785R primers (Klindworth et al.
# 2013), Illumina MiSeq 2x250. Confirmed against the reads themselves: R1 starts
# with 341F; revcomp(R2) starts with 785R. Removing primers BY SEQUENCE (not a
# fixed trim-left) is more robust given the degenerate IUPAC bases.
PRIMER_F="CCTACGGGNGGCWGCAG"        # 341F (17 nt)
PRIMER_R="GACTACHVGGGTATCTAATCC"    # 785R (21 nt)
# cutadapt defaults in the job are fine (error-rate 0.1, discard-untrimmed=true).

# --- DADA2 denoise-paired parameters ----------------------------------------
# TRIM_LEFT = 0 because cutadapt already strips the primers by sequence above;
# setting these would double-trim the (already short) reverse reads.
TRIM_LEFT_F=0
TRIM_LEFT_R=0
# 3' truncation = read length minus low-quality tail. 0 = unset; the denoise job
# will refuse to run until set. Set MANUALLY from demux_viz.qzv.
# Overlap budget is TIGHT: the 341F/785R amplicon is ~464 bp, so DADA2 merging
# needs TRUNC_LEN_F + TRUNC_LEN_R >= ~476. Forward reads are a clean 250; the
# recovered reverse reads are short (median ~215, variable), so truncate the
# forward lightly and the reverse as little as quality allows. Check the "merged"
# column in stats.qza — if retention is poor, fall back to forward-only
# (denoise-single on R1).
TRUNC_LEN_F=249
TRUNC_LEN_R=220

# CPU threads for DADA2 (match --cpus-per-task in 03_dada2.slurm).
DADA2_THREADS=16

# QIIME sample-metadata TSV for feature-table summarize.
# NOTE: damico_meta_qiime.tsv currently has "Run" as its first-column header;
# QIIME requires a recognized ID header (e.g. "sample-id"). Fix that header (or
# set METADATA="") if feature-table summarize errors on the ID column.
METADATA="$REPO_ROOT/$STUDY/Metadata/damico_meta_qiime.tsv"

# Walltime hints (edit per dataset size). Used by submit.sh. 104 runs.
FETCH_TIME="1:00:00"
IMPORT_TIME="1:00:00"
DADA2_TIME="6:00:00"
