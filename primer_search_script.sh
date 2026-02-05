#!/bin/bash

# 1. FIND A FILE (Looks for .fastq.gz, .fastq, .fq.gz, or .fq)
# We grab the first matching file in the folder
FILE=$(ls *fastq* *fq* 2>/dev/null | head -n 1)

if [ -z "$FILE" ]; then
    echo "ERROR: No .fastq or .fastq.gz files found in this directory."
    echo "Please cd into your data folder first."
    exit 1
fi

# 2. CHOOSE THE RIGHT READER (Gzip vs Plain Text)
if [[ "$FILE" == *.gz ]]; then
    echo "Detected compressed file: $FILE"
    # Use zcat for Mac/Linux compatibility to read zipped files
    # If zcat fails on Mac, sometimes 'gzip -cd' is safer
    CAT_CMD="gzip -cd"
else
    echo "Detected uncompressed file: $FILE"
    CAT_CMD="cat"
fi

echo "-------------------------------------------------------"
echo "Checking first 1000 sequences for common primers..."
echo "Translating IUPAC wobble codes (Y, R, W...) to Regex."
echo "-------------------------------------------------------"
printf "%-15s | %-10s | %-30s\n" "Primer" "Hits" "Pattern Searched"
echo "-------------------------------------------------------"

# Function to check a primer
check_primer() {
    NAME=$1
    SEQ=$2
    
    # Translate IUPAC codes to Regex
    # Y->[CT], R->[AG], W->[AT], K->[GT], M->[AC], S->[GC], N->.
    REGEX=$(echo "$SEQ" | sed 's/Y/CT/g' | sed 's/R/AG/g' | sed 's/W/AT/g' | sed 's/K/GT/g' | sed 's/M/AC/g' | sed 's/S/GC/g' | sed 's/N/./g')
    
    # 1. Read file with correct tool
    # 2. Grab top 4000 lines (1000 sequences) to be fast
    # 3. Search for pattern at start of line (^)
    COUNT=$($CAT_CMD "$FILE" | head -n 4000 | grep -E -c "^$REGEX")
    
    printf "%-15s | %-10s | %-30s\n" "$NAME" "$COUNT" "$REGEX"
}

# --- RUN CHECKS ---

# 515F (V4)
check_primer "515F_V4" "GTGYCAGCMGCCGCGGTAA"

# 806R (V4)
check_primer "806R_V4" "GGACTACNVGGGTWTCTAAT"

# 341F (V3-V4)
check_primer "341F_V3V4" "CCTACGGGNGGCWGCAG"

# 27F (V1-V2)
check_primer "27F_V1V2" "AGAGTTTGATCMTGGCTCAG"

echo "-------------------------------------------------------"
echo "INTERPRETATION:"
echo "Hits > 0  : Primers are attached. Set trim-left to primer length."
echo "Hits = 0  : Primers are likely gone (or not at the very start)."
echo "-------------------------------------------------------"