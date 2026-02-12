#!/bin/bash

# Define the list of files (supports .fastq, .fq, .gz)
# We use 'ls' to grab them; if none found, we exit.
FILES=$(ls *fastq* *fq* 2>/dev/null)

if [ -z "$FILES" ]; then
    echo "ERROR: No fastq files found. Go to your data folder first."
    exit 1
fi

echo "-------------------------------------------------------"
echo "Scanning ALL files in directory..."
echo "Checking first 1000 reads per file."
printf "%-30s | %-15s | %-10s\n" "Filename" "Primer Found" "Hits"
echo "-------------------------------------------------------"

# Loop through each file found
for FILE in $FILES; do

    # Determine how to read the file (gzip or cat)
    if [[ "$FILE" == *.gz ]]; then
        CAT_CMD="gzip -cd"
    else
        CAT_CMD="cat"
    fi

    # Helper function to check a specific primer for the CURRENT file
    check_primer() {
        NAME=$1
        SEQ=$2
        
        # Regex translation
        REGEX=$(echo "$SEQ" | sed 's/Y/[CT]/g' | sed 's/R/[AG]/g' | sed 's/W/[AT]/g' | sed 's/K/[GT]/g' | sed 's/M/[AC]/g' | sed 's/S/[GC]/g' | sed 's/N/./g' | sed 's/H/[ACT]/g' | sed 's/V/[ACG]/g' | sed 's/D/[AGT]/g' | sed 's/B/[CGT]/g')
        
        # Check first 1000 reads (4000 lines)
        COUNT=$($CAT_CMD "$FILE" | head -n 4000 | grep -E -c "^$REGEX")
        
        # ONLY print if we found hits (keeps the output clean)
        if [ "$COUNT" -gt 0 ]; then
             printf "%-30s | %-15s | %-10s\n" "$FILE" "$NAME" "$COUNT"
        fi
    }

    # --- RUN CHECKS FOR THIS FILE ---
    # 16S V4
    check_primer "515F_V4" "GTGYCAGCMGCCGCGGTAA"
    check_primer "806R_V4" "GGACTACNVGGGTWTCTAAT"
    
    # 16S V3-V4
    check_primer "341F_V3V4" "CCTACGGGNGGCWGCAG"
    check_primer "785R_V3V4" "GACTACHVGGGTATCTAATCC"
    
    # 16S V1-V2
    check_primer "27F_V1V2" "AGAGTTTGATCMTGGCTCAG"

    # ITS
    check_primer "ITS1F" "CTTGGTCATTTAGAGGAAGTAA"
    
    # If you want to see progress for files with 0 hits, uncomment the line below:
    # echo "Finished checking $FILE"
    
done

echo "-------------------------------------------------------"
echo "Done! If the table above is empty, no primers were found."
echo "-------------------------------------------------------"