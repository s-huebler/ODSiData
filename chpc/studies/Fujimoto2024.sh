#!/bin/bash
# =============================================================================
# chpc/studies/Fujimoto2024.sh
# Fujimoto et al. 2024 (Nature) — allo-HCT gut microbiome; Enterococcus
# domination and GvHD. Faecal 16S rRNA time series (pre-transplant through
# day 98). Osaka Metropolitan U. / IMSUT cohort.
#
# 16S rRNA V3-V4, Illumina MiSeq (v3 Reagent kit, 15% PhiX), PAIRED-END.
# Two-round PCR: first round amplifies V3-V4 with 341F/805R carrying 5'
# second-round-PCR overhangs; second round adds NEBNext Dual Index adapters.
# Standard Illumina R1/R2 -> default paired-end route (02_import_paired ->
# 04_dada2_paired). No FETCH_JOB / LAYOUT overrides.
#
# Primers (paper "16S rRNA gene analysis"), underline = overhang for 2nd-round
# PCR (NOT 16S, and NOT on the reads at the trim-left position — the R1/R2
# sequencing primers anneal to the overhang, so each read begins at the 16S
# primer):
#   FWD full: 5'-ACACGACGCTCTTCCGATCT CCTACGGGNGGCWGCAG-3'
#             overhang ACACGACGCTCTTCCGATCT (20 nt) + 341F CCTACGGGNGGCWGCAG (17 nt)
#   REV full: 5'-GACGTGTGCTCTTCCGATCT GACTACHVGGGTATCTAATCC-3'
#             overhang GACGTGTGCTCTTCCGATCT (20 nt) + 805R GACTACHVGGGTATCTAATCC (21 nt)
#   -> 16S primers are the Klindworth 2013 341F / 805R V3-V4 pair (same reverse
#      primer as DAmico2019's 785R; revcomp = GGATTAGATACCCBDGTAGTC).
#
# DADA2: the paper strips the 16S primers POSITIONALLY inside dada2
# denoise-paired (trim-left-f 17 = |341F|, trim-left-r 21 = |805R|) rather than
# with a separate cutadapt pass. We reproduce that exactly: PRIMER_F/PRIMER_R
# left empty (trim stage SKIPPED), primers removed via TRIM_LEFT_F/R below.
# Paper's exact call:
#   qiime dada2 denoise-paired --p-trim-left-f 17 --p-trim-left-r 21 \
#       --p-trunc-len-f 275 --p-trunc-len-r 215 --p-n-threads 16
# (Alternative, if you ever prefer by-sequence removal per the _template.sh
# guidance: set PRIMER_F="CCTACGGGNGGCWGCAG", PRIMER_R="GACTACHVGGGTATCTAATCC",
# run the trim stage, and set TRIM_LEFT_F/R=0. Not used here — positional
# trim-left at fixed MiSeq read-start is faithful to the published pipeline.)
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="Fujimoto2024"

# Run list — one SRR/DRR/ERR per line, committed under Fujimoto2024/RawData/.
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: standard Illumina paired-end (default route) --------------------
# Leave LAYOUT unset ("paired"): submit.sh uses 02_import_paired + 04_dada2_paired.

# --- Primer removal: SKIPPED (primers stripped positionally in DADA2 below) ---
# Empty -> no cutadapt trim stage; denoise runs on the raw demux and removes the
# 341F/805R primers via TRIM_LEFT_F/R, matching the paper.
PRIMER_F=""
PRIMER_R=""

# --- DADA2 denoise-paired parameters (paper's exact values) ------------------
# 5' primer trim = primer lengths (341F = 17 nt, 805R = 21 nt).
TRIM_LEFT_F=17
TRIM_LEFT_R=21
# 3' truncation from the paper. VERIFY against demux_viz.qzv (raw quality plot,
# no trim stage ran) before trusting the run: F=275 keeps the V3-V4 forward read
# well past center; R=215 trims the weaker MiSeq v3 reverse tail while leaving
# enough overlap to merge (~2x300 chemistry, ~465 bp V3-V4 amplicon).
TRUNC_LEN_F=275
TRUNC_LEN_R=215

# CPU threads for DADA2 (match --cpus-per-task in 04_dada2_paired.slurm).
DADA2_THREADS=16

# --- QIIME sample-metadata TSV for feature-table summarize -------------------
# >>> PLACEHOLDER — build the QIIME tsv (first column sample-id matching the run
# IDs) from Fujimoto2024/Metadata/ and point METADATA at it, e.g.
# "$REPO_ROOT/$STUDY/Metadata/fujimoto_meta_qiime.tsv". Leave "" to skip the
# metadata-annotated summary (import + denoise don't need it).
METADATA="$REPO_ROOT/$STUDY/Metadata/fuji_meta_qiime.tsv"                

# Walltime hints per stage (edit per dataset size). Used by submit.sh — dense
# longitudinal cohort, expect many runs; DENOISE_TIME covers the DADA2 job.
FETCH_TIME="00:10:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="01:00:00"
DENOISE_TIME="7:00:00"
