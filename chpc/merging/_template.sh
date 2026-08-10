#!/bin/bash
# =============================================================================
# chpc/merging/_template.sh — copy this to <cohort>.sh to define a merge set
# =============================================================================
# A "cohort" is a named set of studies to merge + the parameters for the
# merge -> phylogeny -> taxonomy chain. Sourced AFTER config.sh (so $REPO_ROOT,
# $WORK_BASE, and the GG2_* references are already defined) by both chpc/merge.sh
# and the 07/08/09 job scripts.
#
# Cohorts are named files (like chpc/studies/<Study>.sh) so you can keep several
# side by side — e.g. a full set and an Illumina-only sensitivity set — and rerun
# any of them independently. Outputs are namespaced by COHORT under Merging/.
# =============================================================================

# Cohort name — also the output subfolder: Merging/<COHORT>/
COHORT="ChangeMe"

# Studies to merge (folder names under the repo root). Order doesn't matter.
STUDIES=(Study1 Study2 Study3)

# --- Per-study input artifact selection --------------------------------------
# By default each study contributes $REPO_ROOT/<Study>/Mapped/<name>. Change the
# default names, or override a single study's table/seqs path below ("which
# current table and such"). Keep the `declare -A ... =()` lines even if empty.
MAPPED_TABLE_NAME="mapped-table.qza"
MAPPED_SEQS_NAME="mapped-seqs.qza"
declare -A TABLE_OVERRIDE=(
    # [Study2]="$REPO_ROOT/Study2/Mapped/mapped-table.v2.qza"
)
declare -A SEQS_OVERRIDE=(
    # [Study2]="$REPO_ROOT/Study2/Mapped/mapped-seqs.v2.qza"
)

# --- Merge / taxonomy parameters ---------------------------------------------
# Sample metadata for feature-table summarize + taxa barplots (leave "" to skip
# the metadata-annotated summaries).
METADATA="$REPO_ROOT/merged_metadata.tsv"
# Naive-Bayes confidence for the classifier taxonomy stage (matches Merging.qmd).
CLASSIFIER_CONFIDENCE="0.9"
# GG2 references (phylogeny / taxonomy tree / classifier) come from config.sh.

# --- Per-stage resources (override merge.sh defaults) ------------------------
# MERGE_TIME="02:00:00"; MERGE_MEM="16G"
# PHYLO_TIME="02:00:00"; PHYLO_MEM="16G"
# TAXGG_TIME="04:00:00"; TAXGG_MEM="24G"
# TAXCL_TIME="08:00:00"; TAXCL_MEM="32G"; TAXCL_THREADS=8

# --- Compute target (override merge.sh defaults) -----------------------------
# merge.sh defaults every stage to notchpeak-shared-short (modern AVX2 nodes,
# free, <=8h) to dodge the lonepeak SIGILL issue that hit qc/map. Override here
# or via the environment if you need a different allocation.
# MERGE_ACCOUNT="notchpeak-shared-short"
# MERGE_PARTITION="notchpeak-shared-short"
# MERGE_CLUSTER="notchpeak"
