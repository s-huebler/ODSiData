#!/bin/bash
# =============================================================================
# chpc/studies/OrbergMO2024.sh — Orberg 2024, MO16S_ deposit group (primer-free)
#
# Source paper: Orberg et al. 2024, two-center prospective allo-SCT cohort
# (BioProject PRJEB53547 / ERP138358). 16S V1-V3, 27F (S-D-Bact-0008-c-S-20) /
# 534R (S-D-Bact-0517-a-A-18). Platform: Ion GeneStudio S5 Plus, single-end.
# Paper workflow: Trimmomatic (window 25, Q20) -> cutadapt 3.4 (demux, adaptor +
# primer removal) -> vsearch zOTUs (maxEE 5). We do NOT reproduce that; reads are
# re-denoised here with DADA2 denoise-pyro (Ion Torrent / homopolymer model).
#
# WHY TWO STUDY FILES (OrbergMO2024 + OrbergSJ2024)
# The ENA deposit mixes three run groups, identified by the Sample_name prefix
# in Orberg2024/Metadata/Raw_metadata/meta_samples.csv:
#   MO16S_  269 runs  16S, deposited WITHOUT barcode, GAT or 27F
#   SJ16S_   54 runs  16S, deposited with 'GAT' + 27F still on, PLUS an extra
#                     V3-V4 amplicon (341F/805R-like) in 29-68% of reads
#   MOITS_  247 runs  ITS1 (fungal) -> excluded, parked on scratch in
#                     $WORK_BASE/Orberg2024_ITS/RawData
# One FWD_PRIMER setting cannot serve both 16S groups (setting 27F discards
# ~100% of MO; leaving it empty keeps primer + the V3-V4 reads in SJ), so they
# are separate pipeline units with IDENTICAL denoise settings. After trimming
# both start at the base right after 27F, so their ASVs are directly comparable.
# Whether they are one or two studies in the meta-analysis is decided at
# harmonization, not here. MO/SJ are deposit groups, NOT confirmed to be the
# two centers (the clinical sheet uses REGS / MUC).
#
# Evidence: Orberg2024/read_check/REPORT.md (read check 2026-10-14, first 2,000
# reads of 6 MO + 4 SJ + 2 ITS runs). MO also checked for V3-V4 contamination:
# 0.0% 805R-rc in 8 runs.
#
# Raw FASTQs were fetched once as Orberg2024 and split on scratch into
# $WORK_BASE/OrbergMO2024/RawData and $WORK_BASE/OrbergSJ2024/RawData; no
# re-fetch needed. If you ever re-fetch, ACCESSIONS below is already the subset.
#
# REMINDER for downstream: every sample was spiked with Alcanivorax borkumensis,
# Agrobacterium (Rhizobium) radiobacter and Alicyclobacillus acidiphilus as
# process controls. Remove those ASVs before merging.
#
# 3' end: full-length reads end in ...GCCAGCAGCC + CCGGTCAGG, which does NOT
# match revcomp(534R) closely enough for cutadapt, so REV_PRIMER_RC is left
# empty and truncation at PYRO_TRUNC_LEN (<= ~400) removes it instead.
# =============================================================================

STUDY="OrbergMO2024"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"
METADATA="$REPO_ROOT/$STUDY/Metadata/orbergMO_meta_qiime.tsv"

LAYOUT="single"
DENOISER="pyro"

# --- Primers: already removed by the depositor ------------------------------
# 27F is absent from 100% of sampled MO reads (reads start at E. coli ~28).
# >>> LEAVE EMPTY <<< Setting FWD_PRIMER would discard ~all reads via
# --p-discard-untrimmed. With both empty, the trim stage is skipped and
# denoise reads demux.qza directly.
FWD_PRIMER=""
REV_PRIMER_RC=""

# --- DADA2 denoise-pyro parameters (KEEP IDENTICAL in OrbergMO2024/OrbergSJ2024)
# PYRO_TRUNC_LEN provisional from a simulated pyro filter on the sampled reads
# (reads kept after max-ee 2: MO 77.9/71.7/64.6/57.0%, SJ 43.3/39.4/34.5/30.9%
# of ALL reads, V3-V4 included, at 200/250/300/350). Confirm against
# demux_trimmed_viz.qzv (SJ) / demux_viz.qzv (MO) before the denoise run.
PYRO_TRUNC_LEN=350
PYRO_TRIM_LEFT=17
PYRO_MAX_LEN=0
PYRO_MAX_EE=5.0
PYRO_TRUNC_Q=2
PYRO_CHIMERA="consensus"
PYRO_THREADS=16


# Walltime hints (edit per dataset size). Used by submit.sh — one per stage.
# DENOISE_TIME covers whichever denoiser this study selects (DADA2 / Deblur /
# pyro / dada2-single). TRIM_TIME is the cutadapt primer-removal stage.
FETCH_TIME="4:00:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="04:00:00"
DENOISE_TIME="12:00:00"

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
# OOM at 16G (job 9625663, MaxRSS 16.0G after 10h): 7,794 ASVs vs 4,510 in
# Spindelboek2021, which peaked at 15.1G. QC_TIME left at submit.sh default.
QC_MEM="64G";  QC_THREADS=8
# MAP_TIME="04:00:00"; MAP_MEM="24G"; MAP_THREADS=8
# =============================================================================
