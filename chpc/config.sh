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
# cores + tens of GB, not a full node — on a whole-node partition (plain
# 'kingspeak') Slurm makes the job wait for an entire free node, which is the
# main cause of long queue waits (see CHPC's slurm-priority-scores page).
# 'kingspeak-shared' shares a node and runs on the same scheduler/account you
# already submit to. For a whole node, override: CHPC_PARTITION=kingspeak.
# NOTE: 'notchpeak-shared-short' lives on the *notchpeak* scheduler — you can't
# reach it from a kingspeak context without `sbatch -M notchpeak` + notchpeak
# access, so it's not a safe default here.
export CHPC_PARTITION="${CHPC_PARTITION:-kingspeak-shared}"  # sbatch -p / --partition

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

# Fail fast if the allocation was left unset.
check_allocation() {
    if [[ "$CHPC_ACCOUNT" == "CHANGE_ME" ]]; then
        echo "ERROR: set CHPC_ACCOUNT in chpc/config.sh (or export it) before submitting." >&2
        return 1
    fi
}
