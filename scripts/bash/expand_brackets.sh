#!/usr/bin/env bash
#
# Expand bracketed reference lists in the last column of an Excel file.
#
# Usage:
#   ./expand_brackets.sh <input.xlsx> <output.xlsx>
#
set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input.xlsx> <output.xlsx>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# expand_brackets.py lives one level up, in scripts/
PY_SCRIPT="${SCRIPT_DIR}/../expand_brackets.py"

python3 "${PY_SCRIPT}" "$1" "$2"
