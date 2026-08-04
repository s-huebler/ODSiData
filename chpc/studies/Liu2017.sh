#!/bin/bash
# =============================================================================
# chpc/studies/Liu2017.sh
# Liu et al. 2017 — baseline gut microbiota of allo-HSCT recipients & donors,
# 16S V4. Bone Marrow Transplantation 52:1643-1650. ENA: ERP017899 (PRJEB16057),
# Qiita study 10564.
#
# WHY THIS STUDY IS SPECIAL (split-run paired-end):
# The reads are 2x300 MiSeq paired-end (600-cycle v3 kit), but ENA reports
# library_layout=SINGLE. Each physical sample was deposited as TWO separate
# single-end runs — one holding R1, one holding R2 — sharing the same
# sample_accession / library_name (10564.XXXX), both with a "/1" header suffix.
# 158 runs = 79 samples x 2. The standard per-run array (01_fetch.slurm) cannot
# pair these, so this study routes fetch to 01_fetch_ena_and_pair.slurm, which
# groups the two runs per sample, assigns forward/reverse BY PRIMER, relabels
# the reverse mate /1->/2, and repair.sh-syncs them into paired _1/_2 files.
# Downstream (import/trim/denoise) is then fully standard paired.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="Liu2017"

# Run list (all 158 runs; grouped into 79 pairs by the fetch job via the report).
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: standard paired once the fetch job has re-paired the mates -------
LAYOUT="paired"

# --- Non-standard fetch: route submit.sh to the ENA split-run pairing job -----
# submit.sh reads FETCH_JOB (default 01_fetch.slurm) and submits it as a job
# ARRAY sized by FETCH_ITEMS="pairs" — one task per unique PAIR_KEY (79 samples),
# so mates download/orient/repair in parallel. These vars fully drive that job.
FETCH_JOB="chpc/jobs/01_fetch_ena_and_pair.slurm"
FETCH_ARRAY="true"               # array over pairs (throttled by submit.sh)
FETCH_ITEMS="pairs"              # size the array by unique PAIR_KEY, not run count
ENA_REPORT="$REPO_ROOT/$STUDY/RawData/ENA_samples.tsv"   # committed filereport
PAIR_KEY="sample_accession"      # identical for the two mates of a sample
FTP_COL="submitted_ftp"          # download URL column in ENA_samples.tsv

# --- Primers (Methods: broad-range V4, barcoded primers) ---------------------
# 534F (labeled in the paper; sequence is the canonical 515F) and 806R.
# Used TWICE: (1) by the fetch job to orient each mate (the file whose reads
# start with PRIMER_F is the true forward read — deterministic, replaces the old
# fastqc quality-swap), and (2) by the trim stage (03_trim_paired.slurm) to
# strip primers by sequence before denoising.
PRIMER_F="GTGCCAGCMGCCGCGGTAA"        # 534F / 515F (19 nt)
PRIMER_R="GGACTACHVGGGTWTCTAAT"       # 806R (20 nt)

# --- DADA2 denoise-paired parameters -----------------------------------------
# Primers are removed by the trim stage above, so DADA2 does no 5' trim.
TRIM_LEFT_F=0
TRIM_LEFT_R=0
# 3' truncation — PLACEHOLDERS. Set from the POST-trim quality plot
# (QiimeData/demux_trimmed_viz.qzv) before running denoise. 0 = no truncation;
# leaving these at 0 lets the job run untruncated, which is NOT what you want for
# 2x300 V4 — inspect the plot and set both to trim the low-quality 3' tails while
# preserving enough overlap to merge (~253 bp V4 amplicon).
TRUNC_LEN_F=266    # TODO: set from demux_trimmed_viz.qzv
TRUNC_LEN_R=230    # TODO: set from demux_trimmed_viz.qzv

# CPU threads for DADA2 (match --cpus-per-task in 04_dada2_paired.slurm).
DADA2_THREADS=16

# QIIME sample-metadata TSV for feature-table summarize.
METADATA="$REPO_ROOT/$STUDY/Metadata/liu_meta_qiime.tsv"

# Walltime hints per stage (edit per dataset size). Used by submit.sh.
# FETCH_TIME is PER ARRAY TASK (one sample = 2 downloads + repair, a couple min);
# 4h is generous headroom for a slow mirror.
FETCH_TIME="00:15:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="04:00:00"
DENOISE_TIME="7:00:00"
