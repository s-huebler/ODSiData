#!/bin/bash
# =============================================================================
# chpc/studies/Jarosch2023.sh
# Jarosch et al. 2023, Cell Reports Medicine 4:101125 — multimodal immune cell
# phenotyping of GI biopsies in human GvHD; the fecal 16S subcohort is what we
# curate here. DOI 10.1016/j.xcrm.2023.101125. ENA: PRJEB60178 (ERP145235).
# 16S rRNA V1-V3, primers S-D-Bact-0008-c-S-20 / S-D-Bact-0517-a-A-18
# (Klindworth 2013 nomenclature).
#
# !!! PLATFORM NOTE — ION TORRENT SINGLE-END, NOT ILLUMINA PAIRED !!!
# ---------------------------------------------------------------------------
# Methods: V1-V3 amplified with Platinum II Taq and sequenced on a Thermo Fisher
# GeneStudio S5 Plus (Ion Torrent) with the 600 bp protocol after IonChef
# templating. ENA run report confirms Platform=ION_TORRENT, Instrument=Ion
# Torrent S5, LibraryLayout=SINGLE, LibrarySelection=PCR, AMPLICON, AvgSpotLen
# ~410-423 bp. So:
#   * There are NO R1/R2 pairs — DADA2 denoise-paired (04_dada2_paired.slurm)
#     CANNOT be used. This is the single-end route.
#   * Correct QIIME2 denoiser for Ion Torrent variable-length reads is
#     `qiime dada2 denoise-pyro` (the 454/Ion Torrent error model), selected
#     below via DENOISER="pyro" (04_dada2_pyro.slurm). It tolerates variable
#     read length + homopolymer indels rather than trimming to one fixed length.
#   * PLATFORM CONFOUND (dissertation note): like Ingham2019 (454), folding a
#     single Ion Torrent dataset into an otherwise Illumina MiSeq meta-analysis
#     introduces a platform batch effect on ASV calls / read lengths. Worth
#     flagging in the harmonization writeup / inclusion criteria.
#
# UNLIKE Ingham2019: this is a STANDARD ENA per-run fetch. fasterq-dump on these
# single-end runs emits one ${RUN}.fastq each — no split-run pairing, no 454
# SFF prep step, no orientation cleanup. The default 01_fetch.slurm array over
# runs feeds 02_import_single directly.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="Jarosch2023"

# Run list — 53 ENA runs (ERR16879145 ...), one SRR/ERR per line.
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: Ion Torrent single fragments -> single-end route ----------------
# Standard per-run fetch (default 01_fetch.slurm) + 02_import_single. No
# FETCH_JOB / FETCH_ARRAY overrides: these are clean single-end runs, not the
# Liu2017 split-run case.
LAYOUT="single"

# --- Denoiser selection (single-end route) -----------------------------------
# "pyro" -> 04_dada2_pyro.slurm : DADA2 denoise-pyro, the 454/Ion Torrent error
# model. Preferred for this platform (variable length + homopolymer indels).
# Alternative "deblur" (04_deblur.slurm) is fixed-length and lossy on variable
# Ion Torrent reads — not recommended here.
DENOISER="pyro"

# --- Primers: 16S V1-V3, stripped by cutadapt in the single-end 'trim' stage --
# (03_trim_single.slurm, `./chpc/submit.sh Jarosch2023 trim`, runs after import,
# before denoise). FWD_PRIMER = 5' forward primer on the read; REV_PRIMER_RC =
# reverse-complement of the reverse primer (only appears at a read's 3' end when
# the ~410 bp read runs through the full ~490 bp amplicon, i.e. rarely — cutadapt
# treats a 3' adapter as optional, so it is safe to set).
#   FWD  S-D-Bact-0008-c-S-20 (27F, Klindworth 4-degeneracy variant, 20 nt):
#        AGRGTTYGATYMTGGCTCAG                          [CONFIRMED, Klindworth 2013]
#   REV  S-D-Bact-0517-a-A-18 (~518R, 18 nt):
#        ATTACCGCGGCKGCTGGC  -> revcomp GCCAGCMGCCGCGGTAAT
#
# !! VERIFY BEFORE THE TRIM STAGE !! The reverse 18-mer is reconstructed from the
# Klindworth naming (confirmed 17-nt S-D-Bact-0517-a-A-17 = TTACCGCGGCKGCTGGC,
# extended one 5' base); its revcomp is the expected 515F-like sequence, which is
# a good sign, but confirm against the deposited reads once fetched — sample a
# run and check what fraction of reads begin with AGRGTTYGATYMTGGCTCAG (5' still
# on the reads?) and whether GCCAGCMGCCGCGGTAAT appears at the 3' end. If the
# depositor pre-trimmed the 5' primer, set FWD_PRIMER="" to avoid double-trimming
# real 16S bases (cf. Ingham2019). See Vallet2023.sh for the verify-against-reads
# pattern.
FWD_PRIMER="AGRGTTYGATYMTGGCTCAG"      # 27F / S-D-Bact-0008-c-S-20 (20 nt)
REV_PRIMER_RC="GCCAGCMGCCGCGGTAAT"     # revcomp of S-D-Bact-0517-a-A-18 (18 nt)

# --- DADA2 denoise-pyro parameters (used when DENOISER="pyro") ----------------
# PYRO_TRUNC_LEN: truncate every read at this position and DISCARD shorter reads
# (DADA2 requires equal-length reads). SET FROM demux_trimmed_viz.qzv (the POST-
# trim quality plot) — pick a length that keeps most reads while cutting the
# low-quality 3' tail. Ion Torrent AvgSpotLen here is ~410-423 bp, so expect a
# value in the ~300-380 range; 0 = NO truncation. Empty (as left below) = unset
# -> the pyro job ABORTS on purpose, forcing you to inspect the plot first.
#
# >>> PLACEHOLDER — single-end pyro has ONE truncation length, not the F/R pair a
#     paired DADA2 study would use. Set it after the trim stage. <<<
PYRO_TRUNC_LEN=0          # TODO: set from demux_trimmed_viz.qzv (0 = none)
PYRO_TRIM_LEFT=15           # 5' trim; primers removed by the trim stage above, authors indicate 15
PYRO_MAX_LEN=0             # drop reads longer than this pre-trim; 0 = off
PYRO_MAX_EE=5.0            # max expected errors (paper's maxEE=5; default is 2.0)
PYRO_TRUNC_Q=2             # truncate at first base <= this quality (default 2)
PYRO_THREADS=16            # match --cpus-per-task in 04_dada2_pyro.slurm
# (denoise walltime is the shared DENOISE_TIME at the bottom of this file)

# --- QIIME sample-metadata TSV for feature-table summarize -------------------
# >>> PLACEHOLDER — the QIIME-formatted metadata TSV does not exist yet. <<<
# Raw sample metadata is committed at Metadata/Raw_metadata/meta_samples.csv;
# build the QIIME tsv from it (first column #SampleID / sample-id matching the
# ERR run IDs) and point METADATA at it, e.g.
# "$REPO_ROOT/$STUDY/Metadata/jarosch_meta_qiime.tsv". Leave "" to skip the
# metadata-annotated summary (import + denoise don't need it).
METADATA=""                # TODO: build jarosch_meta_qiime.tsv from meta_samples.csv

# Walltime hints per stage (edit per dataset size). 53 single-end Ion Torrent
# runs — small. DENOISE_TIME covers the pyro job.
FETCH_TIME="00:30:00"
IMPORT_TIME="01:00:00"
TRIM_TIME="01:00:00"
DENOISE_TIME="6:00:00"

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
