#!/usr/bin/env bash
# screen_secondpass.sh — resumable second-pass full-text screening loop.
#
# Loops over PDFs in PDF_DIR, invokes `claude -p` once per PDF with the
# screening-ft prompt, and appends classified rows to OUTPUT_CSV. Tracks
# completed PDFs in a sidecar `.processed.log` so reruns automatically
# pick up where the previous run stopped (e.g. after a token-quota pause).
#
# Usage:
#   ./screen_secondpass.sh PDF_DIR INPUT_CSV OUTPUT_CSV [PROMPT_FILE]
#
# Example:
#   ./screen_secondpass.sh \
#     ~/Documents/ODSi/ODSiData/AI_assisted_litreview/Screening2_AI/Prompt_Gen_V2/V2_Papers \
#     ~/Documents/ODSi/ODSiData/AI_assisted_litreview/Screening2_AI/Prompt_Gen_V2/V2_input.csv \
#     ~/Documents/ODSi/ODSiData/AI_assisted_litreview/Screening2_AI/Prompt_Gen_V2/V2_output.csv

set -euo pipefail

# -----------------------------------------------------------------------------
# Arg parsing
# -----------------------------------------------------------------------------

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    cat >&2 <<EOF
Usage: $0 PDF_DIR INPUT_CSV OUTPUT_CSV [PROMPT_FILE]

  PDF_DIR       Folder containing one .pdf per paper.
  INPUT_CSV     Papers export CSV (read-only).
  OUTPUT_CSV    Destination CSV; created with header on first run, appended
                to thereafter. Resumable across reruns.
  PROMPT_FILE   Optional. Defaults to
                ~/Documents/ODSi/ODSiData/AI_assisted_litreview/prompts/screening-ft_v1.md
EOF
    exit 2
fi

PDF_DIR="$1"
INPUT_CSV="$2"
OUTPUT_CSV="$3"
PROMPT_FILE="${4:-$HOME/Documents/ODSi/ODSiData/AI_assisted_litreview/prompts/screening-ft_v1.md}"

# -----------------------------------------------------------------------------
# Validate inputs
# -----------------------------------------------------------------------------

[ -d "$PDF_DIR" ]     || { echo "PDF_DIR not found: $PDF_DIR" >&2;       exit 1; }
[ -f "$INPUT_CSV" ]   || { echo "INPUT_CSV not found: $INPUT_CSV" >&2;   exit 1; }
[ -f "$PROMPT_FILE" ] || { echo "PROMPT_FILE not found: $PROMPT_FILE" >&2; exit 1; }

command -v claude >/dev/null 2>&1 || {
    echo "claude CLI not on PATH. Activate the environment that exposes Claude Code." >&2
    exit 1
}

# -----------------------------------------------------------------------------
# Sidecar files (derived from OUTPUT_CSV)
# -----------------------------------------------------------------------------

PROCESSED_LOG="${OUTPUT_CSV%.csv}.processed.log"
UNMATCHED_LOG="${OUTPUT_CSV%.csv}.unmatched.log"
RUN_LOG="${OUTPUT_CSV%.csv}.runlog"

# Seed OUTPUT_CSV header from INPUT_CSV on first run.
if [ ! -s "$OUTPUT_CSV" ]; then
    head -n 1 "$INPUT_CSV" > "$OUTPUT_CSV"
    echo "[init] Seeded $OUTPUT_CSV with header from $INPUT_CSV"
fi

touch "$PROCESSED_LOG" "$UNMATCHED_LOG" "$RUN_LOG"

# -----------------------------------------------------------------------------
# Counts (for progress display)
# -----------------------------------------------------------------------------

TOTAL_PDFS=$(find "$PDF_DIR" -maxdepth 1 -type f -name '*.pdf' | wc -l | tr -d ' ')
echo "[init] $TOTAL_PDFS PDFs in $PDF_DIR"
echo "[init] Prompt: $PROMPT_FILE"
echo "[init] Processed log: $PROCESSED_LOG"
echo "[init] Unmatched log: $UNMATCHED_LOG"
echo "[init] Run log:       $RUN_LOG"

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------

# Each iteration: re-scan PDF_DIR, diff against PROCESSED_LOG, take the next.
# This is O(N) per iteration but N≤500 — negligible — and makes the loop
# robust to PDFs added mid-run.

while true; do
    next=$(comm -23 \
        <(find "$PDF_DIR" -maxdepth 1 -type f -name '*.pdf' -exec basename {} \; | LC_ALL=C sort -u) \
        <(LC_ALL=C sort -u "$PROCESSED_LOG") \
        | head -n 1)

    if [ -z "$next" ]; then
        DONE_COUNT=$(wc -l < "$PROCESSED_LOG" | tr -d ' ')
        echo "[done] No remaining PDFs. Processed: $DONE_COUNT / $TOTAL_PDFS"
        exit 0
    fi

    DONE_COUNT=$(wc -l < "$PROCESSED_LOG" | tr -d ' ')
    NEXT_IDX=$((DONE_COUNT + 1))
    PDF_PATH="$PDF_DIR/$next"
    TS=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$TS] ($NEXT_IDX/$TOTAL_PDFS) $next"
    echo "[$TS] ($NEXT_IDX/$TOTAL_PDFS) $next" >> "$RUN_LOG"

    # Per-call stderr is captured so we can detect UNMATCHED notices.
    STDERR_TMP=$(mktemp)

    # Build the per-call message. Claude reads the prompt file and applies it
    # to exactly this PDF + this CSV pair.
    MSG="Follow the instructions in $PROMPT_FILE.

PDF_PATH=$PDF_PATH
INPUT_CSV=$INPUT_CSV
OUTPUT_CSV=$OUTPUT_CSV

Process exactly this one PDF, then stop. Do not process any other PDF."

    if claude -p --dangerously-skip-permissions "$MSG" 2> >(tee -a "$STDERR_TMP" >&2); then
        # Capture any UNMATCHED notices for manual reconciliation.
        if grep -q '^UNMATCHED' "$STDERR_TMP"; then
            grep '^UNMATCHED' "$STDERR_TMP" >> "$UNMATCHED_LOG"
            echo "  -> unmatched; logged to $UNMATCHED_LOG"
        fi
        # Mark PDF as processed on clean exit (matched or unmatched).
        echo "$next" >> "$PROCESSED_LOG"
        rm -f "$STDERR_TMP"
    else
        rc=$?
        echo "[error] claude exited with $rc on '$next'." >&2
        echo "[error] Stopping. Rerun the script to resume." >&2
        cat "$STDERR_TMP" >> "$RUN_LOG"
        rm -f "$STDERR_TMP"
        exit "$rc"
    fi
done
