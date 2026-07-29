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

# --- Primer removal (optional; cutadapt in 03_dada2.slurm) -------------------
# Set both to strip primers BY SEQUENCE before DADA2 (preferred over positional
# trim-left when read lengths vary). If set, use TRIM_LEFT_F/R=0 below. Leave
# empty to skip cutadapt. IUPAC/degenerate bases are matched automatically.
PRIMER_F=""                        # e.g. 341F CCTACGGGNGGCWGCAG
PRIMER_R=""                        # e.g. 805R GACTACHVGGGTATCTAATCC
# Optional cutadapt knobs (defaults shown; only needed if you set primers):
# CUTADAPT_ERROR_RATE=0.1
# CUTADAPT_OVERLAP=3
# CUTADAPT_MIN_LENGTH=1
# CUTADAPT_DISCARD_UNTRIMMED="true"
# CUTADAPT_EXTRA=""                # raw passthrough flags, e.g. "--p-indels"

# --- DADA2 denoise-paired parameters ----------------------------------------
# 5' primer trim: use paper's primer lengths IF not using cutadapt above;
# set to 0 when PRIMER_F/PRIMER_R are set (cutadapt already removed primers).
TRIM_LEFT_F=17
TRIM_LEFT_R=21
# 3' truncation = read length minus low-quality tail. VERIFY against demux plot
# (demux_trimmed_viz.qzv if cutadapt ran, else demux_viz.qzv).
TRUNC_LEN_F=0
TRUNC_LEN_R=0

# CPU threads for DADA2 (match --cpus-per-task in 02_import_dada2.slurm).
DADA2_THREADS=16

# Optional QIIME sample-metadata TSV for feature-table summarize. Leave "" to
# skip the metadata-annotated summary (import + DADA2 don't need it).
METADATA=""

# Walltime hints (edit per dataset size). Used by submit.sh.
FETCH_TIME="12:00:00"
IMPORT_TIME="04:00:00"
DADA2_TIME="24:00:00"
