#!/usr/bin/env bash
# =============================================================================
# make_manifest_paired.sh — build a QIIME2 paired-end manifest (Phred33 V2).
# Linux/CHPC port of scripts/bash/create_manifest_script.sh: takes explicit
# input dir + output path instead of relying on the current directory.
#
# Usage: make_manifest_paired.sh <fastq_dir> <out_manifest.tsv>
# Emits one row per sample that has BOTH <id>_1.fastq and <id>_2.fastq.
# =============================================================================
set -euo pipefail

FASTQ_DIR="${1:?usage: make_manifest_paired.sh <fastq_dir> <out.tsv>}"
OUT="${2:?usage: make_manifest_paired.sh <fastq_dir> <out.tsv>}"

FASTQ_DIR="$(cd "$FASTQ_DIR" && pwd)"   # absolute
mkdir -p "$(dirname "$OUT")"

printf 'sample-id\tforward-absolute-filepath\treverse-absolute-filepath\n' > "$OUT"

shopt -s nullglob
n=0
for f in "$FASTQ_DIR"/*_1.fastq; do
    r="${f/_1.fastq/_2.fastq}"
    if [[ -f "$f" && -f "$r" ]]; then
        id="$(basename "${f/_1.fastq/}")"
        printf '%s\t%s\t%s\n' "$id" "$f" "$r" >> "$OUT"
        n=$((n+1))
    else
        echo "Warning: skipping $(basename "${f/_1.fastq/}") — missing forward or reverse read." >&2
    fi
done
shopt -u nullglob

echo "Wrote $n paired samples to $OUT"
[[ $n -gt 0 ]] || { echo "ERROR: no paired FASTQs found in $FASTQ_DIR" >&2; exit 2; }
