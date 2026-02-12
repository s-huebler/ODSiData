#!/bin/bash

# 1. FIND A FILE (Looks for .fastq.gz, .fastq, .fq.gz, or .fq)
FILE=$(ls *fastq* *fq* 2>/dev/null | head -n 1)

if [ -z "$FILE" ]; then
    echo "ERROR: No fastq files found. Go to your data folder first."
    exit 1
fi

# 2. CHOOSE THE RIGHT READER
if [[ "$FILE" == *.gz ]]; then
    CAT_CMD="gzip -cd"
else
    CAT_CMD="cat"
fi

echo "-------------------------------------------------------"
echo "Checking file: $FILE"
echo "Scanning first 1000 reads for common primers..."
echo "-------------------------------------------------------"
printf "%-20s | %-10s | %-10s\n" "Primer Name" "Hits" "Region"
echo "-------------------------------------------------------"

# Helper Function
check_primer() {
    NAME=$1
    SEQ=$2
    REGION=$3
    
    # Translate IUPAC to Regex (Y->[CT], R->[AG], W->[AT], N->., etc.)
    REGEX=$(echo "$SEQ" | sed 's/Y/[CT]/g' | sed 's/R/[AG]/g' | sed 's/W/[AT]/g' | sed 's/K/[GT]/g' | sed 's/M/[AC]/g' | sed 's/S/[GC]/g' | sed 's/N/./g' | sed 's/H/[ACT]/g' | sed 's/V/[ACG]/g' | sed 's/D/[AGT]/g' | sed 's/B/[CGT]/g')
    
    # Search start of line (^) in first 4000 lines (1000 reads)
    COUNT=$($CAT_CMD "$FILE" | head -n 4000 | grep -E -c "^$REGEX")
    
    printf "%-20s | %-10s | %-10s\n" "$NAME" "$COUNT" "$REGION"
}

# --- 16S BACTERIA ---
# V4 Region (Most common for microbiome)
check_primer "515F (Parada)"    "GTGYCAGCMGCCGCGGTAA"   "16S V4"
check_primer "515F (Original)"  "GTGCCAGCMGCCGCGGTAA"   "16S V4"
check_primer "806R (Apprill)"   "GGACTACNVGGGTWTCTAAT"  "16S V4"
check_primer "806R (Original)"  "GGACTACHVGGGTWTCTAAT"  "16S V4"

# V3-V4 Region (Longer reads)
check_primer "341F (Klindworth)" "CCTACGGGNGGCWGCAG"    "16S V3-V4"
check_primer "785R (Herlemann)"  "GACTACHVGGGTATCTAATCC" "16S V3-V4"
check_primer "805R"              "GACTACCAGGGTATCTAAT"   "16S V3-V4"

# V1-V2 & V1-V3
check_primer "27F (Agler)"      "AGAGTTTGATCMTGGCTCAG"  "16S V1"
check_primer "338R"             "TGCTGCCTCCCGTAGGAGT"   "16S V2"
check_primer "534R"             "ATTACCGCGGCTGCTGG"     "16S V3"

# --- ITS FUNGI ---
# Common for skin/gut fungi
check_primer "ITS1-F"           "CTTGGTCATTTAGAGGAAGTAA" "Fungi ITS1"
check_primer "ITS2"             "GCTGCGTTCTTCATCGATGC"   "Fungi ITS2"
check_primer "ITS3"             "GCATCGATGAAGAACGCAGC"   "Fungi ITS3"
check_primer "ITS4"             "TCCTCCGCTTATTGATATGC"   "Fungi ITS4"

# --- 18S EUKARYOTES ---
check_primer "Euk_1391f"        "GTACACACCGCCCGTC"       "18S V9"
check_primer "EukBr"            "TGATCCTTCTGCAGGTTCACCTAC" "18S V9"

echo "-------------------------------------------------------"
echo "INTERPRETATION:"
echo "Hits > 0  : The primer is attached. Trim this length."
echo "Hits = 0  : Primer likely removed by sequencing center."
echo "-------------------------------------------------------"