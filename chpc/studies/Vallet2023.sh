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
TRUNC_LEN_F=230
TRUNC_LEN_R=225

DADA2_THREADS=16

METADATA="$REPO_ROOT/$STUDY/Metadata/vallet_meta_qiime.tsv"

# Walltimes per stage (used by submit.sh). DENOISE_TIME covers the DADA2 job.
# 118 runs; average ~14,677 reads/sample (range 3,056-24,545) per the paper.
FETCH_TIME="00:05:00"
IMPORT_TIME="01:00:00"
TRIM_TIME="01:00:00"
DENOISE_TIME="5:00:00"

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
# QC_TIME="12:00:00";  QC_MEM="32G";  QC_THREADS=8
# MAP_TIME="12:00:00"; MAP_MEM="64G"; MAP_THREADS=8
# =============================================================================
