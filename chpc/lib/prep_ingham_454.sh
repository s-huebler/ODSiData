#!/usr/bin/env bash
# =============================================================================
# prep_ingham_454.sh — normalize Ingham2019 ENA 454 reads into ONE clean,
# forward-oriented, primer-free single-end FASTQ per run, ready to hand to
# 02_import_single.slurm. See chpc/studies/Ingham2019.sh for the biology.
#
# WHY THIS EXISTS (confirmed by inspecting ERR2666851):
#   The ENA deposit (PRJEB25221) is the authors' split_libraries.py output, and
#   `fasterq-dump --split-files` turns each run into THREE files with quirks:
#     ${RUN}_1.fastq  ${RUN}_2.fastq  ${RUN}.fastq
#   1. ${RUN}_1.fastq and ${RUN}_2.fastq are BYTE-IDENTICAL — a fasterq-dump
#      duplication artifact, NOT two sequencing directions. Keep one, drop _2.
#   2. The 5' forward/linker primer (519F or 926R) is ALREADY REMOVED by the
#      depositor — no read starts with a primer. So NO 5' primer trimming here
#      or downstream.
#   3. Reads are MIXED orientation, labelled in the read NAME:
#         ...R1_...  = forward  (519F -> 926R)
#         ...R2_...  = reverse  (926R -> 519F)
#   4. The 3' REVERSE primer + a ~50 bp 454 technical tail is RETAINED
#      (the paper disabled reverse-primer removal at demux):
#         forward (R1) reads end in  revcomp(926R) = AAACTCAAAGGAATTGACGG + tail
#         reverse (R2) reads end in  revcomp(519F) = GTATTACCGCGGCTGCTG   + tail
#      Both must be trimmed (adapter + everything 3' of it).
#
# WHAT THIS SCRIPT DOES, PER RUN:
#   1. DROP  ${RUN}_2.fastq                       (identical duplicate of _1)
#   2. POOL  ${RUN}_1.fastq + ${RUN}.fastq        (_1 adds distinct R2 reads)
#   3. TRIM  the 3' reverse primer + tail with cutadapt, giving BOTH revcomp
#            primers as 3' adapters so each read is trimmed in its NATIVE
#            orientation (order matters: trim BEFORE reorienting, exactly like
#            the paper's truncate_reverse_primer -> adjust_seq_orientation).
#            Untrimmed reads (primer not reached) are KEPT, not discarded.
#   4. REORIENT to forward (519F->926R) by the .R1/.R2 read-name tag:
#            R1 kept as-is, R2 reverse-complemented (seq + quality).
#   5. DEDUP by read ID (safety net; abundance-preserving — does NOT collapse
#            identical sequences from distinct molecules).
#   6. WRITE cleaned ${RUN}.fastq into <raw_dir>; MOVE the raw inputs into
#            <raw_dir>/_raw454/ so make_manifest_single.sh (a non-recursive
#            top-level glob) only ever sees the cleaned file.
#
# After this runs, the reads are already primer-free and single-orientation, so
# the cutadapt step in 03_deblur_single is a NO-OP for this study (primers are
# left empty in Ingham2019.sh).
#
# Idempotent: a run whose raw inputs already sit in _raw454/ is skipped.
#
# Requirements: cutadapt and python3 on PATH. On CHPC the QIIME2 module ships
# cutadapt — `source chpc/config.sh && load_qiime2_env` before calling, or run
# inside any env that provides cutadapt.
#
# Usage (on CHPC — no manual module load needed, the script does it):
#   bash chpc/lib/prep_ingham_454.sh [raw_dir]
# Defaults: raw_dir = $WORK_BASE/${STUDY:-Ingham2019}/RawData
# The script sources chpc/config.sh for $WORK_BASE and, if cutadapt isn't
# already on PATH, calls load_qiime2_env (the QIIME2 module ships cutadapt).
# Override the raw dir by passing it as $1; override WORK_BASE/STUDY via env.
# =============================================================================
set -euo pipefail

# --- Pull in CHPC site config (paths + module loaders) ----------------------
# config.sh lives one level up from this lib/ dir. It defines WORK_BASE and the
# load_qiime2_env() helper. Sourcing is safe: it only sets vars (with :- so any
# values you already exported win) and defines functions — it loads no modules.
_PREP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PREP_CHPC_DIR="$(dirname "$_PREP_LIB_DIR")"
if [[ -f "$_PREP_CHPC_DIR/config.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_PREP_CHPC_DIR/config.sh"
else
    echo "WARNING: $_PREP_CHPC_DIR/config.sh not found — WORK_BASE and the QIIME2" >&2
    echo "         module auto-load are unavailable; ensure cutadapt is on PATH." >&2
fi

# --- Primers (revcomp forms are the 3' adapters to strip) --------------------
REVCOMP_926R="${REVCOMP_926R:-AAACTCAAAGGAATTGACGG}"   # 3' adapter on forward (R1) reads
REVCOMP_519F="${REVCOMP_519F:-GTATTACCGCGGCTGCTG}"     # 3' adapter on reverse (R2) reads

# --- cutadapt knobs ----------------------------------------------------------
CA_ERROR="${CA_ERROR:-0.15}"          # 454 is indel-prone; allow a looser match
CA_OVERLAP="${CA_OVERLAP:-10}"        # min primer<->read overlap to trim (primers are 18-20 nt)
CA_MINLEN="${CA_MINLEN:-50}"          # drop reads shorter than this AFTER trimming
CA_THREADS="${CUTADAPT_THREADS:-4}"

# --- Resolve raw dir ---------------------------------------------------------
RAW_DIR="${1:-${WORK_BASE:?set WORK_BASE or pass raw_dir}/${STUDY:-Ingham2019}/RawData}"
[[ -d "$RAW_DIR" ]] || { echo "ERROR: raw_dir not found: $RAW_DIR" >&2; exit 1; }
RAW_DIR="$(cd "$RAW_DIR" && pwd)"
ARCHIVE="$RAW_DIR/_raw454"
mkdir -p "$ARCHIVE"

# --- Ensure cutadapt is available (auto-load the QIIME2 module if needed) -----
# The QIIME2 module ships the cutadapt binary. If it's not already on PATH (e.g.
# you're running the script standalone on a login node), load it via config.sh's
# load_qiime2_env. `|| true` so a module-load failure falls through to the clean
# error below rather than aborting under `set -e`.
if ! command -v cutadapt >/dev/null 2>&1; then
    if declare -F load_qiime2_env >/dev/null 2>&1; then
        echo "cutadapt not on PATH — loading the QIIME2 module (load_qiime2_env)..."
        load_qiime2_env || true
    fi
fi
command -v cutadapt >/dev/null || {
    echo "ERROR: cutadapt still not on PATH after attempting to load the QIIME2 module." >&2
    echo "       Check 'module spider qiime2' and the module name in chpc/config.sh" >&2
    echo "       (load_qiime2_env), or load an env that provides cutadapt, then retry." >&2
    exit 1; }
command -v python3  >/dev/null || { echo "ERROR: python3 not on PATH." >&2; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/prep454.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- Enumerate run accessions present as raw files ---------------------------
# A run is anything with a _1 / _2 / bare fastq at the top level of raw_dir.
shopt -s nullglob
declare -A RUNS=()
for f in "$RAW_DIR"/*.fastq; do
    b="$(basename -- "$f")"; b="${b%.fastq}"
    b="${b%_1}"; b="${b%_2}"
    RUNS["$b"]=1
done
shopt -u nullglob

[[ ${#RUNS[@]} -gt 0 ]] || { echo "No top-level *.fastq runs found in $RAW_DIR — already cleaned?"; exit 0; }

echo "==== prep_ingham_454: $RAW_DIR ===="
echo "Runs to process: ${#RUNS[@]}"
printf 'run\traw_reads\tafter_trim\tR1\tR2\tclean_out\n' > "$RAW_DIR/prep454_summary.tsv"

process_run() {
    local run="$1"
    local f1="$RAW_DIR/${run}_1.fastq" f2="$RAW_DIR/${run}_2.fastq" fb="$RAW_DIR/${run}.fastq"

    # Idempotency: if nothing raw is left at top level for this run, skip.
    if [[ ! -f "$f1" && ! -f "$f2" && ! -f "$fb" ]]; then
        echo "  [$run] no raw inputs at top level — skipping (already cleaned)."
        return 0
    fi

    # 1+2. Pool _1 + bare (skip _2 entirely). Guard against the _1==_2 dup and
    #      against a bare file that is itself one of the cleaned outputs.
    local pool="$TMP/${run}.pool.fastq"
    : > "$pool"
    [[ -f "$f1" ]] && cat "$f1" >> "$pool"
    [[ -f "$fb" ]] && cat "$fb" >> "$pool"
    local raw_reads=$(( $(wc -l < "$pool") / 4 ))
    if (( raw_reads == 0 )); then
        echo "  [$run] pool empty — skipping." ; return 0
    fi

    # 3. Trim 3' reverse primer + tail in native orientation (both revcomp
    #    primers offered; whichever is present is removed along with everything
    #    3' of it). Keep untrimmed reads.
    local trimmed="$TMP/${run}.trim.fastq"
    cutadapt -j "$CA_THREADS" -e "$CA_ERROR" -O "$CA_OVERLAP" -m "$CA_MINLEN" \
        -a "$REVCOMP_926R" -a "$REVCOMP_519F" \
        -o "$trimmed" "$pool" > "$TMP/${run}.cutadapt.log" 2>&1 || {
            echo "  [$run] cutadapt FAILED — see $TMP/${run}.cutadapt.log" >&2; return 1; }
    local after_trim=$(( $(wc -l < "$trimmed") / 4 ))

    # 4+5. Reorient by .R1/.R2 name tag (revcomp R2), dedup by read ID.
    local clean="$RAW_DIR/${run}.clean.fastq"
    RUN_ID="$run" python3 - "$trimmed" "$clean" <<'PY'
import sys, re
inp, out = sys.argv[1], sys.argv[2]
comp = str.maketrans("ACGTNacgtn", "TGCANtgcan")
def rc(s): return s.translate(comp)[::-1]
seen = set()
n_r1 = n_r2 = n_untag = n_out = 0
with open(inp) as fh, open(out, "w") as w:
    while True:
        h = fh.readline()
        if not h: break
        seq = fh.readline().rstrip("\n")
        plus = fh.readline()
        qual = fh.readline().rstrip("\n")
        rid = h[1:].split()[0]          # unique read ID (before first space)
        if rid in seen:                 # dedup by ID (abundance-preserving)
            continue
        seen.add(rid)
        name = h[1:].rstrip("\n")
        if re.search(r"\.R2_", name):
            seq, qual = rc(seq), qual[::-1]
            n_r2 += 1
        elif re.search(r"\.R1_", name):
            n_r1 += 1
        else:
            n_untag += 1                # no tag -> leave as-is (assume forward)
        w.write(f"@{name}\n{seq}\n+\n{qual}\n")
        n_out += 1
sys.stderr.write(f"{n_r1}\t{n_r2}\t{n_untag}\t{n_out}\n")
PY
    # Recover the R1/R2/out counts printed on stderr above.
    read -r c_r1 c_r2 c_untag c_out < <(
        RUN_ID="$run" python3 - "$clean" <<'PY'
import sys, re
r1=r2=un=tot=0
for i,l in enumerate(open(sys.argv[1])):
    if i%4==0:
        tot+=1
        if re.search(r"\.R2_", l): r2+=1
        elif re.search(r"\.R1_", l): r1+=1
        else: un+=1
print(r1, r2, un, tot)
PY
    )
    local clean_out="$c_out"

    # 6. Publish cleaned file as ${run}.fastq and archive raw inputs so the
    #    manifest builder's top-level *.fastq glob only sees the clean one.
    mv -f "$clean" "$RAW_DIR/${run}.fastq.tmp"
    for raw in "$f1" "$f2" "$fb"; do
        [[ -f "$raw" ]] && mv -f "$raw" "$ARCHIVE/"
    done
    mv -f "$RAW_DIR/${run}.fastq.tmp" "$RAW_DIR/${run}.fastq"

    printf '%s\t%d\t%d\t%s\t%s\t%s\n' \
        "$run" "$raw_reads" "$after_trim" "$c_r1" "$c_r2" "$clean_out" \
        >> "$RAW_DIR/prep454_summary.tsv"
    echo "  [$run] raw=$raw_reads -> trim=$after_trim -> clean=$clean_out (R1=$c_r1 R2->fwd=$c_r2 untagged=$c_untag)"
}

rc_any=0
for run in "${!RUNS[@]}"; do
    process_run "$run" || rc_any=1
done

echo
echo "==== done. cleaned ${#RUNS[@]} run(s). ===="
echo "Cleaned reads : $RAW_DIR/<RUN>.fastq   (one per run, forward, primer-free)"
echo "Raw archived  : $ARCHIVE/"
echo "Summary       : $RAW_DIR/prep454_summary.tsv"
echo "Next: submit 02_import_single (LAYOUT=single). cutadapt in 03_deblur_single"
echo "      is a no-op for this study — primers are already gone."
exit $rc_any
