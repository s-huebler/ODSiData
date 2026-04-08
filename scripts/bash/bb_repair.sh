#!/bin/bash

# ==============================================================================
# Script Name: run_bbmap_repair.sh
# Description: Cleans ENA-corrupted FASTQ headers and uses BBTools repair.sh 
#              to re-synchronize paired-end FASTQ files.
# ==============================================================================

echo "Creating 'synced_reads' directory..."
mkdir -p synced_reads

# Loop through all forward reads
for f in *_1.fastq; do
    
    if [ ! -f "$f" ]; then
        echo "No files matching *_1.fastq found. Exiting."
        exit 1
    fi

    r="${f/_1.fastq/_2.fastq}"
    base="${f/_1.fastq/}"
    
    if [ ! -f "$r" ]; then
        echo "Warning: Reverse read $r not found for $f. Skipping $base."
        continue
    fi

    echo "--------------------------------------------------"
    echo "1. Cleaning ENA headers for $base..."
    
    # FORWARD READ: Strip the @ERRXXXXXX.X prefix, leaving the original @10564.../1 header
    sed -E 's/^@ERR[0-9]+\.[0-9]+ /@/' "$f" > temp_1.fastq
    
    # REVERSE READ: Strip the @ERRXXXXXX.X prefix AND change the trailing /1 to /2
    sed -E 's/^@ERR[0-9]+\.[0-9]+ (.*)\/1$/@\1\/2/' "$r" > temp_2.fastq

    echo "2. Repairing read pairs for $base..."
    
    # Run BBMap's repair tool on the cleaned temporary files
    repair.sh in=temp_1.fastq in2=temp_2.fastq \
              out="synced_reads/${base}_1.fastq" \
              out2="synced_reads/${base}_2.fastq" \
              outs="synced_reads/${base}_orphans.fastq" \
              repair
              
    # Clean up the temporary files to save hard drive space
    rm temp_1.fastq temp_2.fastq
              
done

echo "--------------------------------------------------"
echo "All files cleaned and synced! You can find them in 'synced_reads'."