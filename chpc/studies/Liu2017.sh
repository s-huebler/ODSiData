#!/bin/bash
# =============================================================================
# chpc/studies/Liu2017.sh
# Liu et al. 2017 — baseline gut microbiota of allo-HSCT recipients & donors,
# 16S V4. Bone Marrow Transplantation 52:1643-1650. ENA: ERP017899 (PRJEB16057),
# Qiita study 10564.
#
# WHY THIS STUDY IS SPECIAL (split-run -> single-end FORWARD):
# The reads are 2x300 MiSeq (600-cycle v3 kit), but ENA reports
# library_layout=SINGLE. Each physical sample was deposited as TWO separate
# single-end runs — one holding R1, one holding R2 — sharing the same
# sample_accession / library_name (10564.XXXX). 158 runs = 79 samples x 2. The
# standard per-run array (01_fetch.slurm) cannot group these, so fetch still
# routes to 01_fetch_ena_and_pair.slurm, which groups a sample's two runs and
# assigns forward/reverse BY PRIMER.
#
# We first re-paired the mates for DADA2 paired merge, but the two runs were
# deposited with INDEPENDENT read orderings — the shared @10564.<tag>_<index>
# names do NOT co-refer to the same cluster — so name-based repair.sh paired
# non-mates and 28/79 samples merged at only 3-27% (vs 88-95% for the rest). The
# true mates exist but are recoverable only by per-read overlap alignment, which
# the conserved primer-proximal anchors defeat. Full write-up + archived
# artifacts: Liu_Merging_Test/SUMMARY.md.
#
# RESOLUTION: process the study SINGLE-END FORWARD. The forward read (~301 bp)
# already spans the full ~253 bp V4 amplicon, so merging is unnecessary. Fetch
# runs with SPLIT_OUTPUT="forward_single" (orient by primer, keep the 515F run,
# discard the reverse); LAYOUT="single" routes import/trim/denoise to the
# single-end path (DADA2 denoise-single). The slightly shorter single-end V4 is
# harmonized against merged studies by the downstream GG2 closed-ref mapping.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="Liu2017"

# Run list (all 158 runs; grouped into 79 pairs by the fetch job via the report).
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: SINGLE-END forward (see header) ---------------------------------
LAYOUT="single"
DENOISER="dada2-single"          # un-merged Illumina forward reads

# --- Non-standard fetch: route submit.sh to the ENA split-run job -------------
# submit.sh reads FETCH_JOB and submits it as an ARRAY sized by FETCH_ITEMS="pairs"
# — one task per unique PAIR_KEY (79 samples). The job groups a sample's two runs
# and orients them BY PRIMER; SPLIT_OUTPUT="forward_single" then keeps only the
# 515F forward run as <key>_1.fastq and discards the reverse (no repair).
FETCH_JOB="chpc/jobs/01_fetch_ena_and_pair.slurm"
FETCH_ARRAY="true"               # array over pairs (throttled by submit.sh)
FETCH_ITEMS="pairs"              # size the array by unique PAIR_KEY, not run count
SPLIT_OUTPUT="forward_single"    # keep only the oriented forward run (single-end)
ENA_REPORT="$REPO_ROOT/$STUDY/RawData/ENA_samples.tsv"   # committed filereport
PAIR_KEY="sample_accession"      # identical for the two mates of a sample
FTP_COL="submitted_ftp"          # download URL column in ENA_samples.tsv

# --- Primers (Methods: broad-range V4, barcoded primers) ---------------------
# 534F (labeled in the paper; sequence is the canonical 515F) and 806R.
# PRIMER_F/PRIMER_R orient the mates in the fetch job (the run whose reads start
# with PRIMER_F is the forward run). For the SINGLE-END trim stage
# (03_trim_single.slurm) the same primers are supplied as FWD_PRIMER (5' front)
# and REV_PRIMER_RC (3' adapter = reverse-complement of 806R), because a ~301 bp
# forward read on a ~253 bp amplicon reads THROUGH into the 806R region at its 3'.
PRIMER_F="GTGCCAGCMGCCGCGGTAA"        # 534F / 515F (19 nt) — orientation
PRIMER_R="GGACTACHVGGGTWTCTAAT"       # 806R (20 nt)        — orientation
FWD_PRIMER="GTGCCAGCMGCCGCGGTAA"      # 515F — single-end trim, 5' front
REV_PRIMER_RC="ATTAGAWACCCBDGTAGTCC"  # revcomp(806R) — single-end trim, 3' adapter

# --- DADA2 denoise-single parameters -----------------------------------------
# Primers are removed by the single-end trim stage, so no 5' trim here.
DADA2S_TRIM_LEFT=0
# 3' truncation — VERIFIED against QiimeData/demux_trimmed_viz.qzv (2026-08-09).
# denoise-single truncates every read at this length and DISCARDS shorter reads.
# The trimmed forward reads are 284 bp (2x300 MiSeq, 515F already trimmed) and
# the run is excellent: median Q37-38 the full length, 25th pct >=34 to ~228 bp,
# then choppy; adapter read-through decays the tail past ~250 bp. The V4 insert
# (post-primer, between 515F/806R) is only ~214 bp, so there is no biology to
# recover past the amplicon. 230 covers the full insert incl. longer-variant
# taxa and drops the degraded 806R/adapter read-through tail.
DADA2S_TRUNC_LEN=230

# Remaining denoise-single knobs — set explicitly so the run is fully specified
# (the job otherwise falls back to these same defaults). Run quality easily
# supports max-ee 2.0; trunc-q 2 and consensus chimera removal are DADA2 stock.
DADA2S_MAX_EE=2.0                 # --p-max-ee (max expected errors)
DADA2S_TRUNC_Q=2                 # --p-trunc-q (truncate at first base <= this q)
DADA2S_CHIMERA="consensus"       # --p-chimera-method (consensus|pooled|none)

# CPU threads for DADA2 denoise-single (--cpus-per-task in 04_dada2_single.slurm).
DADA2S_THREADS=8

# QIIME sample-metadata TSV for feature-table summarize.
METADATA="$REPO_ROOT/$STUDY/Metadata/liu_meta_qiime.tsv"

# Walltime hints per stage (edit per dataset size). Used by submit.sh.
# FETCH_TIME is PER ARRAY TASK (one sample = 2 downloads + orient, keep forward);
# 15m is generous headroom for a slow mirror.
FETCH_TIME="00:15:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="04:00:00"
DENOISE_TIME="8:00:00"

# Memory per stage (sbatch --mem; overrides the job-script #SBATCH default).
# 79 samples single-end V4 — 32G is comfortable headroom for DADA2 denoise-single.
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
QC_TIME="7:50:00";  QC_MEM="16G";  QC_THREADS=8
MAP_TIME="01:00:00"; MAP_MEM="24G"; MAP_THREADS=8
# =============================================================================
