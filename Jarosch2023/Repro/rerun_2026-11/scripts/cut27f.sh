#!/bin/bash
# Primer-demultiplex: keep reads carrying 27F (S-D-Bact-0008-c-S-20 variant seen in reads), strip it; optionally strip 519R-rc at 3' end.
set -euo pipefail
IN=$1; OUT=$2; MODE=${3:-g}   # g = 5' non-anchored 27F
CA=/home/claude/tools/cutadapt-3.5/bin/cutadapt
mkdir -p $OUT/logs
for f in $IN/*.fastq.gz; do s=$(basename $f .fastq.gz)
  $CA -g AGRGTTYGATYMTGGCTCAG -e 0.15 -O 15 --discard-untrimmed --minimum-length 50 -j 2 -o $OUT/$s.fastq.gz $f > $OUT/logs/$s.txt
done
