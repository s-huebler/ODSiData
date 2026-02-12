#!/bin/bash

# Check if an input file was provided
if [ -z "$1" ]; then
    echo "Usage: ./clean_metadata.sh input_file.csv"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$(basename "$INPUT_FILE" .csv)_qiime.tsv"

echo "Processing $INPUT_FILE..."

# Pipeline explanation:
# 1. tr '\r' '\n': Converts Windows carriage returns to newlines (fixes common formatting bugs).
# 2. sed 's/","/\t/g': Handles quoted CSV fields if present (simple regex).
# 3. sed 's/,/\t/g': Converts remaining commas to tabs.
# 4. sed '1s/^Run/sample-id/': Renames the first column header from 'Run' to 'sample-id'.
# 5. sed '1s/Sample Name/sample-name/': (Optional) standardizes 'Sample Name' to avoid confusion.

cat "$INPUT_FILE" \
    | tr -d '\r' \
    | sed 's/","/\t/g' \
    | sed 's/,/\t/g' \
    | sed '1s/^Run/sample-id/' \
    > "$OUTPUT_FILE"

echo "Done! Created: $OUTPUT_FILE"
echo "You can now check it with: qiime metadata tabulate --m-input-file $OUTPUT_FILE"