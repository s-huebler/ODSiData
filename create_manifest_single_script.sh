#!/usr/bin/env bash
# create_manifest_single.sh
# Works with older Bash (no associative arrays).
# Generates a QIIME 2 single-end manifest file (tab-separated).
# Header: sample-id<TAB>absolute-filepath
#
# Usage:
#   bash create_manifest_single.sh /path/to/fastqs manifest_single.tsv
# Defaults: search_dir="."  out="manifest_single.tsv"

set -euo pipefail

SEARCH_DIR="${1:-.}"
OUT="${2:-manifest.tsv}"

# sanity checks
if [[ ! -d "$SEARCH_DIR" ]]; then
  echo "Directory not found: $SEARCH_DIR" >&2
  exit 1
fi

# Write header (overwrite existing)
echo -e "sample-id\tabsolute-filepath" > "$OUT"

# patterns to include
shopt -s nullglob
files=( "$SEARCH_DIR"/*.fastq "$SEARCH_DIR"/*.fastq.gz "$SEARCH_DIR"/*.fq "$SEARCH_DIR"/*.fq.gz )
shopt -u nullglob

# exclusion regex for obvious R2/paired files (case-insensitive)
exclude_regex='(_2(\.fastq|\.fq|\.fastq\.gz|\.fq\.gz)$|_R2(\.fastq|\.fq|\.fastq\.gz|\.fq\.gz)$|[._-]R2(\.fastq|\.fq|\.fastq\.gz|\.fq\.gz)$)'
found=0

# helper to produce absolute path without relying on realpath/readlink -f
abs_path() {
  local dir file
  dir="$(cd "$1" && pwd)"
  file="$2"
  printf "%s/%s" "$dir" "$file"
}

for filepath in "${files[@]}"; do
  # skip if glob didn't match (shouldn't happen due to nullglob) or not a regular file
  [[ -f "$filepath" ]] || continue

  filename="$(basename -- "$filepath")"

  # skip obvious reverse/paired files
  if [[ "${filename}" =~ $exclude_regex ]]; then
    # echo "Skipping paired/reverse file: $filename" >&2
    continue
  fi

  # derive sample id by stripping extensions and common suffixes
  id="$filename"
  id="${id%.fastq.gz}"
  id="${id%.fq.gz}"
  id="${id%.fastq}"
  id="${id%.fq}"

  # remove common _1 / _R1 suffix if present (case-insensitive)
  id="${id%_1}"
  id="${id%_R1}"
  id="${id%_r1}"

  # check for duplicate sample-id already in OUT (avoid associative arrays)
  if grep -qP "^${id}\t" "$OUT"; then
    echo "Warning: duplicate sample-id '$id' from file '$filename' — skipping duplicate." >&2
    continue
  fi

  # compute absolute path robustly
  dirpart="$(dirname -- "$filepath")"
  abs="$(abs_path "$dirpart" "$filename")"

  echo -e "${id}\t${abs}" >> "$OUT"
  found=1
done

if [[ $found -eq 0 ]]; then
  echo "No single-end FASTQ files found in '${SEARCH_DIR}' (or only excluded R2 files were present)." >&2
  echo "Searched for: *.fastq, *.fq, *.fastq.gz, *.fq.gz (skipping obvious R2/paired names)." >&2
  exit 2
fi

echo "Created ${OUT}."
