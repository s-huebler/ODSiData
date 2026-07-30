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
#   1. DADA2 denoise-paired (LAYOUT="paired", 03_dada2.slurm) CANNOT be used.
#      There are no Illumina R1/R2 pairs here — 454 reads are single fragments,
#      and DADA2 has no paired 454 mode.
#   2. The strictly-correct QIIME2 denoiser for 454 is `qiime dada2 denoise-pyro`
#      (single-end, 454/Ion Torrent error model). That job does NOT exist in
#      this repo yet (only 03_dada2.slurm = denoise-paired and
#      03_deblur_single.slurm = Deblur). Options:
#        (a) add a denoise-pyro job (best fidelity to the platform), or
#        (b) route through the existing single-end / Deblur path below as an
#            approximation (Deblur trims every read to one fixed length and
#            drops shorter ones — lossy on 200-1000 bp variable 454 reads), or
#        (c) EXCLUDE this study from the ASV meta-analysis and, if needed, fold
#            in the authors' published OTU table from figshare instead.
#   3. RAW-DATA AVAILABILITY: the paper deposits datasets on figshare
#      (OTU/taxonomy tables: 10.6084/m9.figshare.6508187; sequence + clinical
#      data: 10.6084/m9.figshare.6508232), NOT necessarily as SRA fastq.
#      VERIFY that run_accessions.txt actually resolves to fetchable reads
#      before scheduling 01_fetch — there may be no SRA project for this study,
#      in which case the SFF/FASTA must be pulled from figshare and imported
#      manually.
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
# until then "single" routes to 02_import_single.slurm + 03_deblur_single.slurm
# (Deblur) as the closest available approximation. See consequence #2 above.
LAYOUT="single"

# Concatenated-read split does not apply to 454 single fragments.
SPLIT_CONCAT=0

# --- Primers: 16S V4-V5, 519F / 926R (Ingham 2019, Methods) ------------------
# Amplicons were sequenced BIDIRECTIONALLY, so BOTH primers can appear at the 5'
# end depending on read orientation, and the opposite primer's reverse-complement
# can appear at the 3' end. Reads MUST be orientation-normalized before denoising
# (the paper did this with adjust_seq_orientation.py). For cutadapt, strip the
# forward primer at 5' and the revcomp of the reverse primer at 3' AFTER
# orienting all reads 519F -> 926R.
#   519F (fwd): CAGCAGCCGCGGTAATAC        (18 nt)
#   926R (rev): CCGTCAATTCCTTTGAGTTT      (20 nt)
#   revcomp(519F): GTATTACCGCGGCTGCTG     (5' primer if a read is reverse-oriented)
#   revcomp(926R): AAACTCAAAGGAATTGACGG   (3' adapter on a forward-oriented read)
# For the single-end / Deblur cutadapt step (03_deblur_single.slurm):
FWD_PRIMER="CAGCAGCCGCGGTAATAC"          # 519F (5' front, 18 nt)
REV_PRIMER_RC="AAACTCAAAGGAATTGACGG"     # revcomp of 926R (3' adapter, 20 nt)

# --- Deblur denoise-16S parameters (single-end route) -----------------------
# TRIM_LENGTH: Deblur trims EVERY read to this fixed length and DISCARDS reads
# shorter than it. 454 reads are 200-1000 bp and highly variable, so this is
# lossy — set MANUALLY and conservatively from demux_viz.qzv (length/quality
# plot) to keep most reads while cutting the low-quality 3' tail. 0 = unset
# (job refuses to run). Prefer a denoise-pyro job (consequence #2) if fidelity
# matters more than reusing existing infrastructure.
TRIM_LENGTH=0

# LEFT_TRIM_LEN: 5' bases Deblur removes before denoising. Leave 0 — cutadapt
# above already strips the 519F primer by sequence.
LEFT_TRIM_LEN=0

# Quality-filter q-score minimum (Deblur tutorial default = 4). The paper kept
# reads with min quality score 25 in QIIME1; that is not directly comparable.
MIN_QUALITY=4

# CPU threads for Deblur (match --cpus-per-task in 03_deblur_single.slurm).
DEBLUR_THREADS=16

# Optional QIIME sample-metadata TSV for feature-table summarize. Leave "" to
# skip. (Clinical + sample metadata: figshare 10.6084/m9.figshare.6508232.)
METADATA=""

# Walltime hints (edit per dataset size). 97 fecal samples, 30 patients.
FETCH_TIME="00:30:00"
IMPORT_TIME="04:00:00"
DEBLUR_TIME="12:00:00"
