#!/bin/bash
# =============================================================================
# chpc/studies/DAmico2019.sh
# D'Amico et al. 2019 — allo-HSCT / GVHD gut microbiome, 16S V3-V4.
#
# SRA metadata reports layout=SINGLE, and the deposited reads are pre-joined:
# each spot is one ~458 bp sequence = forward_R1 + revcomp(reverse), a near
# full-length V3-V4 amplicon in forward orientation (341F at the 5' end,
# revcomp(785R) at the 3' end). `fasterq-dump --split-files` returns a single
# FASTQ per run.
#
# TREATMENT: keep these as single-end / pre-merged reads (02_import_single). We
# tried splitting them back into paired R1/R2 for DADA2, but the recovered
# reverse reads are too short for a reliable overlap on the ~464 bp amplicon, so
# single-end is the correct call.
#
# DENOISER: currently "dada2-single" (04_dada2_single.slurm), switched from
# "deblur" on 2026-08-13 — see the DENOISER block below for the rationale and
# the caveat about DADA2's error model on pre-joined reads.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="DAmico2019"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: route submit.sh to the single-end import/trim/denoise jobs ------
LAYOUT="single"

# --- Concatenated-read split: OFF for this study ----------------------------
# The split infrastructure in 01_fetch.slurm / chpc/lib/split_concat_16s.py stays
# available, but we intentionally do NOT split here — each run is kept as one
# ${SRR}.fastq and treated as a single-end merged amplicon.
SPLIT_CONCAT=0

# --- Primer removal (cutadapt trim-single, 'trim' stage: 03_trim_single.slurm) -
# Paper §2.3: V3-V4 amplified with 341F / 785R (Klindworth et al. 2013), MiSeq
# 2x250. Confirmed against the reads: they start with 341F and end with the
# reverse-complement of 785R. cutadapt strips the 5' forward primer (--p-front)
# and the 3' reverse-primer revcomp (--p-adapter).
FWD_PRIMER="CCTACGGGNGGCWGCAG"          # 341F (5' front, 17 nt)
REV_PRIMER_RC="GGATTAGATACCCBDGTAGTC"   # revcomp of 785R (3' adapter, 21 nt)

# !!! BUG FIXED 2026-08-13 — the trim + everything downstream MUST be re-run. !!!
# 03_trim_single.slurm used to pass --p-front and --p-adapter to ONE cutadapt
# call. cutadapt defaults to --times 1 (at most ONE adapter removed per read),
# so it matched and trimmed only the 3' revcomp(785R) and never searched for
# 341F. --p-discard-untrimmed did not catch it either: that flag only drops
# reads where ZERO adapters matched, so reads that kept their 341F sailed
# through the gate. Evidence: 1586 of the 1634 rep-seqs in
# QiimeData/dna-sequences.fasta still begin with an intact 341F.
# The job now runs two SEPARATE passes (5' front with discard-untrimmed, then
# 3' adapter without) and audits residual primer content afterwards.
# Re-run:  ./chpc/submit.sh DAmico2019 trim  ->  denoise  ->  qc  ->  map

# =============================================================================
# DENOISER selection (within LAYOUT="single")
# =============================================================================
# "deblur"       -> 04_deblur.slurm       (fixed-length, built for joined reads)
# "dada2-single" -> 04_dada2_single.slurm (DADA2 denoise-single)
#
# Set to "dada2-single" 2026-08-13. Rationale: this is the route closest to the
# paper's own reported workflow (PANDASeq join -> DADA2 ASVs), and it avoids two
# places where Deblur sheds reads for reasons that are artifacts of the joined
# layout rather than data quality:
#
#   1. quality-filter q-score (Deblur's mandatory pre-step) truncates at the
#      first run of 3 bases <= Q4 and then DISCARDS the read if <=75% of its
#      original length survives. A joined 2x250 read covering a ~455 nt amplicon
#      has only ~45 bp of overlap, so it carries an INTERNAL quality valley
#      around position 210-250 (late cycles of BOTH mates) followed by RECOVERY
#      as the sequence moves into the early, high-quality cycles of the
#      reverse-complemented R2. q-score truncates at the valley, sees ~48% of the
#      read remaining, and throws the whole thing away — including the good
#      sequence after the valley. QIIME's own joined-read tutorial notes the
#      default q-score settings are not benchmarked on joined reads.
#   2. Deblur's fixed TRIM_LENGTH discards every read shorter than the cutoff,
#      which on naturally variable V3-V4 lengths is a taxonomic-bias risk.
#
# DADA2 instead does whole-read expected-error filtering (max-ee), so it judges
# the read as a whole rather than stopping at the first bad window.
#
# !!! CAVEAT — this contradicts the guidance in 04_dada2_single.slurm's header,
# which says to use Deblur for pre-merged reads. That guidance is not arbitrary:
# DADA2's learnErrors fits a Q-score -> error-rate model, and in the overlap
# region PANDASeq RECOMPUTES quality scores with a consensus formula rather than
# reporting instrument Q. The error model is therefore partly fit on synthetic
# quality values. That is a real limitation, not a formality. Treat this run as
# a SENSITIVITY ANALYSIS against the Deblur arm, not an automatic upgrade:
# compare per-sample retention between the two, and against the ~8,044
# high-quality sequences/sample the authors report (archive average is ~23,500
# joined sequences/sample, so the authors themselves kept roughly one third).
#
# !!! BOTH denoisers write the SAME filenames (table.qza, rep-seqs.qza,
# stats.qza, *.qzv, exported-seqs/dna-sequences.fasta) to $STUDY/QiimeData/.
# Switching DENOISER and re-running OVERWRITES the other arm's outputs. Copy the
# existing Deblur outputs somewhere safe first if you want to compare them.
DENOISER="dada2-single"

# =============================================================================
# DADA2 denoise-single parameters (04_dada2_single.slurm) — ACTIVE ARM
# =============================================================================
# DADA2S_TRUNC_LEN=0 disables fixed-length truncation AND the accompanying
# length filter, so naturally shorter V3-V4 amplicons are kept instead of
# discarded. This is the main reason to prefer DADA2 here over Deblur's fixed
# TRIM_LENGTH. Variable-length ASVs are fine downstream: the GG2 route for this
# study is closed-reference `non-v4-16s` mapping, which does not require equal
# lengths.
DADA2S_TRUNC_LEN=0

# 5' trim. Leave 0 — the trim stage removes 341F by sequence.
DADA2S_TRIM_LEFT=0

# --p-trunc-q 0 disables truncation at the first low-quality base. This is
# deliberate and specific to joined reads: the default (2) would cut at the
# internal overlap valley described above and throw away the recovered
# high-quality tail. Quality control is handed entirely to max-ee.
DADA2S_TRUNC_Q=0

# Whole-read expected-error ceiling (DADA2 default 2.0). If the denoising stats
# show most reads dying at the `filtered` step, try 3.0 then 5.0 as a
# SENSITIVITY ANALYSIS — do not pick the value that merely maximizes retention;
# check that per-sample retention and the resulting ASVs are stable across it.
DADA2S_MAX_EE=5.0

DADA2S_CHIMERA="consensus"

# CPU threads (match --cpus-per-task in 04_dada2_single.slurm).
DADA2S_THREADS=16

# AFTER THE RUN: inspect QiimeData/stats_viz.qzv and read the columns in order —
# input -> filtered -> denoised -> non-chimeric. That tells you WHICH stage is
# losing reads and whether the loss is uniform across samples or concentrated in
# a few. Compare the final per-sample counts to the paper's ~8,044.

# =============================================================================
# Deblur denoise-16S parameters (04_deblur.slurm) — INACTIVE ARM
# =============================================================================
# Kept for the comparison run. To switch back, set DENOISER="deblur" above.
#
# TRIM_LENGTH: Deblur trims EVERY read to this fixed length and DISCARDS any
# read shorter than it. Reads are ~458 bp but variable. Set MANUALLY from
# demux_viz.qzv (length/quality plot) to retain most reads while cutting the
# low-quality 3' tail. 0 = unset (job refuses to run); -1 disables trimming.
#
# Set to 400 (2026-07-30). demux_viz.qzv length summary (PRE-cutadapt):
# 2%=439, 9%=440, 25%=441, 50%=460, 75%=465, 98%=466 nts. Deblur applies
# --p-trim-length AFTER the 'trim' stage's cutadapt strips 341F (17 nt) +
# revcomp(785R) (up to 21 nt, ~38 nt total), so reads entering Deblur are
# shorter than the table above. 400 is deliberately conservative to absorb that
# primer loss and retain reads (a table-derived 439 would discard nearly
# everything post-cutadapt). Inspect demux_trimmed_viz.qzv (from the trim stage)
# to re-check this against the POST-primer lengths.
#
# RE-CHECK AFTER THE 2026-08-13 TRIM FIX. The run that produced the current
# outputs lost only ~21 nt to cutadapt (3' primer only), so 400 was slack. With
# both primers removed the full ~38 nt comes off and the length distribution
# shifts to roughly 2%=401, 25%=403, 50%=422, 98%=428 — 400 still retains ~98%
# of reads but is now close to the 2% floor. Read the residual-primer audit and
# the length quantiles printed by the trim job (and demux_trimmed_viz.qzv); if
# the observed 2% quantile lands below 400, drop TRIM_LENGTH to ~390 before
# denoising rather than silently losing the short tail.
TRIM_LENGTH=400

# LEFT_TRIM_LEN: 5' bases Deblur removes before denoising. Leave 0 — cutadapt
# above already removes the 341F primer by sequence.
LEFT_TRIM_LEN=0

# Quality-filter q-score minimum (Deblur tutorial default = 4).
MIN_QUALITY=4

# CPU threads for Deblur (match --cpus-per-task in 04_deblur.slurm).
DEBLUR_THREADS=16

# QIIME sample-metadata TSV for feature-table summarize.
# NOTE: damico_meta_qiime.tsv currently has "Run" as its first-column header;
# QIIME requires a recognized ID header (e.g. "sample-id"). Fix that header (or
# set METADATA="") if feature-table summarize errors on the ID column.
METADATA="$REPO_ROOT/$STUDY/Metadata/damico_meta_qiime.tsv"

# Walltime hints per stage (edit per dataset size). Used by submit.sh. 104 runs.
# DENOISE_TIME covers whichever denoiser DENOISER selects.
# All written as ${VAR:-default} so a value exported on the command line WINS.
# (A plain VAR="..." here would clobber the environment, since submit.sh sources
# this file after the shell sets it.) That matters for notchpeak-shared-short,
# whose 8h wall cap would reject the 24h DENOISE_TIME default:
#   CHPC_CLUSTER=notchpeak CHPC_ACCOUNT=notchpeak-shared-short \
#   CHPC_PARTITION=notchpeak-shared-short DENOISE_TIME=08:00:00 \
#   ./chpc/submit.sh DAmico2019 denoise
FETCH_TIME="${FETCH_TIME:-12:00:00}"
IMPORT_TIME="${IMPORT_TIME:-04:00:00}"
TRIM_TIME="${TRIM_TIME:-06:00:00}"   # two cutadapt passes since the 2026-08-13 primer fix
DENOISE_TIME="${DENOISE_TIME:-07:50:00}"

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
QC_TIME="${QC_TIME:-24:00:00}";  QC_MEM="${QC_MEM:-16G}";  QC_THREADS="${QC_THREADS:-8}"
MAP_TIME="${MAP_TIME:-07:00:00}"; MAP_MEM="${MAP_MEM:-24G}"; MAP_THREADS="${MAP_THREADS:-8}"
# =============================================================================
