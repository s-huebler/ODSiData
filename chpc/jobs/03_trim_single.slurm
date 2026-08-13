#!/bin/bash
# =============================================================================
# 03_trim_single.slurm — SINGLE-END / pre-merged primer removal with cutadapt.
# Strips primers from the single-end demux.qza produced by 02_import_single.slurm
# (on scratch) using `qiime cutadapt trim-single`, then writes demux_trimmed.qza
# + a fresh quality plot (demux_trimmed_viz.qzv). This is the standalone `trim`
# stage that used to live inside the single-end denoise jobs (Deblur / DADA2
# denoise-single / denoise-pyro).
#
# WORKFLOW: import -> [inspect demux_viz.qzv] -> trim (THIS job) -> [inspect
# demux_trimmed_viz.qzv, set the denoiser's trim/trunc length] -> denoise
# (04_deblur.slurm | 04_dada2_single.slurm | 04_dada2_pyro.slurm). The denoise
# job auto-detects demux_trimmed.qza and prefers it.
#
# -----------------------------------------------------------------------------
# TWO-PASS PRIMER REMOVAL (changed 2026-08-13 — see the DAmico2019 bug below)
# -----------------------------------------------------------------------------
# Merged / pre-joined amplicons carry TWO primers: the forward primer at the 5'
# end and revcomp(reverse primer) at the 3' end. This job removes them in two
# SEPARATE cutadapt calls:
#
#   pass 1  --p-front   FWD_PRIMER      (+ --p-discard-untrimmed by default)
#   pass 2  --p-adapter REV_PRIMER_RC   (never discards)
#
# WHY NOT ONE CALL WITH BOTH FLAGS (the previous behaviour):
#   cutadapt defaults to --times 1, i.e. it removes AT MOST ONE adapter per read.
#   With --p-front and --p-adapter passed to a single call it finds whichever
#   matches best (in practice the 3' revcomp), trims it, and stops — the 5'
#   forward primer is never searched for. Worse, --p-discard-untrimmed only
#   discards reads where ZERO adapters matched, so those reads sail through the
#   gate still carrying the forward primer. This silently happened to
#   DAmico2019: 1586/1634 Deblur rep-seqs still began with an intact 341F.
#
# WHY NOT JUST --p-times 2:
#   It fixes the "only one adapter removed" half, but --p-discard-untrimmed
#   still means "at least one adapter found". A read that matches the 3' adapter
#   but NOT the 5' primer survives with the primer attached, producing ASVs that
#   differ from their neighbours by a 17-21 nt prefix — poison for a
#   cross-study meta-analysis. Splitting the passes makes the 5' requirement
#   unambiguous: pass 1 drops every read lacking the forward primer, and pass 2
#   is free to leave the 3' adapter alone on reads that were truncated before
#   reaching it (legitimately common, and NOT a reason to discard the read).
#
# Runs when FWD_PRIMER and/or REV_PRIMER_RC is set; if BOTH are empty the job is
# a NO-OP (prints a note and exits 0) and denoise falls back to the raw
# demux.qza — e.g. Ingham2019, whose primers are already stripped upstream by
# prep_ingham_454.sh.
#
# Tunables (set in chpc/studies/<Study>.sh, defaults in parentheses):
#   CUTADAPT_ERROR_RATE (0.1)          --p-error-rate
#   CUTADAPT_OVERLAP (3)               --p-overlap
#   CUTADAPT_MIN_LENGTH (1)            --p-minimum-length
#   CUTADAPT_DISCARD_UNTRIMMED (true)  drop reads with no 5' primer (pass 1 only)
#   CUTADAPT_EXTRA ("")                raw extra flags, applied to BOTH passes
#   PRIMER_CHECK (true)                post-trim residual-primer audit
#
# Submit via chpc/submit.sh (routes here when the study sets LAYOUT="single").
# Standalone:
#   sbatch -A <acct> -p notchpeak \
#          --export=ALL,STUDY_FILE=studies/DAmico2019.sh chpc/jobs/03_trim_single.slurm
# =============================================================================
#SBATCH --job-name=qiime-trim-single
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=04:00:00
#SBATCH --output=chpc/logs/trim_single_%j.out
#SBATCH --error=chpc/logs/trim_single_%j.err

set -euo pipefail

: "${STUDY_FILE:?STUDY_FILE must be exported (e.g. studies/DAmico2019.sh)}"
cd "${SLURM_SUBMIT_DIR:-.}"
source chpc/config.sh
source "chpc/$STUDY_FILE"

load_qiime2_env

# --- Node-local temp for QIIME2/cutadapt intermediates -----------------------
if [[ -d /scratch/local ]]; then
    export TMPDIR="/scratch/local/$USER/${SLURM_JOB_ID:-$$}"
else
    export TMPDIR="${TMPDIR:-/tmp}/odsi-${SLURM_JOB_ID:-$$}"
fi
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR" 2>/dev/null || true' EXIT

QD="$WORK_BASE/$STUDY/QiimeData"          # working artifacts (scratch)
mkdir -p "$QD"

THREADS="${SLURM_CPUS_PER_TASK:-${CUTADAPT_THREADS:-8}}"

FWD_PRIMER="${FWD_PRIMER:-}"              # 5' forward primer (--p-front)
REV_PRIMER_RC="${REV_PRIMER_RC:-}"        # 3' adapter = revcomp of reverse primer

ERROR_RATE="${CUTADAPT_ERROR_RATE:-0.1}"
OVERLAP="${CUTADAPT_OVERLAP:-3}"
MIN_LENGTH="${CUTADAPT_MIN_LENGTH:-1}"
DISCARD_UNTRIMMED="${CUTADAPT_DISCARD_UNTRIMMED:-true}"

# --- Precondition: demux.qza from the single-end import step must exist ------
if [[ ! -f "$QD/demux.qza" ]]; then
    echo "ERROR: $QD/demux.qza not found. Run 02_import_single.slurm first." >&2
    exit 1
fi

echo "==== cutadapt trim-single for $STUDY ===="
echo "Work    : $QD"
echo "primers : fwd='${FWD_PRIMER:-none}' rev_rc='${REV_PRIMER_RC:-none}'"
echo "params  : error-rate=$ERROR_RATE overlap=$OVERLAP min-length=$MIN_LENGTH" \
     "discard-untrimmed(5')=$DISCARD_UNTRIMMED threads=$THREADS"

# --- No primers set -> nothing to trim ---------------------------------------
if [[ -z "$FWD_PRIMER" && -z "$REV_PRIMER_RC" ]]; then
    echo "Neither FWD_PRIMER nor REV_PRIMER_RC set in the study file — nothing to trim."
    echo "Skipping cutadapt; the denoise job will fall back to the raw demux.qza."
    exit 0
fi

# Shared flags for both passes.
COMMON_ARGS=(--p-error-rate "$ERROR_RATE"
             --p-overlap "$OVERLAP"
             --p-minimum-length "$MIN_LENGTH"
             --p-cores "$THREADS"
             --verbose)
# Escape hatch: extra raw flags from the study file (space-separated), applied
# to both passes, e.g. CUTADAPT_EXTRA="--p-indels --p-match-read-wildcards".
if [[ -n "${CUTADAPT_EXTRA:-}" ]]; then
    # shellcheck disable=SC2206
    COMMON_ARGS+=(${CUTADAPT_EXTRA})
fi

IN="$QD/demux.qza"
INTERMEDIATE=""

# --- Pass 1: 5' forward primer (--p-front) -----------------------------------
if [[ -n "$FWD_PRIMER" ]]; then
    if [[ -n "$REV_PRIMER_RC" ]]; then
        OUT="$QD/demux_trim5.qza"; INTERMEDIATE="$OUT"
    else
        OUT="$QD/demux_trimmed.qza"
    fi

    echo
    echo "---- pass 1/2: 5' forward primer ----"
    echo "  --p-front $FWD_PRIMER"

    PASS1_ARGS=(--i-demultiplexed-sequences "$IN"
                --p-front "$FWD_PRIMER"
                "${COMMON_ARGS[@]}"
                --o-trimmed-sequences "$OUT")
    # Drop reads with no forward primer. This is the meaningful gate: a merged
    # amplicon that does not start with the forward primer is not the target
    # amplicon (or is too degraded to place), so it should not enter denoising.
    if [[ "$DISCARD_UNTRIMMED" == "true" ]]; then
        PASS1_ARGS+=(--p-discard-untrimmed)
    else
        PASS1_ARGS+=(--p-no-discard-untrimmed)
    fi

    rm -f "$OUT"
    qiime cutadapt trim-single "${PASS1_ARGS[@]}"
    IN="$OUT"
else
    echo
    echo "---- pass 1/2: SKIPPED (FWD_PRIMER not set) ----"
fi

# --- Pass 2: 3' revcomp(reverse primer) (--p-adapter) ------------------------
# NEVER --p-discard-untrimmed here: a read whose 3' end was truncated before
# reaching the reverse primer is a perfectly good read and must be kept.
if [[ -n "$REV_PRIMER_RC" ]]; then
    echo
    echo "---- pass 2/2: 3' reverse-primer revcomp ----"
    echo "  --p-adapter $REV_PRIMER_RC"

    rm -f "$QD/demux_trimmed.qza"
    qiime cutadapt trim-single \
        --i-demultiplexed-sequences "$IN" \
        --p-adapter "$REV_PRIMER_RC" \
        "${COMMON_ARGS[@]}" \
        --p-no-discard-untrimmed \
        --o-trimmed-sequences "$QD/demux_trimmed.qza"
else
    echo
    echo "---- pass 2/2: SKIPPED (REV_PRIMER_RC not set) ----"
fi

# Drop the between-pass artifact (large; scratch only).
[[ -n "$INTERMEDIATE" ]] && rm -f "$INTERMEDIATE"

# --- Post-trim audit: are the primers actually gone? -------------------------
# Cheap, non-fatal sanity check. Reads a few fastq.gz members straight out of
# the .qza (it is a zip) and reports what fraction of reads still carry the
# primers, matching IUPAC degenerate bases. Any non-trivial hit rate means the
# trim did not do what you think it did — this is exactly the failure that went
# unnoticed for DAmico2019.
if [[ "${PRIMER_CHECK:-true}" == "true" ]]; then
    echo
    echo "---- post-trim residual-primer audit ----"
    FWD_PRIMER="$FWD_PRIMER" REV_PRIMER_RC="$REV_PRIMER_RC" QZA="$QD/demux_trimmed.qza" \
    python3 - <<'PY' || echo "  (audit skipped — non-fatal)"
import gzip, io, os, re, zipfile

qza = os.environ["QZA"]
fwd = os.environ.get("FWD_PRIMER", "")
rev = os.environ.get("REV_PRIMER_RC", "")

IUPAC = {"A":"A","C":"C","G":"G","T":"T","R":"[AG]","Y":"[CT]","S":"[GC]",
         "W":"[AT]","K":"[GT]","M":"[AC]","B":"[CGT]","D":"[AGT]",
         "H":"[ACT]","V":"[ACG]","N":"[ACGT]"}

def rx(p):
    return re.compile("".join(IUPAC.get(c, c) for c in p.upper()))

MAX_FILES, MAX_READS = 5, 5000
zf = zipfile.ZipFile(qza)
members = [n for n in zf.namelist() if n.endswith(".fastq.gz")][:MAX_FILES]
if not members:
    raise SystemExit("  no fastq.gz members found in the artifact")

n = fwd_hits = rev_hits = 0
lens = []
fwd_rx, rev_rx = (rx(fwd) if fwd else None), (rx(rev) if rev else None)

for m in members:
    with gzip.open(io.BytesIO(zf.read(m)), "rt") as fh:
        for i, line in enumerate(fh):
            if i % 4 != 1:
                continue
            s = line.strip()
            n += 1
            lens.append(len(s))
            # Allow a little slack: the primer could sit a few bases in.
            if fwd_rx and fwd_rx.search(s[:len(fwd) + 5]):
                fwd_hits += 1
            if rev_rx and rev_rx.search(s[-(len(rev) + 5):]):
                rev_hits += 1
            if n >= MAX_READS:
                break
    if n >= MAX_READS:
        break

lens.sort()
q = lambda p: lens[min(len(lens) - 1, int(p * len(lens)))]
print(f"  sampled {n} reads from {len(members)} run(s)")
print(f"  read length: 2%={q(.02)} 25%={q(.25)} 50%={q(.50)} 75%={q(.75)} 98%={q(.98)}")
if fwd_rx:
    print(f"  reads still starting with FWD_PRIMER   : {fwd_hits}/{n} ({100*fwd_hits/n:.2f}%)")
if rev_rx:
    print(f"  reads still ending with REV_PRIMER_RC  : {rev_hits}/{n} ({100*rev_hits/n:.2f}%)")
if (fwd_rx and fwd_hits / n > 0.01) or (rev_rx and rev_hits / n > 0.01):
    print("  *** WARNING: primer sequence still present above 1% — trim did NOT work. ***")
else:
    print("  OK: primers removed.")
PY
fi

# --- Post-trim quality plot — inspect before setting the trim/trunc length ---
qiime demux summarize \
    --i-data "$QD/demux_trimmed.qza" \
    --o-visualization "$QD/demux_trimmed_viz.qzv"

# --- Copy the inspectable plot back into the repo ----------------------------
# demux_trimmed.qza stays on scratch (large / gitignored). Bring back only the
# quality-plot visualization so you can view it locally.
DEST="$REPO_ROOT/$STUDY/QiimeData"
mkdir -p "$DEST"
cp -f "$QD/demux_trimmed_viz.qzv" "$DEST/"

echo
echo "==== Trim done. Primer-trimmed reads: $QD/demux_trimmed.qza ===="
echo "Check the residual-primer audit above, then inspect"
echo "$DEST/demux_trimmed_viz.qzv (view.qiime2.org or 'qiime tools view'),"
echo "set the denoiser's trim/trunc length in chpc/$STUDY_FILE, then: submit.sh $STUDY denoise"
