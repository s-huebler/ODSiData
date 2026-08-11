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
STUDY="Spindelboek2021"

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
PRIMER_F="TGCCAGCAGCCGCGGTAA"                        # 16s_515_S3_fwd 
PRIMER_R="GGACTACCAGGGTATCTAAT"                        # 16s_806_S2_rev 
# Optional cutadapt knobs (defaults shown; only needed if you set primers):
# CUTADAPT_ERROR_RATE=0.1
# CUTADAPT_OVERLAP=3
# CUTADAPT_MIN_LENGTH=1
# CUTADAPT_DISCARD_UNTRIMMED="true"
# CUTADAPT_EXTRA=""                # raw passthrough flags, e.g. "--p-indels"

# --- DADA2 denoise-paired parameters ----------------------------------------
DENOISER="pyro"

PYRO_TRUNC_LEN=276
PYRO_TRIM_LEFT=0          # 5' trim; 0 — primers already removed by prep_ingham_454.sh
PYRO_MAX_LEN=0            # drop reads longer than this pre-trim; 0 = off
PYRO_MAX_EE=2.0          # max expected errors (DADA2 default 2.0)
PYRO_TRUNC_Q=2          # truncate at first base <= this quality (default 2)
PYRO_THREADS=16          # match 04_dada2_pyro --cpus-per-task


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

# =============================================================================
# Greengenes2 mapping — qc + map stages (05_qc.slurm / 06_gg2_map.slurm)
# =============================================================================
# Runs AFTER denoise (and your local BLAST step). Two stages:
#   ./chpc/submit.sh $STUDY qc    -> classify-consensus-vsearch gate: keep only
#                                    ASVs that confidently assign to the GG2
#                                    backbone (drops the rare/novel tail).
#   ./chpc/submit.sh $STUDY map   -> qiime greengenes2 non-v4-16s: closed-ref
#                                    map the survivors onto the GG2 backbone
#                                    namespace (run uniformly on every study).
# Outputs land in $STUDY/Mapped/. Defaults come from chpc/config.sh (references +
# thresholds) and chpc/submit.sh (walltime/mem/threads). UNCOMMENT to override.
#
# --- Inputs to the qc stage (default: this study's DADA2 outputs) ------------
# QC_INPUT_TABLE="$REPO_ROOT/$STUDY/QiimeData/table.qza"
# QC_INPUT_SEQS="$REPO_ROOT/$STUDY/QiimeData/rep-seqs.qza"
#
# --- QC gate thresholds (classify-consensus-vsearch) -------------------------
# QC_PERC_IDENTITY=0.97       # min % identity to a GG2 reference sequence
# QC_QUERY_COV=0.90           # min fraction of the query that must align
# QC_MIN_CONSENSUS=0.51       # consensus fraction across accepted hits
# QC_MAXACCEPTS=10            # candidate hits considered per ASV
# QC_TOP_HITS_ONLY=false      # true = keep only best-identity hits
# QC_EXCLUDE="Unassigned"     # taxonomy label(s) filtered out after classifying
#
# --- non-v4-16s mapping identity --------------------------------------------
# GG2_MAP_PERC_IDENTITY=0.99  # closed-ref clustering identity vs the backbone
#
# --- Inputs to the map stage (default: the qc stage outputs) -----------------
# MAP_INPUT_TABLE="$REPO_ROOT/$STUDY/Mapped/qc-table.qza"
# MAP_INPUT_SEQS="$REPO_ROOT/$STUDY/Mapped/qc-seqs.qza"
#
# --- Resources (override chpc/submit.sh defaults) ----------------------------
# QC_TIME="04:00:00";  QC_MEM="16G";  QC_THREADS=8
# MAP_TIME="04:00:00"; MAP_MEM="24G"; MAP_THREADS=8
# =============================================================================
