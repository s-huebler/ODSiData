#!/bin/bash
# =============================================================================
# chpc/studies/_template.sh — copy this to <Study>.sh for a new dataset
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.
# Every value here is study-specific. Trim/trunc numbers come from the paper's
# methods AND should be sanity-checked against demux_viz.qzv (the quality plot)
# before you trust the DADA2 run.
# =============================================================================

# Folder name under the repo root (e.g. Fujimoto2024, Artacho2024).
STUDY="ChangeMe2024"

# Accession list — one SRR per line (already committed under <Study>/RawData/).
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Fetch job selection (default = per-run SRA array) ------------------------
# Standard studies leave these unset. Set them ONLY for "split-run" paired-end
# data: studies deposited as TWO separate single-end runs per sample (one = R1,
# one = R2, both library_layout=SINGLE), which the per-run array cannot pair.
# See chpc/studies/Liu2017.sh for a worked example. The pairing job groups the
# two runs, orients them BY PRIMER (PRIMER_F/PRIMER_R below), and repairs them
# into paired _1/_2 for the standard import/trim/denoise path.
# FETCH_JOB="chpc/jobs/01_fetch_ena_and_pair.slurm"
# FETCH_ARRAY="true"               # array over samples (throttled by submit.sh)
# FETCH_ITEMS="pairs"              # size the array by unique PAIR_KEY, not run count
# ENA_REPORT="$REPO_ROOT/$STUDY/RawData/ENA_samples.tsv"  # filereport TSV
# PAIR_KEY="sample_accession"      # column identical for the two mates
# FTP_COL="submitted_ftp"          # download-URL column in the report

# --- Primer removal (optional; cutadapt in the 'trim' stage) -----------------
# Handled by 03_trim_paired.slurm (`./chpc/submit.sh <Study> trim`), which runs
# AFTER import and BEFORE denoise. Set both to strip primers BY SEQUENCE
# (preferred over positional trim-left when read lengths vary). If set, use
# TRIM_LEFT_F/R=0 below. Leave empty to skip the trim stage entirely (denoise
# then uses the raw demux). IUPAC/degenerate bases are matched automatically.
PRIMER_F=""                        # e.g. 341F CCTACGGGNGGCWGCAG
PRIMER_R=""                        # e.g. 805R GACTACHVGGGTATCTAATCC
# Optional cutadapt knobs (defaults shown; only needed if you set primers):
# CUTADAPT_ERROR_RATE=0.1
# CUTADAPT_OVERLAP=3
# CUTADAPT_MIN_LENGTH=1
# CUTADAPT_DISCARD_UNTRIMMED="true"
# CUTADAPT_EXTRA=""                # raw passthrough flags, e.g. "--p-indels"

# --- DADA2 denoise-paired parameters ----------------------------------------
# 5' primer trim: use paper's primer lengths IF not using the trim stage above;
# set to 0 when PRIMER_F/PRIMER_R are set (the trim stage already removed them).
TRIM_LEFT_F=17
TRIM_LEFT_R=21
# 3' truncation = read length minus low-quality tail. VERIFY against demux plot
# (demux_trimmed_viz.qzv if the trim stage ran, else demux_viz.qzv).
TRUNC_LEN_F=0
TRUNC_LEN_R=0

# CPU threads for DADA2 (match --cpus-per-task in 04_dada2_paired.slurm).
DADA2_THREADS=16

# =============================================================================
# SINGLE-END route (uncomment + set LAYOUT="single" for un-paired data)
# =============================================================================
# Leave LAYOUT unset/"paired" for standard Illumina R1/R2 (block above). For
# single-end data, set LAYOUT="single" and pick a denoiser with DENOISER:
#   "deblur"       -> 04_deblur.slurm        : PRE-MERGED / joined reads
#                     (fwd+rev already joined). Uses TRIM_LENGTH / LEFT_TRIM_LEN
#                     / MIN_QUALITY / DEBLUR_THREADS.
#   "pyro"         -> 04_dada2_pyro.slurm    : 454 / Ion Torrent variable-length
#                     reads. Uses the PYRO_* parameters.
#   "dada2-single" -> 04_dada2_single.slurm  : TRUE single-end, UN-MERGED
#                     Illumina reads (standard DADA2 error model). Uses the
#                     DADA2S_* parameters below.
# Primers for the single-end route are stripped by cutadapt trim-single in the
# 'trim' stage (03_trim_single.slurm, `./chpc/submit.sh <Study> trim`) — set
# FWD_PRIMER / REV_PRIMER_RC (revcomp of the reverse primer) instead of
# PRIMER_F/PRIMER_R above; leave both "" if already removed.
#
# LAYOUT="single"
# DENOISER="dada2-single"
# FWD_PRIMER=""                     # e.g. 341F CCTACGGGNGGCWGCAG
# REV_PRIMER_RC=""                  # e.g. revcomp(805R) GGATTAGATACCCBDGTAGTC
#
# --- DADA2 denoise-single parameters (used when DENOISER="dada2-single") -----
# DADA2S_TRUNC_LEN is REQUIRED (no default): truncate every read here and
# DISCARD shorter reads. Set from demux_viz.qzv; 0 = no truncation; leaving it
# unset makes the job abort so you inspect the quality plot first.
# DADA2S_TRUNC_LEN=""
# DADA2S_TRIM_LEFT=0               # 5' trim; 0 when cutadapt/primers handled it
# DADA2S_MAX_EE=2.0               # max expected errors (DADA2 default 2.0)
# DADA2S_TRUNC_Q=2               # truncate at first base <= this quality
# DADA2S_CHIMERA="consensus"      # consensus | pooled | none
# DADA2S_THREADS=16               # match --cpus-per-task in the denoise job
# (denoise walltime is the shared DENOISE_TIME at the bottom of this file)
# =============================================================================

# Optional QIIME sample-metadata TSV for feature-table summarize. Leave "" to
# skip the metadata-annotated summary (import + DADA2 don't need it).
METADATA=""

# Walltime hints (edit per dataset size). Used by submit.sh — one per stage.
# DENOISE_TIME covers whichever denoiser this study selects (DADA2 / Deblur /
# pyro / dada2-single). TRIM_TIME is the cutadapt primer-removal stage.
FETCH_TIME="12:00:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="04:00:00"
DENOISE_TIME="24:00:00"

# Memory per stage — passed to sbatch --mem, overriding each job script's
# #SBATCH --mem default (import 8G, denoise 32G). Right-size to the dataset:
# over-asking memory lengthens your Slurm queue wait. Defaults if unset:
# IMPORT_MEM=8G, TRIM_MEM=8G, DENOISE_MEM=32G.
IMPORT_MEM="8G"
TRIM_MEM="8G"
DENOISE_MEM="32G"
