#!/bin/bash
# =============================================================================
# chpc/studies/Ingham2019.sh
# Ingham et al. 2019, Microbiome 7:131 — pediatric allo-HSCT / GVHD gut
# microbiome. 16S rRNA V4-V5 region.
#
# !!! PLATFORM WARNING — THIS IS 454 PYROSEQUENCING, NOT ILLUMINA !!!
# ---------------------------------------------------------------------------
# The paper's Methods ("DNA isolation ... and 16S rRNA gene sequencing") state
# the libraries were run on a Roche 454 GS FLX Titanium instrument (2-region
# sequencing, GS FLX Titanium Sequencing Kit XLR70) at the Univ. of Copenhagen
# High-Throughput DNA Sequencing Center. Reads are 454 flowgram data (SFF),
# ~200-1000 bp, VARIABLE length, and were sequenced BIDIRECTIONALLY (both the
# 519F->926R and 926R->519F orientations exist in the raw data).
#
# The bioinformatics in the paper are QIIME *1.9.0*, not QIIME2:
#   mothur sffinfo (SFF -> FASTA + qual + flowgrams)
#   split_libraries.py  (two-step demux for the bidirectional reads)
#   denoise_wrapper.py  (454 FLOWGRAM denoising — the pyrosequencing-era
#                        equivalent of DADA2's error model; corrects the
#                        homopolymer indel errors 454 is prone to)
#   identify_chimeric_seqs.py  (usearch61, de novo + reference vs RDP v15)
#   pick_otus.py  (97% OTU clustering vs SILVA 119)  ->  make_otu_table.py
#
# WHY THE "EXTRA STEPS": they are NOT just because the study predates DADA2.
# DADA2 (2016) existed well before this 2019 paper. The flowgram/SFF handling
# (sffinfo, denoise_wrapper, inflate/truncate_reverse_primer, adjust_seq_
# orientation) is 454-SPECIFIC error correction that has no analogue in an
# Illumina DADA2 run. The authors then used the classic closed/de-novo OTU
# picking pipeline rather than ASV denoising. So: part legacy-OTU workflow,
# part hard platform requirement.
#
# CONSEQUENCES FOR OUR PIPELINE — READ BEFORE RUNNING:
#   1. DADA2 denoise-paired (LAYOUT="paired", 04_dada2_paired.slurm) CANNOT be used.
#      There are no Illumina R1/R2 pairs here — 454 reads are single fragments,
#      and DADA2 has no paired 454 mode.
#   2. The strictly-correct QIIME2 denoiser for 454 is `qiime dada2 denoise-pyro`
#      (single-end, 454/Ion Torrent error model), now implemented as
#      04_dada2_pyro.slurm and selected below via DENOISER="pyro" (best
#      fidelity to the platform: tolerates variable length + homopolymer indels).
#      Alternatives: DENOISER="deblur" (04_deblur.slurm; fixed-length
#      trim, lossy on 200-1000 bp variable 454 reads), or EXCLUDE this study from
#      the ASV meta-analysis and fold in the authors' published OTU table
#      (figshare 6508187) instead. denoise-paired (04_dada2_paired.slurm) still CANNOT
#      be used (see #1).
#   3. RAW-DATA AVAILABILITY (RESOLVED): per-sample demultiplexed FASTQ ARE on
#      ENA under PRJEB25221 (the figshare SFF record 6508250 points to it), so
#      01_fetch works. NOTE: `fasterq-dump --split-files` emits 3 files per run
#      (${RUN}_1, ${RUN}_2, ${RUN}) where _1 and _2 are BYTE-IDENTICAL dups and
#      orientation is mixed — do NOT treat the 3 files as coverage. This is
#      cleaned up by the mandatory prep_ingham_454.sh pre-step (see below).
#      (figshare also has OTU/taxonomy tables 6508187 and clinical data 6508232
#      if you ever prefer the authors' published OTU table over re-processing.)
#   4. PLATFORM CONFOUND (dissertation note): mixing a single 454 dataset into
#      an otherwise Illumina MiSeq meta-analysis introduces a platform batch
#      effect on ASV/OTU calls and read lengths. Worth flagging in the
#      harmonization writeup / deciding inclusion criteria deliberately.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="Ingham2019"
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: 454 single-fragment reads -> single-end route ------------------
# NOT paired. If/when a denoise-pyro job is added, point LAYOUT/DENOISE at it;
# until then "single" routes to 02_import_single.slurm + 04_deblur.slurm
# (Deblur) as the closest available approximation. See consequence #2 above.
LAYOUT="single"

# Concatenated-read split does not apply to 454 single fragments.
SPLIT_CONCAT=0

# --- MANDATORY PRE-STEP: run chpc/lib/prep_ingham_454.sh after 01_fetch -------
# `fasterq-dump --split-files` produces THREE files per run with 454/ENA quirks
# (verified on ERR2666851 = sample P01.w1):
#   * ${RUN}_1.fastq and ${RUN}_2.fastq are BYTE-IDENTICAL (fasterq-dump dup,
#     NOT two directions) -> keep one, drop _2.
#   * The 5' forward/linker primer is ALREADY REMOVED by the depositor
#     (split_libraries.py output) -> no read starts with 519F/926R.
#   * Reads are MIXED orientation, tagged in the read NAME (.R1_ = forward
#     519F->926R, .R2_ = reverse 926R->519F).
#   * The 3' REVERSE primer + a ~50 bp 454 tail is RETAINED and must be trimmed.
# prep_ingham_454.sh normalizes all of this: drops _2, pools _1+bare, trims the
# 3' reverse primer + tail (cutadapt, both revcomp primers) in native
# orientation, reverse-complements the R2 reads to a single forward orientation,
# dedups by read ID, writes ONE clean ${RUN}.fastq per run, and MOVES the raw
# inputs into RawData/_raw454/ so 02_import_single's manifest glob only sees the
# cleaned files. RUN IT BEFORE 02_import_single:
#   source chpc/config.sh && load_qiime2_env      # provides cutadapt
#   bash chpc/lib/prep_ingham_454.sh "$WORK_BASE/Ingham2019/RawData"
#
# --- Primers: 16S V4-V5, 519F / 926R (Ingham 2019, Methods) ------------------
# Kept here for provenance only. All primer/tail removal AND orientation
# normalization happen in prep_ingham_454.sh above, NOT in the QIIME2 pipeline.
#   519F (fwd): CAGCAGCCGCGGTAATAC        (18 nt)
#   926R (rev): CCGTCAATTCCTTTGAGTTT      (20 nt)
#   revcomp(519F): GTATTACCGCGGCTGCTG     (3' adapter on a reverse/R2 read)
#   revcomp(926R): AAACTCAAAGGAATTGACGG   (3' adapter on a forward/R1 read)
#
# >>> LEAVE THESE EMPTY <<< The cleaned reads are already primer-free and
# single-orientation, so the cutadapt step in 04_deblur is a NO-OP for
# this study. Setting either of these would DOUBLE-TRIM real 16S bases.
FWD_PRIMER=""            # already stripped by depositor + prep_ingham_454.sh
REV_PRIMER_RC=""         # already stripped by prep_ingham_454.sh

# --- Denoiser selection (single-end route) ----------------------------------
# "pyro"   -> 04_dada2_pyro.slurm : DADA2 denoise-pyro, the 454/Ion Torrent
#             error model. Preferred here: it tolerates variable read length and
#             454 homopolymer indels instead of trimming everything to one fixed
#             length. Uses the PYRO_* parameters below.
# "deblur" -> 04_deblur.slurm : Deblur (fixed-length trim; lossy on the
#             200-1000 bp variable 454 reads). Uses the Deblur parameters below.
# Both read the same demux.qza from 02_import_single; switch freely by changing
# this one line.
DENOISER="pyro"

# --- DADA2 denoise-pyro parameters (used when DENOISER="pyro") ---------------
# PYRO_TRUNC_LEN: truncate every read at this position and DISCARD shorter reads
# (DADA2 requires all reads the same length). Set from demux_viz.qzv — pick a
# length that keeps most reads while cutting the low-quality 3' tail. Cleaned
# ERR2666851 ran min=60 mean=369 max=610 bp, so a value around 250-300 is a
# reasonable starting point; 0 = NO truncation (keep full length, rely on max-ee
# /trunc-q). Empty = unset -> the job ABORTS (forces you to inspect the plot
# first, like Deblur's TRIM_LENGTH guard). Set a positive length, or an explicit
# 0 if you deliberately want NO truncation.
PYRO_TRUNC_LEN=""
PYRO_TRIM_LEFT=0          # 5' trim; 0 — primers already removed by prep_ingham_454.sh
PYRO_MAX_LEN=0            # drop reads longer than this pre-trim; 0 = off
PYRO_MAX_EE=2.0          # max expected errors (DADA2 default 2.0)
PYRO_TRUNC_Q=2          # truncate at first base <= this quality (default 2)
PYRO_THREADS=16          # match 04_dada2_pyro --cpus-per-task
PYRO_TIME="12:00:00"     # walltime for the pyro denoise job

# --- Deblur denoise-16S parameters (used when DENOISER="deblur") -------------
# TRIM_LENGTH: Deblur trims EVERY read to this fixed length and DISCARDS reads
# shorter than it. 454 reads are 200-1000 bp and highly variable, so this is
# lossy — set MANUALLY and conservatively from demux_viz.qzv (length/quality
# plot) to keep most reads while cutting the low-quality 3' tail. 0 = unset
# (job refuses to run).
TRIM_LENGTH=0

# LEFT_TRIM_LEN: 5' bases Deblur removes before denoising. Leave 0 — the 5'
# primer was already removed upstream (depositor + prep_ingham_454.sh), and the
# reads are forward-oriented, so there is nothing more to strip at the 5' end.
LEFT_TRIM_LEN=0

# Quality-filter q-score minimum (Deblur tutorial default = 4). The paper kept
# reads with min quality score 25 in QIIME1; that is not directly comparable.
MIN_QUALITY=4

# CPU threads for Deblur (match --cpus-per-task in 04_deblur.slurm).
DEBLUR_THREADS=16

# Optional QIIME sample-metadata TSV for feature-table summarize. Leave "" to
# skip. (Clinical + sample metadata: figshare 10.6084/m9.figshare.6508232.)
METADATA=""

# Walltime hints (edit per dataset size). 97 fecal samples, 30 patients.
FETCH_TIME="00:30:00"
IMPORT_TIME="04:00:00"
DEBLUR_TIME="12:00:00"
