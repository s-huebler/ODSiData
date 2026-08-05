#!/bin/bash
# =============================================================================
# chpc/config.sh — CHPC site configuration (edit ONCE for your environment)
# =============================================================================
# Sourced by every job/submit script. Holds account, partition, scratch paths,
# and module-load logic. Do NOT put per-study parameters here — those live in
# chpc/studies/<Study>.sh.
#
# Quick start on CHPC:
#   module spider qiime2        # find the exact QIIME2 module name
#   module spider sra           # find the SRA toolkit module name
# then edit the two load_*_env functions below to match.
# =============================================================================

# --- SLURM allocation --------------------------------------------------------
# Set these to your CHPC allocation. Override at submit time with env vars, e.g.
#   CHPC_ACCOUNT=my-alloc CHPC_PARTITION=notchpeak ./submit.sh Artacho2024
export CHPC_ACCOUNT="${CHPC_ACCOUNT:-qiaox}"          # sbatch -A / --account
# Default to a SHARED partition, not a whole-node one. These jobs need a few
# cores + tens of GB, not a full node — a whole-node partition makes the job
# wait for an entire free node, the main cause of long queue waits (see CHPC's
# slurm-priority-scores page).
#
# We default to LONEPEAK, not kingspeak: as of this writing kingspeak general is
# saturated (all nodes allocated) and 'kingspeak-shared' is drained, so jobs
# there just sit. 'lonepeak-shared' (qiaox allocation) is shared, has generous
# walltime, and usually has free nodes. It lives on the lonepeak scheduler, so
# CHPC_CLUSTER below routes sbatch there.
#
# Common overrides (set on the command line):
#   whole node:        CHPC_CLUSTER=lonepeak  CHPC_PARTITION=lonepeak
#   back to kingspeak: CHPC_CLUSTER=""        CHPC_PARTITION=kingspeak-shared
#   free short (<=8h): CHPC_CLUSTER=notchpeak CHPC_ACCOUNT=notchpeak-shared-short \
#                      CHPC_PARTITION=notchpeak-shared-short
export CHPC_PARTITION="${CHPC_PARTITION:-lonepeak-shared}"  # sbatch -p / --partition
# Cluster/scheduler to submit to. Each CHPC cluster runs its OWN Slurm
# controller, so a partition is only valid on its own cluster — submitting a
# notchpeak/lonepeak partition from a kingspeak context fails with "invalid
# partition specified". Empty = your login cluster's scheduler; set this
# (paired with a matching CHPC_ACCOUNT/CHPC_PARTITION) to reach another cluster.
# submit.sh turns this into `sbatch --clusters=$CHPC_CLUSTER`.
export CHPC_CLUSTER="${CHPC_CLUSTER:-lonepeak}"      # sbatch -M / --clusters ("" = login cluster)

# --- Scratch workspace -------------------------------------------------------
# Large files (FASTQ, demux.qza, intermediate artifacts) live on scratch, never
# in the git repo. Scratch is auto-scrubbed after ~60 days of no access.
export SCRATCH_BASE="${SCRATCH_BASE:-/scratch/general/vast/$USER}"
export WORK_BASE="${WORK_BASE:-$SCRATCH_BASE/ODSiData}"

# --- Repo location on CHPC ---------------------------------------------------
# Auto-detected as the parent of this chpc/ directory. Override if your checkout
# lives elsewhere.
_CHPC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CHPC_DIR="$_CHPC_DIR"
export REPO_ROOT="${REPO_ROOT:-$(dirname "$_CHPC_DIR")}"

# --- Greengenes2 reference artifacts (qc + map stages) -----------------------
# Shared across studies, so they live here (not per-study). Used by
# 05_qc.slurm (classify-consensus-vsearch) and 06_gg2_map.slurm (non-v4-16s).
# GG2_REF_SEQS / GG2_REF_TAX / GG2_BACKBONE are the backbone reference artifacts.
# Two of them (backbone.full-length.fna.qza, backbone.tax.qza) are NOT tracked in
# git — download the release into $GG2_REF_DIR before running the qc/map stages:
#   ftp.microbio.me/greengenes_release/<version>/  (e.g. 2024.09)
export GG2_REF_DIR="${GG2_REF_DIR:-$REPO_ROOT/Greengenes2}"
export GG2_VERSION="${GG2_VERSION:-2024.09}"
export GG2_REF_SEQS="${GG2_REF_SEQS:-$GG2_REF_DIR/$GG2_VERSION.backbone.full-length.fna.qza}"
export GG2_REF_TAX="${GG2_REF_TAX:-$GG2_REF_DIR/$GG2_VERSION.backbone.tax.qza}"
export GG2_BACKBONE="${GG2_BACKBONE:-$GG2_REF_SEQS}"   # non-v4-16s backbone = same seqs

# --- QC gate (classify-consensus-vsearch) default thresholds -----------------
# Keep only ASVs with a confident hit to the GG2 backbone; the rest are dropped
# as Unassigned. Override any of these per study in chpc/studies/<Study>.sh.
export QC_PERC_IDENTITY="${QC_PERC_IDENTITY:-0.97}"    # min % identity to a reference
export QC_QUERY_COV="${QC_QUERY_COV:-0.90}"            # min query coverage
export QC_MAXACCEPTS="${QC_MAXACCEPTS:-10}"            # hits considered per query
export QC_MIN_CONSENSUS="${QC_MIN_CONSENSUS:-0.51}"    # consensus fraction for a call
export QC_TOP_HITS_ONLY="${QC_TOP_HITS_ONLY:-false}"   # only best-identity hits
export QC_EXCLUDE="${QC_EXCLUDE:-Unassigned}"          # taxonomy label(s) to drop

# --- non-v4-16s closed-reference mapping default -----------------------------
export GG2_MAP_PERC_IDENTITY="${GG2_MAP_PERC_IDENTITY:-0.99}"  # clustering identity

# --- Environment modules -----------------------------------------------------
# Wrapped in functions so the job scripts stay clean. EDIT the module names to
# match what `module spider` reports on CHPC.

load_sra_env() {
    module purge 2>/dev/null || true
    module load sra-toolkit/3.1.1 \
        || { echo "ERROR: could not load sra-toolkit/3.1.1. Check 'module spider sra'." >&2; return 1; }
    command -v prefetch >/dev/null || { echo "ERROR: prefetch not on PATH after module load." >&2; return 1; }
}

load_qiime2_env() {
    module purge 2>/dev/null || true
    # QIIME2 on CHPC requires anaconda3 loaded first.
    module load anaconda3/2023.03 && module load qiime2/2023.5 \
        || { echo "ERROR: could not load qiime2/2023.5 (needs anaconda3/2023.03 first). Check 'module spider qiime2'." >&2; return 1; }
    command -v qiime >/dev/null || { echo "ERROR: 'qiime' not on PATH after module load." >&2; return 1; }
}

load_bbmap_env() {
    # BBTools provides repair.sh, used by 01_fetch_ena_and_pair.slurm to re-sync
    # split-run paired-end mates. On CHPC (frisco/kingspeak) the module is
    # 'bbtools/38.86' (there is no 'bbmap' module). Check 'module spider bbtools'.
    module purge 2>/dev/null || true
    module load bbtools/38.86 \
        || { echo "ERROR: could not load bbtools/38.86. Check 'module spider bbtools' (or add BBTools to PATH)." >&2; return 1; }
    command -v repair.sh >/dev/null || { echo "ERROR: 'repair.sh' not on PATH after loading bbtools/38.86." >&2; return 1; }
}

# Verify the q2-greengenes2 plugin is installed in the loaded QIIME2 env (needed
# by 06_gg2_map.slurm's `qiime greengenes2 non-v4-16s`). CHPC's qiime2 module may
# not ship it — if missing, pip-install it into the active env.
check_gg2_plugin() {
    if ! qiime greengenes2 --help >/dev/null 2>&1; then
        echo "ERROR: q2-greengenes2 plugin not available in the loaded QIIME2 env." >&2
        echo "       Install it into the active env, e.g.:  pip install q2-greengenes2" >&2
        echo "       (then re-run 'qiime greengenes2 --help' to confirm)." >&2
        return 1
    fi
}

# Fail fast if the allocation was left unset.
check_allocation() {
    if [[ "$CHPC_ACCOUNT" == "CHANGE_ME" ]]; then
        echo "ERROR: set CHPC_ACCOUNT in chpc/config.sh (or export it) before submitting." >&2
        return 1
    fi
}
