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
# PRIMER REMOVAL — cutadapt by-sequence (NOT the paper's positional trim-left).
# The paper stripped primers positionally inside dada2 denoise-paired
# (--p-trim-left-f 17 --p-trim-left-r 21 --p-trunc-len-f 275 --p-trunc-len-r 215
# --p-n-threads 16). We instead remove 341F/805R BY SEQUENCE in the 'trim' stage
# (03_trim_paired.slurm -> qiime cutadapt trim-paired) before denoise: robust to
# any heterogeneity spacer / length variation, matches IUPAC degeneracy
# (N/W/H/V) automatically, and drops off-target pairs where the primer isn't
# found (--p-discard-untrimmed). Primers set via PRIMER_F/PRIMER_R below;
# TRIM_LEFT_F/R zeroed so DADA2 doesn't double-trim.
#   * NOTE: 03_trim_paired.slurm removes the 5' primer ONLY (--p-front-f/-r); it
#     does NOT strip 3' read-through of the opposite primer. On this ~465 bp
#     V3-V4 amplicon at 2x300, 3' read-through is handled by TRUNC_LEN below
#     (as in the paper). To also remove it by sequence, add via CUTADAPT_EXTRA:
#       --p-adapter-f GGATTAGATACCCBDGTAGTC   (revcomp of 805R)
#       --p-adapter-r CTGCWGCCNCCCGTAGG       (revcomp of 341F)
#   * To reproduce the paper's positional route instead: PRIMER_F/PRIMER_R="",
#     TRIM_LEFT_F=17, TRIM_LEFT_R=21, TRUNC_LEN_F=275, TRUNC_LEN_R=215.
# =============================================================================
# Sourced AFTER config.sh, so $REPO_ROOT and $WORK_BASE are already defined.

STUDY="Fujimoto2024"

# Run list — one SRR/DRR/ERR per line, committed under Fujimoto2024/RawData/.
ACCESSIONS="$REPO_ROOT/$STUDY/RawData/run_accessions.txt"

# --- Layout: standard Illumina paired-end (default route) --------------------
# Leave LAYOUT unset ("paired"): submit.sh uses 02_import_paired + 04_dada2_paired.

# --- Primer removal: cutadapt trim-paired ('trim' stage, 03_trim_paired.slurm) -
# Runs AFTER import, BEFORE denoise ( ./chpc/submit.sh Fujimoto2024 trim ). Strips
# 341F/805R by sequence into demux_trimmed.qza; the denoise job auto-detects and
# prefers it. Keep TRIM_LEFT_F/R = 0 below so primers aren't double-trimmed.
PRIMER_F="CCTACGGGNGGCWGCAG"        # 341F (17 nt)
PRIMER_R="GACTACHVGGGTATCTAATCC"    # 805R (21 nt)
# Optional cutadapt knobs (defaults shown; uncomment to override):
# CUTADAPT_ERROR_RATE=0.1
# CUTADAPT_OVERLAP=3
# CUTADAPT_MIN_LENGTH=1
# CUTADAPT_DISCARD_UNTRIMMED="true"  # drop pairs lacking the primer (recommended)

# --- DADA2 denoise-paired parameters -----------------------------------------
# Primers removed by cutadapt above -> NO positional 5' trim here (MUST be 0).
TRIM_LEFT_F=0
TRIM_LEFT_R=0
# 3' truncation = the paper's values translated into the POST-cutadapt coordinate
# frame. cutadapt already stripped the 5' primer, so truncation is measured from
# the primer-free read start: paper_trunc - primer_len ->
#   F: 275 - 17 = 258     R: 215 - 21 = 194
# This preserves the paper's biological read lengths (~258 / ~194 bp) and ~25 bp
# merge overlap on the ~427 bp primer-free V3-V4 insert. VERIFY against
# demux_trimmed_viz.qzv (the POST-trim quality plot) before denoise — set from
# the plot if the quality profile disagrees.
TRUNC_LEN_F=265
TRUNC_LEN_R=194

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
FETCH_TIME="00:15:00"
IMPORT_TIME="04:00:00"
TRIM_TIME="01:00:00"
DENOISE_TIME="7:00:00"
