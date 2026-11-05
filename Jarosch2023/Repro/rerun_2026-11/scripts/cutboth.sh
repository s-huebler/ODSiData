#!/bin/bash
set -euo pipefail
IN=$1; OUT=$2; CA=/home/claude/tools/cutadapt-3.5/bin/cutadapt; mkdir -p $OUT/logs
for f in $IN/*.fastq.gz; do s=$(basename $f .fastq.gz)
 $CA -g V13=AGRGTTYGATYMTGGCTCAG -g V34=CCTACGGGNGGCWGCAG -e 0.15 -O 15 --discard-untrimmed --minimum-length 50 -j 2 -o $OUT/$s.fastq.gz $f > $OUT/logs/$s.txt
done
