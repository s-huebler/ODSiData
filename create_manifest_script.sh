#!/bin/bash

# This script generates a QIIME 2 paired-end manifest file.
# It first creates the header row.
# Then, it loops through all forward read files (*_1.fastq).
# For each forward read, it constructs the expected reverse read filename.
# It then checks if BOTH the forward and reverse files exist.
# Only if both files exist will it add a line to the manifest.tsv.

# Get the absolute current working directory
CWD=$(pwd)

# Create the header, overwriting any existing manifest.tsv
echo -e "sample-id\tforward-absolute-filepath\treverse-absolute-filepath" > manifest.tsv

# Loop through all files ending in _1.fastq in the current directory
for f in *_1.fastq; do
  # Define the corresponding reverse read filename by replacing _1 with _2
  r="${f/_1.fastq/_2.fastq}"
  
  # Check if both the forward file ($f) and the reverse file ($r) exist
  if [ -f "$f" ] && [ -f "$r" ]; then
    # If both exist, define the sample ID by removing _1.fastq
    id="${f/_1.fastq/}"
    
    # Append the sample information to manifest.tsv
    # Using $CWD ensures we get the full, absolute path
    echo -e "$id\t${CWD}/$f\t${CWD}/$r" >> manifest.tsv
  else
    # Optional: Log a warning for skipped files
    echo "Warning: Skipping ${f/_1.fastq/} because one or both read files are missing." >&2
  fi
done

echo "manifest.tsv has been created."
