#!/usr/bin/env bash
# run_repairseq_sweep.sh
# Test fp_len 40 / 80 / 120 with secondary k-mer vote within groups.
# Run via:  srun --jobid=<JOBID> bash scripts/run_repairseq_sweep.sh

set -euo pipefail
source /uufs/chpc.utah.edu/common/home/u1477302/Documents/ODSiData/chpc/config.sh

SCRIPTS=/uufs/chpc.utah.edu/common/home/u1477302/Documents/ODSiData/scripts
RAW="$WORK_BASE/Liu2017/RawData"
OUT="$WORK_BASE/Liu2017/Repaired"
SAMPLE=SAMEA4506927
R1="$RAW/${SAMPLE}_1.fastq"
R2="$RAW/${SAMPLE}_2.fastq"

mkdir -p "$OUT"

for FPL in 40 80 120; do
    PREFIX="$OUT/${SAMPLE}_fpl${FPL}"
    echo ""
    echo "============================================================"
    echo "  fp_len = $FPL"
    echo "============================================================"
    python3 "$SCRIPTS/repairseq.py" \
        "$R1" "$R2" "$PREFIX" \
        --fp_len "$FPL" \
        --kmer_size 40 \
        --vote_threshold 25 \
        --r1_query_tail 96

    echo ""
    echo "--- bbmerge fp_len=$FPL ---"
    bbmerge.sh \
        in1="${PREFIX}_1.repaired.fastq" \
        in2="${PREFIX}_2.repaired.fastq" \
        out=/dev/null \
        loose=t \
        2>&1 | grep -E "^(Joined|Avg Insert|Result)"
    echo ""
done

echo "Sweep complete."
