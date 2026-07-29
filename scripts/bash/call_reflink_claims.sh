#!/usr/bin/env bash
#
# call_reflink_claims.sh
#
# Expand the "Cited" column of a claims workbook (one reference per row) and
# join it to a citing dictionary, adding citing_id / ref_id / ref_label columns
# to every sheet. Thin wrapper around scripts/reflink_claims.py.
#
# Usage:
#   scripts/bash/call_reflink_claims.sh <claims.xlsx> <citing_dictionary.csv> [output.xlsx]
#
# If <output.xlsx> is omitted, the output is written next to the input claims
# file with a "_reflinked" suffix (e.g. Claims_14July_reflinked.xlsx).
#
# Example:
#   scripts/bash/call_reflink_claims.sh \
#       claim-network2/Claims_14July.xlsx \
#       citation-network/Full_Network/citing_dictionary.csv

set -euo pipefail

usage() {
    echo "Usage: $0 <claims.xlsx> <citing_dictionary.csv> [output.xlsx]" >&2
    exit 1
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || usage

CLAIMS="$1"
DICT="$2"

# Resolve the python script relative to this bash script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="$SCRIPT_DIR/../reflink_claims.py"

[ -f "$CLAIMS" ] || { echo "Error: claims file not found: $CLAIMS" >&2; exit 1; }
[ -f "$DICT" ]   || { echo "Error: dictionary file not found: $DICT" >&2; exit 1; }
[ -f "$PY_SCRIPT" ] || { echo "Error: python script not found: $PY_SCRIPT" >&2; exit 1; }

if [ "$#" -eq 3 ]; then
    OUTPUT="$3"
else
    # Default: <claims-dir>/<claims-stem>_reflinked.xlsx
    CLAIMS_DIR="$(dirname "$CLAIMS")"
    CLAIMS_BASE="$(basename "$CLAIMS")"
    CLAIMS_STEM="${CLAIMS_BASE%.*}"
    OUTPUT="$CLAIMS_DIR/${CLAIMS_STEM}_reflinked.xlsx"
fi

echo "Claims     : $CLAIMS"
echo "Dictionary : $DICT"
echo "Output     : $OUTPUT"
echo

python3 "$PY_SCRIPT" "$CLAIMS" "$DICT" "$OUTPUT"
