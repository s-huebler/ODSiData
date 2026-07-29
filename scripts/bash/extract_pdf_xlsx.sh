#!/usr/bin/env bash
# extract_pdf_xlsx.sh — batch table + reference extraction from a folder of PDFs.
#
# For every Lastname_Year.pdf in PDF_DIR, invokes `claude -p` once with the
# combined extraction prompt and writes Lastname_Year_tables.xlsx (one sheet per
# table + a References sheet + a Source & Notes sheet) into the SAME folder.
#
# Resumable with no sidecar files: a PDF is skipped if its output .xlsx already
# exists. No logs, decision files, or progress notes are written — the only
# deliverable is the workbook per PDF.
#
# Usage:
#   ./extract_pdf_xlsx.sh PDF_DIR [PROMPT_FILE]
#
# Example:
#   ./extract_pdf_xlsx.sh ~/Documents/ODSi/ODSiData/AI_assisted_litreview/tables_refs/batch1

set -euo pipefail

# -----------------------------------------------------------------------------
# Arg parsing
# -----------------------------------------------------------------------------

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    cat >&2 <<EOF
Usage: $0 PDF_DIR [PROMPT_FILE]

  PDF_DIR      Folder containing one or more Lastname_Year.pdf files. Outputs
               (Lastname_Year_tables.xlsx) are written back into this folder.
  PROMPT_FILE  Optional. Defaults to the combined prompt that ships beside
               this script:
               <script dir>/pdf_extract_prompt.md
EOF
    exit 2
fi

PDF_DIR="${1%/}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="${2:-$SCRIPT_DIR/pdf_extract_prompt.md}"

# -----------------------------------------------------------------------------
# Validate inputs
# -----------------------------------------------------------------------------

[ -d "$PDF_DIR" ]     || { echo "PDF_DIR not found: $PDF_DIR" >&2;       exit 1; }
[ -f "$PROMPT_FILE" ] || { echo "PROMPT_FILE not found: $PROMPT_FILE" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || {
    echo "claude CLI not on PATH. Activate the environment that exposes Claude Code." >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Enumerate work
# -----------------------------------------------------------------------------

TOTAL_PDFS=$(find "$PDF_DIR" -maxdepth 1 -type f -name '*.pdf' | wc -l | tr -d ' ')
[ "$TOTAL_PDFS" -gt 0 ] || { echo "No .pdf files in $PDF_DIR" >&2; exit 1; }

echo "[init] $TOTAL_PDFS PDFs in $PDF_DIR"
echo "[init] Prompt: $PROMPT_FILE"

idx=0
done_count=0
skipped=0

# Sort for stable, predictable order.
while IFS= read -r PDF_PATH; do
    idx=$((idx + 1))
    base=$(basename "$PDF_PATH")
    name_year="${base%.pdf}"
    out_xlsx="$PDF_DIR/${name_year}_tables.xlsx"

    # Resume: skip PDFs whose output already exists.
    if [ -s "$out_xlsx" ]; then
        echo "[$idx/$TOTAL_PDFS] $base -> exists, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    TS=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TS] [$idx/$TOTAL_PDFS] $base -> ${name_year}_tables.xlsx"

    MSG="Follow the instructions in $PROMPT_FILE.

INPUT_PDF=$PDF_PATH
OUTPUT_XLSX=$out_xlsx
NAME_YEAR=$name_year

Process exactly this one PDF, then stop. Do not process any other PDF. Write only OUTPUT_XLSX."

    if claude -p --dangerously-skip-permissions "$MSG"; then
        if [ -s "$out_xlsx" ]; then
            echo "  -> done: $out_xlsx"
            done_count=$((done_count + 1))
        else
            echo "[warn] claude finished but $out_xlsx was not created for '$base'." >&2
        fi
    else
        rc=$?
        echo "[error] claude exited with $rc on '$base'. Stopping; rerun to resume." >&2
        exit "$rc"
    fi
done < <(find "$PDF_DIR" -maxdepth 1 -type f -name '*.pdf' | LC_ALL=C sort)

echo "[done] Created: $done_count  Skipped (already done): $skipped  Total: $TOTAL_PDFS"
