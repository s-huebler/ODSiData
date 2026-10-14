#!/usr/bin/env bash
# run_repair_sweep.sh
# Sweep fp_len 80, 100, 120 for SAMEA4506927.
# Skips fp_len=40 (known mixed groups, secondary vote too slow on 48K-read buckets).
# Writes per-fp_len repaired FASTQs and a comparison table to Repaired/repair_sweep.md
#
# Run via: srun --jobid=<JOBID> bash scripts/run_repair_sweep.sh

set -euo pipefail
source /uufs/chpc.utah.edu/common/home/u1477302/Documents/ODSiData/chpc/config.sh

SCRIPTS=/uufs/chpc.utah.edu/common/home/u1477302/Documents/ODSiData/scripts
RAW="$WORK_BASE/Liu2017/RawData"
OUT="$WORK_BASE/Liu2017/Repaired"
SAMPLE=SAMEA4506927
R1="$RAW/${SAMPLE}_1.fastq"
R2="$RAW/${SAMPLE}_2.fastq"
TOTAL=335072    # known R1 count

mkdir -p "$OUT"

# Accumulate stats for the comparison table
declare -a FPL_LIST=()
declare -a PAIRS_LIST=()
declare -a RECOVERY_LIST=()
declare -a JOINED_LIST=()
declare -a YIELD_LIST=()

for FPL in 80 100 120; do
    echo ""
    echo "============================================================"
    echo "  [$(date '+%H:%M:%S')]  fp_len = $FPL  START"
    echo "============================================================"

    PREFIX="$OUT/${SAMPLE}_fpl${FPL}"

    python3 "$SCRIPTS/repairseq.py" \
        "$R1" "$R2" "$PREFIX" \
        --fp_len      "$FPL" \
        --kmer_size   40 \
        --vote_threshold 25 \
        --r1_query_tail  96 \
        --max_group   5000 \
        --purity_prefix_len 100

    PAIRS=$(grep -c "^@" "${PREFIX}_1.repaired.fastq" 2>/dev/null || echo 0)
    RECOVERY=$(python3 -c "print(f'{$PAIRS/$TOTAL*100:.1f}')")

    echo ""
    echo "  [$(date '+%H:%M:%S')]  fp_len=$FPL  bbmerge loose=t ..."
    MERGE_OUT=$(bbmerge.sh \
        in1="${PREFIX}_1.repaired.fastq" \
        in2="${PREFIX}_2.repaired.fastq" \
        out=/dev/null \
        loose=t 2>&1)

    echo "$MERGE_OUT" | grep -E "(Joined|Avg Insert)"

    JOINED_N=$(echo "$MERGE_OUT" | awk '/^Joined:/{print $2}')
    JOINED_PCT=$(echo "$MERGE_OUT" | awk '/^Joined:/{gsub(/%/,"",$3); print $3}')
    EFFECTIVE_YIELD=$(python3 -c "print(int($JOINED_N))" 2>/dev/null || echo "$JOINED_N")

    FPL_LIST+=("$FPL")
    PAIRS_LIST+=("$PAIRS")
    RECOVERY_LIST+=("$RECOVERY")
    JOINED_LIST+=("$JOINED_PCT")
    YIELD_LIST+=("$EFFECTIVE_YIELD")

    echo "  fp_len=$FPL  pairs=$PAIRS  recovery=${RECOVERY}%  joined=${JOINED_PCT}%  yield=$EFFECTIVE_YIELD"
    echo "  [$(date '+%H:%M:%S')]  fp_len=$FPL  DONE"
done

# ── Write comparison table ────────────────────────────────────────────────────
SWEEP_MD="$OUT/repair_sweep.md"
{
echo "# SAMEA4506927 repairseq sweep — $(date '+%Y-%m-%d')"
echo ""
echo "Baseline (fp_len=40, blind 1:1 zip, prior run): recovery=90.8%, joined=25.6%, yield≈79K"
echo ""
echo "| fp_len | re-paired | recovery% | joined% | effective yield |"
echo "|--------|-----------|-----------|---------|-----------------|"
echo "| 40     | 304,379   | 90.8%     | 25.6%   | 77,852          |"
for i in "${!FPL_LIST[@]}"; do
    printf "| %-6s | %-9s | %-9s | %-7s | %-15s |\n" \
        "${FPL_LIST[$i]}" "${PAIRS_LIST[$i]}" "${RECOVERY_LIST[$i]}%" \
        "${JOINED_LIST[$i]}%" "${YIELD_LIST[$i]}"
done
echo ""
echo "Target: joined% ≥ 85% (good-sample baseline ~90%)."
echo "Effective yield = re-paired pairs × joined% = usable merged reads."
} > "$SWEEP_MD"

echo ""
echo "============================================================"
echo "  SWEEP COMPLETE — comparison table:"
echo "============================================================"
cat "$SWEEP_MD"

# ── Guardrail ─────────────────────────────────────────────────────────────────
ALL_BELOW=true
for pct in "${JOINED_LIST[@]}"; do
    OK=$(python3 -c "print('yes' if float('${pct}') >= 85 else 'no')" 2>/dev/null || echo no)
    if [[ "$OK" == "yes" ]]; then
        ALL_BELOW=false
        break
    fi
done

if $ALL_BELOW; then
    echo ""
    echo "*** GUARDRAIL TRIGGERED ***"
    echo "Joined% never reached 85% for any fp_len tested (80/100/120)."
    echo "The R1 amplicon tail is too low-quality to re-pair cleanly."
    echo "Recommendation: process these 28 samples as single-end (R1 only)."
fi
