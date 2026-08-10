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
export CHPC_PARTITION="${CHPC_PARTITION:-lonepeak}"  # sbatch -p / --partition
# Cluster/scheduler to submit to. Each CHPC cluster runs its OWN Slurm
# controller, so a partition is only valid on its own cluster — submitting a
# notchpeak/lonepeak partition from a kingspeak context fails with "invalid
# partition specified". Empty = your login cluster's scheduler; set this
# (paired with a matching CHPC_ACCOUNT/CHPC_PARTITION) to reach another cluster.
# submit.sh turns this into `sbatch --clusters=$CHPC_CLUSTER`.
export CHPC_CLUSTER="${CHPC_CLUSTER:-lonepeak}"      # sbatch -M / --clusters ("" = login cluster)

# --- CPU microarchitecture constraint (avoid "Illegal instruction" SIGILL) ----
# lonepeak's GENERAL nodes are Intel Nehalem — no AVX at all. The qiime2 module's
# vsearch (and qiime's own numpy/scikit-bio C extensions) are built with AVX2, so
# they crash with SIGILL ("Illegal instruction (core dumped)") on those old cores.
# Swapping in a "generic" vsearch does NOT reliably help: vsearch has no runtime
# SIMD dispatch, and if the crash is in qiime's Python stack the vsearch swap is
# irrelevant. The robust fix is to let Slurm skip the old nodes entirely.
#
# NOTE: this is a SECONDARY, best-effort safety net. It only works on clusters
# that actually expose CPU-arch features — and lonepeak does NOT (its nodes are
# tagged only by owner/core-count/memory, e.g. "chpc,c24,m256"), so there is no
# feature to select an AVX2 node there. The PRIMARY fix for the SIMD-sensitive
# stages (qc, map) is submit.sh routing them to a uniformly-modern partition
# (SIMD_* -> notchpeak-shared-short). Keep this list for clusters that DO expose
# arch features (e.g. notchpeak owner nodes); submit.sh intersects it with the
# target cluster's real features and drops the rest, so a bad code can't cause an
# "Invalid feature specification" rejection.
# Codes: bwk=Broadwell, skl=Skylake, csl=Cascade Lake, icl=Icelake, npl=AMD
# Naples, rom=AMD Rome, mil=AMD Milan. Inspect a cluster's features with:
#   sinfo -M <cluster> -N -o "%n %f" | sort -u
# Set CHPC_CPU_CONSTRAINT="" to disable this net entirely.
export CHPC_CPU_CONSTRAINT="${CHPC_CPU_CONSTRAINT:-bwk|skl|csl|icl|npl|rom|mil}"  # sbatch -C / --constraint

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

# --- Merge-phase references (07_merge / 08_phylogeny / 09_taxonomy_*) ---------
# Shared across cohorts. GG2_PHYLOGENY and GG2_CLASSIFIER are already in
# Greengenes2/; GG2_TAXONOMY_TREE (the .taxonomy.asv.nwk.qza) must be downloaded
# into $GG2_REF_DIR from ftp.microbio.me/greengenes_release/<version>/ before the
# tax-gg stage. taxonomy-from-table takes the .nwk taxonomy artifact as input.
export GG2_PHYLOGENY="${GG2_PHYLOGENY:-$GG2_REF_DIR/$GG2_VERSION.phylogeny.asv.nwk.qza}"          # 08_phylogeny filter-tree
export GG2_TAXONOMY_TREE="${GG2_TAXONOMY_TREE:-$GG2_REF_DIR/$GG2_VERSION.taxonomy.asv.nwk.qza}"   # 09_taxonomy_gg taxonomy-from-table
export GG2_CLASSIFIER="${GG2_CLASSIFIER:-$GG2_REF_DIR/$GG2_VERSION.backbone.full-length.nb.sklearn-1.4.2.qza}"  # 09_taxonomy_classifier

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
    # The qiime2/2023.5 module's bundled vsearch is compiled with SIMD instructions
    # that crash ("Illegal instruction") on older lonepeak Nehalem cores. Prepend a
    # locally-built vsearch so classify-consensus-vsearch uses it instead — QIIME2
    # shells out to whatever `vsearch` is first on PATH.
    #
    # NOTE: this is a best-effort mitigation, NOT a guaranteed fix. vsearch has no
    # runtime SIMD dispatch, so even this build can SIGILL on Nehalem, and if the
    # crash is in qiime's own numpy/scikit-bio extensions the swap does nothing.
    # The reliable fix is CHPC_CPU_CONSTRAINT (see above) pinning the job to
    # AVX2-capable nodes. Keep both.
    local _vs_override="$HOME/software/envs/vsearch-2.28/bin"
    export PATH="$_vs_override:$PATH"
    # Hard-verify the override actually took effect. `command -v vsearch` alone is
    # not enough: it succeeds even if the override dir is missing, silently falling
    # back to the module's crashing vsearch. Require the resolved binary to live
    # under $_vs_override.
    local _vs_path; _vs_path="$(command -v vsearch || true)"
    if [[ -z "$_vs_path" ]]; then
        echo "ERROR: 'vsearch' not on PATH after override." >&2; return 1
    fi
    if [[ "$_vs_path" != "$_vs_override/"* ]]; then
        echo "WARNING: vsearch override did NOT take effect." >&2
        echo "         expected under: $_vs_override" >&2
        echo "         actually using: $_vs_path  (likely the module's AVX2 build — may SIGILL)" >&2
        echo "         Build/locate the local vsearch, or rely on CHPC_CPU_CONSTRAINT." >&2
    fi
    # Log what's actually in use so crashes are diagnosable from the job log.
    # Capture (don't pipe to head): a pipe to head + `set -o pipefail` makes vsearch
    # die of SIGPIPE (141), which would mask its real exit status here.
    echo "[env] vsearch -> $_vs_path"
    local _vsv
    if _vsv=$(vsearch --version 2>&1); then
        echo "[env] $(printf '%s\n' "$_vsv" | head -1)"
    else
        echo "[env] WARNING: 'vsearch --version' exited nonzero — it may SIGILL on this node." >&2
    fi
    echo "[env] qiime   -> $(command -v qiime)"
}

# q2-greengenes2 personal conda env -------------------------------------------
# The CHPC qiime2/2023.5 MODULE does NOT ship q2-greengenes2, so the map stage
# (06_gg2_map.slurm) can't use it. Instead we activate a personal conda env that
# clones qiime2 2023.5 and adds the plugin (built once, verified on a compute node:
# `qiime greengenes2 non-v4-16s --help` loads). Its compiled deps (scikit-bio /
# biom / iow) use AVX2 and SIGILL on old cores — which is fine because submit.sh
# routes the map stage to notchpeak-shared-short (SIMD_* target), same as qc.
# Override GG2_ENV if you rebuild the env elsewhere.
export GG2_ENV="${GG2_ENV:-$HOME/software/envs/qiime2-2023.5-gg2}"

load_qiime2_gg2_env() {
    module purge 2>/dev/null || true
    # We activate a conda env by PATH (not the qiime2 module), so we only need
    # anaconda3 to get `conda` + its shell hook.
    module load anaconda3/2023.03 \
        || { echo "ERROR: could not load anaconda3/2023.03 (needed to activate conda envs). Check 'module spider anaconda3'." >&2; return 1; }
    local _conda_base; _conda_base="$(conda info --base 2>/dev/null)"
    # shellcheck disable=SC1091
    source "$_conda_base/etc/profile.d/conda.sh" \
        || { echo "ERROR: could not source conda.sh from $_conda_base." >&2; return 1; }
    [[ -d "$GG2_ENV" ]] \
        || { echo "ERROR: q2-greengenes2 env not found at GG2_ENV=$GG2_ENV." >&2;
             echo "       Build it (qiime2 2023.5 clone + pip install q2-greengenes2) or set GG2_ENV." >&2; return 1; }
    conda activate "$GG2_ENV" \
        || { echo "ERROR: could not 'conda activate $GG2_ENV'." >&2; return 1; }
    command -v qiime >/dev/null \
        || { echo "ERROR: 'qiime' not on PATH after activating $GG2_ENV." >&2; return 1; }
    echo "[env] conda env -> $GG2_ENV"
    echo "[env] qiime     -> $(command -v qiime)"
    echo "[env] vsearch   -> $(command -v vsearch)"
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

# Verify the q2-greengenes2 plugin is loadable in the active env (needed by
# 06_gg2_map.slurm's `qiime greengenes2 non-v4-16s`). With load_qiime2_gg2_env
# this should pass; a failure here on a compute node most likely means either the
# GG2_ENV activation didn't happen, or the node is too old and the plugin's
# compiled deps SIGILL'd (map should run on notchpeak-shared-short — see submit.sh).
check_gg2_plugin() {
    if ! qiime greengenes2 --help >/dev/null 2>&1; then
        echo "ERROR: 'qiime greengenes2' not available / failed to load in the active env." >&2
        echo "       Expected env: GG2_ENV=$GG2_ENV (activated by load_qiime2_gg2_env)." >&2
        echo "       If this ran on an old node, it may be an 'Illegal instruction' crash in the" >&2
        echo "       plugin's compiled deps — resubmit map to notchpeak-shared-short." >&2
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
