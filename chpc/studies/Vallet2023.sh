#!/bin/bash
# =============================================================================
# chpc/studies/Vallet2023.sh
# Vallet et al. 2023, Cell Host & Microbe 31:1386-1403 — allo-HSCT gut
# microbiome / GVHD (16S subcohort). BioProject PRJNA902819 (118 SRR runs).
# 16S rRNA V3-V4, Illumina MiSeq (GeT-PlaGe / Genopole, Toulouse).
#
# PROVENANCE NOTE (not a mistake — do not flag): these samples were previously
# processed here under "Allozithro2017". They are the 16S subcohort of the
# Allozithro trial that was published separately as Vallet 2023, so they now
# live in their own Vallet2023/ folder and are re-run from scratch on this
# pipeline. Some files under Vallet2023/ may still carry an "Allo"/"allo"
# prefix (e.g. allo_meta*.{csv,tsv}); that is expected legacy naming.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="Vallet2023"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: standard Illumina R1/R2 paired-end -----------------------------
# 118 runs, deposited as clean paired FASTQ. `fasterq-dump --split-files` yields
# in-sync ${SRR}_1.fastq / ${SRR}_2.fastq, so the default import
# (02_import.slurm -> make_manifest_paired.sh) builds the manifest directly.
# NO repair / re-pairing / concat-split needed (unlike DAmico2019 or the 454
# Ingham2019 case). Leave LAYOUT at its "paired" default.

# --- Primer removal (cutadapt 'trim' stage: 03_trim_paired.slurm) ------------
# Paper (Method Details, "Sample processing and 16S rRNA sequencing"): V3-V4 of
# 16S amplified and sequenced on Illumina MiSeq at GeT-PlaGe (Genopole,
# Toulouse). Key-resources table lists "Primers V3-V4 / Eurofins". These are the
# gene-specific cores of the standard GeT-PlaGe/FROGS V3-V4 pair (343F / 784R)
# with NO Illumina overhang; the forward carries a degenerate R (A/G), which
# cutadapt matches automatically.
#   V3 fwd: ACGGRAGGCAGCAG       (14 nt)  343F
#   V4 rev: TACCAGGGTATCTAAT     (16 nt)  784R core
# VERIFIED against the deposited reads (2026-08-03): R1 reads begin with
# ACGGRAGGCAGCAG (89% of a sampled run; dominant 5' prefixes ACGGGAGGCAGCAG /
# ACGGAAGGCAGCAG) and R2 reads begin with TACCAGGGTATCTAAT (81%), so primers are
# still ON the reads and are NOT pre-trimmed — keep DISCARD_UNTRIMMED=true below.
# NOTE: the paper's text prints the forward as "TACGGRAGGCAGCAG"; that leading T
# is spurious (the reads carry no such base), so we use the true 343F core here.
PRIMER_F="ACGGRAGGCAGCAG"
PRIMER_R="TACCAGGGTATCTAAT"
CUTADAPT_ERROR_RATE=0.1        # allowed mismatch fraction vs primer
CUTADAPT_OVERLAP=3            # min overlap read<->primer to call a match
CUTADAPT_MIN_LENGTH=1        # drop reads emptied by trimming
CUTADAPT_DISCARD_UNTRIMMED="true"   # keep only pairs where the primer was found

# --- DADA2 denoise-paired parameters ----------------------------------------
# Primers are stripped by cutadapt above, so trim-left = 0 here (avoid double
# trimming). 3' truncation removes the low-quality tail.
# !! TRUNC_LEN_F/R ARE PLACEHOLDERS — SET FROM THE QUALITY PLOT !!
#    Inspect demux_trimmed_viz.qzv (the POST-primer plot) after the trim stage
#    and set both before denoising. The paper reports the MiSeq read length only
#    indirectly (their QIIME1 phylotype pipeline required min length 300 bp
#    after primer/barcode trimming), so read length here is likely 2x300 (v3) or
#    2x250. Keep the merge budget in mind: the primer-free fwd+rev lengths must
#    exceed the ~V3-V4 insert (~465 nt) + 12 to still merge in DADA2.
TRIM_LEFT_F=0
TRIM_LEFT_R=0
TRUNC_LEN_F=0
TRUNC_LEN_R=0

DADA2_THREADS=16

METADATA="$REPO_ROOT/$STUDY/Metadata/vallet_meta_qiime.tsv"

# Walltimes per stage (used by submit.sh). DENOISE_TIME covers the DADA2 job.
# 118 runs; average ~14,677 reads/sample (range 3,056-24,545) per the paper.
FETCH_TIME="12:00:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="04:00:00"
DENOISE_TIME="24:00:00"
