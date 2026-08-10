#!/bin/bash
# =============================================================================
# chpc/merging/full_cohort.sh — all seven GG2-mapped studies
# =============================================================================
# The full harmonized cohort: every study that has completed the qc + map stages
# (06_gg2_map.slurm), merged in the GG2 backbone namespace. Sourced AFTER
# config.sh by chpc/merge.sh and the 07/08/09 jobs.
#
# For a sensitivity analysis that drops the 454 study (Ingham2019 is Roche 454,
# a platform confound vs the Illumina studies), copy this to illumina_only.sh and
# remove Ingham2019 from STUDIES.
# =============================================================================

COHORT="full_cohort"

STUDIES=(
    Liu2017
    Fujimoto2024
    Artacho2024
    DAmico2019
    Ingham2019
    Jarosch2023
    Vallet2023
)

# --- Per-study input artifact selection (defaults to each study's map output) -
MAPPED_TABLE_NAME="mapped-table.qza"
MAPPED_SEQS_NAME="mapped-seqs.qza"
declare -A TABLE_OVERRIDE=()
declare -A SEQS_OVERRIDE=()

# --- Merge / taxonomy parameters ---------------------------------------------
METADATA="$REPO_ROOT/Merging/merged_metadata.tsv"
CLASSIFIER_CONFIDENCE="0.9"

# --- Per-stage resources: use merge.sh defaults (uncomment to override) -------
# MERGE_TIME="02:00:00"; MERGE_MEM="16G"
# PHYLO_TIME="02:00:00"; PHYLO_MEM="16G"
# TAXGG_TIME="04:00:00"; TAXGG_MEM="24G"
# TAXCL_TIME="08:00:00"; TAXCL_MEM="32G"; TAXCL_THREADS=8
