#!/usr/bin/env bash
# =============================================================================
# make_manifest_single.sh — build a QIIME2 single-end manifest (Phred33 V2).
# Linux/CHPC port of scripts/bash/create_manifest_single_script.sh: takes an
# explicit input dir + output path instead of relying on the current directory.
# Mirrors lib/make_manifest_paired.sh for the single-end / pre-merged layout.
#
# Usage: make_manifest_single.sh <fastq_dir> <out_manifest.tsv>
# Emits one row per single-end FASTQ (SRRxxxxxxx.fastq). Obvious reverse-mate
# files (_2 / _R2) are skipped as a safety net in case a run was mislabelled.
# Header: sample-id<TAB>absolute-filepath
# =============================================================================
set -euo pipefail

FASTQ_DIR="${1:?usage: make_manifest_single.sh <fastq_dir> <out.tsv>}"
OUT="${2:?usage: make_manifest_single.sh <fastq_dir> <out.tsv>}"

FASTQ_DIR="$(cd "$FASTQ_DIR" && pwd)"   # absolute
mkdir -p "$(dirname "$OUT")"

printf 'sample-id\tabsolute-filepath\n' > "$OUT"

# Skip obvious reverse/paired files (case-insensitive) — single layout only.
exclude_regex='([._-]R?2)(\.fastq|\.fq)(\.gz)?$'

shopt -s nullglob
n=0
for f in "$FASTQ_DIR"/*.fastq "$FASTQ_DIR"/*.fastq.gz "$FASTQ_DIR"/*.fq "$FASTQ_DIR"/*.fq.gz; do
    [[ -f "$f" ]] || continue
    base="$(basename -- "$f")"

    # skip reverse-mate files if any slipped through
    if [[ "$base" =~ $exclude_regex ]]; then
        echo "Warning: skipping reverse/paired file $base (single-end layout)." >&2
        continue
    fi

    # derive sample id: strip extension, then a lone _1/_R1 forward suffix
    id="$base"
    id="${id%.fastq.gz}"; id="${id%.fq.gz}"; id="${id%.fastq}"; id="${id%.fq}"
    id="${id%_1}"; id="${id%_R1}"; id="${id%_r1}"

    if grep -qP "^${id}\t" "$OUT"; then
        echo "Warning: duplicate sample-id '$id' from '$base' — skipping." >&2
        continue
    fi

    printf '%s\t%s\n' "$id" "$f" >> "$OUT"
    n=$((n+1))
done
shopt -u nullglob

echo "Wrote $n single-end samples to $OUT"
[[ $n -gt 0 ]] || { echo "ERROR: no single-end FASTQs found in $FASTQ_DIR" >&2; exit 2; }
