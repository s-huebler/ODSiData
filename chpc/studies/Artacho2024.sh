#!/bin/bash
# =============================================================================
# chpc/studies/Artacho2024.sh
# Artacho et al. 2024, Microbiome — BioProject PRJNA1088414 (104 SRR runs).
# V3-V4, MiSeq v3 (2x300). DADA2 v1.8 in the paper.
# =============================================================================

STUDY="Artacho2024"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Primer removal (cutadapt 'trim' stage: 03_trim_paired.slurm) ------------
# V3-V4 amplified with the Illumina "16S Metagenomic Sequencing Library Prep"
# protocol (Kapa HiFi + Nextera XT). That protocol's locus primers are the
# Klindworth (2013) 341F / 805R pair — their lengths (17 and 21 nt) match the
# paper's positional trims exactly, confirming the "first 17/21" are primers.
#   341F (fwd): CCTACGGGNGGCWGCAG        (17 nt)
#   805R (rev): GACTACHVGGGTATCTAATCC    (21 nt)
# Removing them by sequence is more robust than positional trim-left because the
# imported reads are variable length (demux plot: min ~40 fwd / ~147 rev).
# NOTE: confirm these against the study's SRA records if possible — the paper
# cites the Illumina protocol rather than printing the sequences.
PRIMER_F="CCTACGGGNGGCWGCAG"
PRIMER_R="GACTACHVGGGTATCTAATCC"
CUTADAPT_ERROR_RATE=0.1        # allowed mismatch fraction vs primer
CUTADAPT_OVERLAP=3            # min overlap read<->primer to call a match
CUTADAPT_MIN_LENGTH=1        # drop reads emptied by trimming
CUTADAPT_DISCARD_UNTRIMMED="true"   # keep only pairs where the primer was found

# --- DADA2 denoise-paired parameters ----------------------------------------
# Primers are stripped by cutadapt above, so trim-left = 0 here (avoid double
# trimming). 3' truncation removes the low-quality tail; the paper used 35 (fwd)
# / 75 (rev), i.e. trunc-len 300-35=265 and 300-75=225 for 2x300 reads.
# !! VERIFY against demux_trimmed_viz.qzv (the POST-primer plot) before trusting,
#    and keep the merge-overlap budget in mind: primer-free fwd+rev lengths must
#    exceed ~the V3-V4 insert (~427 nt) + 12 to still merge (paper leaves ~25 nt).
TRIM_LEFT_F=0
TRIM_LEFT_R=0
TRUNC_LEN_F=265
TRUNC_LEN_R=225

DADA2_THREADS=16

METADATA="$REPO_ROOT/$STUDY/Metadata/artacho_meta_qiime.tsv"

# Walltimes per stage (used by submit.sh). DENOISE_TIME covers the DADA2 job.
FETCH_TIME="1:00:00"
IMPORT_TIME="5:00:00"
TRIM_TIME="2:00:00"
DENOISE_TIME="12:00:00"
