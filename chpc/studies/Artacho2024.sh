#!/bin/bash
# =============================================================================
# chpc/studies/Artacho2024.sh
# Artacho et al. 2024, Microbiome — BioProject PRJNA1088414 (274 SRR runs).
# V3-V4, MiSeq v3 (2x300). DADA2 v1.8 in the paper.
# =============================================================================

STUDY="Artacho2024"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- DADA2 denoise-paired parameters ----------------------------------------
# Paper's methods: trim 17 (fwd) / 21 (rev) nt from the 5' end to remove
# primers; remove 35 nt (fwd) / 75 nt (rev) of low-quality tail from the 3' end.
# For 2x300 reads that gives trunc-len 300-35=265 (fwd) and 300-75=225 (rev).
# !! VERIFY against demux_viz.qzv before trusting — actual read length can vary.
TRIM_LEFT_F=17
TRIM_LEFT_R=21
TRUNC_LEN_F=265
TRUNC_LEN_R=225

DADA2_THREADS=16

# No QIIME metadata TSV generated yet for Artacho (only Raw_metadata/ present).
# Once you build one (cf. Fujimoto2024/Metadata/Parsing_metadata.qmd), point here.
METADATA=""

FETCH_TIME="12:00:00"
DADA2_TIME="24:00:00"
