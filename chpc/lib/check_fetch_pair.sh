#!/usr/bin/env bash
# =============================================================================
# check_fetch_pair.sh — verify a split-run ENA fetch (01_fetch_ena_and_pair.slurm)
# before moving on to import. Lightweight enough for a login node; the per-pair
# read/orientation spot-check samples a few pairs by default (--full does all).
#
# Usage (from repo root on CHPC):
#   bash chpc/lib/check_fetch_pair.sh Liu2017            # summary + 5 sampled pairs
#   bash chpc/lib/check_fetch_pair.sh Liu2017 --full     # spot-check ALL pairs (heavier)
#   SAMPLE_N=10 bash chpc/lib/check_fetch_pair.sh Liu2017
#
# Checks:
#   1. expected pairs (unique PAIR_KEY in ENA_REPORT) vs complete pairs on disk
#   2. incomplete pairs (one mate missing/empty) and any missing keys
#   3. orphan reads dropped by repair.sh (large fraction = a pairing problem)
#   4. failed_downloads.txt contents
#   5. sampled pairs: _1/_2 read-count parity + forward/reverse primer fraction
# Exit 0 only if every expected pair is complete with no empty files.
# =============================================================================
set -uo pipefail

STUDY_NAME="${1:?usage: check_fetch_pair.sh <StudyName> [--full]}"
MODE="${2:-}"
SAMPLE_N="${SAMPLE_N:-5}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
source chpc/config.sh
source "chpc/studies/${STUDY_NAME}.sh"

RAW_DIR="$WORK_BASE/$STUDY/RawData"
ENA_REPORT="${ENA_REPORT:-$RAW_DIR/ENA_samples.tsv}"
PAIR_KEY="${PAIR_KEY:-sample_accession}"
ORIENT_WINDOW="${ORIENT_WINDOW:-50}"
ORIENT_READS="${ORIENT_READS:-2000}"
FAILED_LOG="$WORK_BASE/$STUDY/failed_downloads.txt"

echo "==== fetch check: $STUDY ===="
echo "RawData: $RAW_DIR"
[[ -d "$RAW_DIR" ]] || { echo "ERROR: RawData not found — has fetch run?"; exit 2; }

# --- Expected pair keys from the report -------------------------------------
mapfile -t KEYS < <(awk -F'\t' -v key="$PAIR_KEY" '
    NR==1{for(i=1;i<=NF;i++)if($i==key)k=i; if(!k){print "NO_KEY">"/dev/stderr";exit 3} next}
    $k!=""{print $k}' "$ENA_REPORT" | sort -u)
n_expected="${#KEYS[@]}"

# --- 1-2. Completeness ------------------------------------------------------
complete=0; incomplete=(); missing=(); empty=()
for key in "${KEYS[@]}"; do
    f="$RAW_DIR/${key}_1.fastq"; r="$RAW_DIR/${key}_2.fastq"
    if [[ -f "$f" && -f "$r" ]]; then
        if [[ -s "$f" && -s "$r" ]]; then complete=$((complete+1)); else empty+=("$key"); fi
    elif [[ -f "$f" || -f "$r" ]]; then
        incomplete+=("$key")
    else
        missing+=("$key")
    fi
done

echo
echo "--- completeness ---"
echo "expected pairs : $n_expected"
echo "complete pairs : $complete"
echo "incomplete     : ${#incomplete[@]} ${incomplete[*]:-}"
echo "missing        : ${#missing[@]} ${missing[*]:-}"
echo "empty file(s)  : ${#empty[@]} ${empty[*]:-}"

# --- 3. Orphans -------------------------------------------------------------
echo
echo "--- orphans (reads repair.sh could not pair) ---"
shopt -s nullglob
orph=( "$RAW_DIR"/*_orphans.fastq )
if (( ${#orph[@]} == 0 )); then
    echo "no orphan files."
else
    biggest=""
    for o in "${orph[@]}"; do
        lines=$(wc -l < "$o"); reads=$((lines/4))
        (( reads > 0 )) && echo "  $(basename "$o"): $reads reads"
    done | sort -t: -k2 -n | tail -5
    total_orph=$(cat "${orph[@]}" | wc -l); total_orph=$((total_orph/4))
    echo "total orphan reads across all samples: $total_orph  (a few is normal; thousands = investigate)"
fi
shopt -u nullglob

# --- 4. Failure log ---------------------------------------------------------
echo
echo "--- failed_downloads.txt ---"
if [[ -s "$FAILED_LOG" ]]; then echo "PRESENT — review:"; cat "$FAILED_LOG"; else echo "none (empty or absent)."; fi

# --- 5. Sampled read-count parity + orientation -----------------------------
iupac_regex(){ echo "$1"|sed -e 's/M/[AC]/g' -e 's/R/[AG]/g' -e 's/W/[AT]/g' -e 's/S/[CG]/g' -e 's/Y/[CT]/g' -e 's/K/[GT]/g' -e 's/V/[ACG]/g' -e 's/H/[ACT]/g' -e 's/D/[AGT]/g' -e 's/B/[CGT]/g' -e 's/N/[ACGT]/g'; }
RE_F="$(iupac_regex "${PRIMER_F:-}")"; RE_R="$(iupac_regex "${PRIMER_R:-}")"
pct_hits(){ # file regex -> integer % of first ORIENT_READS reads with primer in first window
    awk -v pat="$2" -v max="$ORIENT_READS" -v w="$ORIENT_WINDOW" '
        NR%4==2{c++; if(toupper(substr($0,1,w))~pat)m++; if(c>=max)exit}
        END{ if(c>0) printf "%d", (100*m/c); else print "NA" }' "$1"
}

if [[ "$MODE" == "--full" ]]; then sample=( "${KEYS[@]}" ); else sample=( "${KEYS[@]:0:$SAMPLE_N}" ); fi
echo
echo "--- spot-check (${#sample[@]} pair(s); reads=_1/_2, must be EQUAL; %F in _1 & %R in _2 should be high) ---"
printf "%-16s %10s %10s %8s %8s %8s\n" "pair" "reads_1" "reads_2" "equal?" "%F(_1)" "%R(_2)"
parity_ok=1
for key in "${sample[@]}"; do
    f="$RAW_DIR/${key}_1.fastq"; r="$RAW_DIR/${key}_2.fastq"
    [[ -s "$f" && -s "$r" ]] || { printf "%-16s %10s\n" "$key" "MISSING"; parity_ok=0; continue; }
    n1=$(( $(wc -l < "$f")/4 )); n2=$(( $(wc -l < "$r")/4 ))
    eq="yes"; [[ "$n1" != "$n2" ]] && { eq="NO"; parity_ok=0; }
    pf=$([[ -n "$RE_F" ]] && pct_hits "$f" "$RE_F" || echo "-")
    pr=$([[ -n "$RE_R" ]] && pct_hits "$r" "$RE_R" || echo "-")
    printf "%-16s %10s %10s %8s %7s%% %7s%%\n" "$key" "$n1" "$n2" "$eq" "$pf" "$pr"
done

# --- Verdict ----------------------------------------------------------------
echo
echo "=================================================="
if (( complete == n_expected )) && (( ${#empty[@]} == 0 )) && (( parity_ok == 1 )) && [[ ! -s "$FAILED_LOG" ]]; then
    echo "PASS: all $n_expected pairs complete. Ready: ./chpc/submit.sh $STUDY import"
    exit 0
else
    echo "NOT READY: resolve the items above."
    (( complete < n_expected )) && echo "  - re-run fetch to fill gaps: ./chpc/submit.sh $STUDY fetch (checkpoint skips done pairs)"
    (( parity_ok == 0 )) && echo "  - unequal _1/_2 counts mean a repair/pairing issue for those samples."
    exit 1
fi
