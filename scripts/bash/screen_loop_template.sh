#!/usr/bin/env bash
# screen_loop.sh — second-pass screening, one PDF per Claude call
set -euo pipefail

PDF_DIR="$HOME/Documents/ODSi/ODSiData/screening/pdfs"
INPUT_CSV="$HOME/Documents/ODSi/ODSiData/screening/first_pass.csv"
OUTPUT_CSV="$HOME/Documents/ODSi/ODSiData/screening/second_pass.csv"
PROMPT_FILE="$HOME/Documents/ODSi/ODSiData/screening/second_pass_prompt.md"

# Seed output CSV with header from input on first run
[ -f "$OUTPUT_CSV" ] || head -1 "$INPUT_CSV" > "$OUTPUT_CSV"

while true; do
  # PDFs present on disk but absent from column 1 of OUTPUT_CSV
  next=$(comm -23 \
    <(find "$PDF_DIR" -maxdepth 1 -name '*.pdf' -exec basename {} .pdf \; | sort) \
    <(awk -F',' 'NR>1 {print $1}' "$OUTPUT_CSV" | sort -u) \
    | head -1)

  if [ -z "$next" ]; then
    echo "Done — no remaining PDFs."
    break
  fi

  echo "[$(date +%H:%M:%S)] Processing: $next"
  claude -p --dangerously-skip-permissions \
    "Follow the instructions in $PROMPT_FILE. Process the PDF at $PDF_DIR/$next.pdf. Find the row in $INPUT_CSV whose identifier matches '$next', copy it verbatim, and append it to $OUTPUT_CSV with the tags column updated to include SecondPass_[include|exclude|unsure] and (if excluded) SecondPass_ExcludeReason_[reason]. Do not modify $INPUT_CSV. Do not re-read PDFs already in $OUTPUT_CSV."
done