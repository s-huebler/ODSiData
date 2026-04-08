#!/bin/bash

# Configuration
PROJECT_ACCESSION="ERP017899"
REPORT_FILE="ena_report.tsv"
PLAN_FILE="download_plan.txt"
COMPLETED_LOG="completed_runs.txt"
FAILED_LOG="failed_downloads.txt"

MAX_RETRIES=3
RETRY_DELAY=60

# Create the completed log if it doesn't exist
touch "$COMPLETED_LOG"

echo "========================================"
echo "Step 1: Fetching ENA Project Metadata"
echo "========================================"

if [[ ! -f "$REPORT_FILE" ]]; then
    curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${PROJECT_ACCESSION}&result=read_run&fields=study_accession,sample_accession,run_accession,fastq_ftp&format=tsv" > "$REPORT_FILE"
    echo "Metadata saved to $REPORT_FILE"
else
    echo "Metadata $REPORT_FILE already exists. Skipping API call."
fi

echo "========================================"
echo "Step 2: Generating Download Plan"
echo "========================================"

# This block finds the correct columns, sorts by sample then run, 
# and assigns _1 to the lower run accession and _2 to the higher run accession.
awk -F'\t' '
NR==1 {
    for(i=1; i<=NF; i++) {
        if($i=="run_accession") r=i;
        if($i=="sample_accession") s=i;
        if($i=="fastq_ftp") f=i;
    }
}
NR>1 {
    # Print sample, run, and ftp for sorting
    if(r && s && f) print $s "\t" $r "\t" $f
}' "$REPORT_FILE" | sort -k1,1 -k2,2 | awk -F'\t' '
{
    # If the sample accession is the same as the previous row, it is the reverse read (2)
    if ($1 == prev_sample) {
        read_num = 2
    } else {
    # If it is a new sample accession, it is the forward read (1)
        read_num = 1
        prev_sample = $1
    }
    # Output format: run_accession target_filename fastq_ftp
    print $2 "\t" $1 "_" read_num ".fastq\t" $3
}' > "$PLAN_FILE"

echo "Plan generated and saved to $PLAN_FILE."

echo "========================================"
echo "Step 3: Processing Runs from Plan"
echo "========================================"

# Read the generated plan line by line
while read -r run_accession target_filename fastq_ftp; do
    
    # Skip empty lines
    [[ -z "$run_accession" || -z "$fastq_ftp" ]] && continue
    
    # ENA sometimes provides multiple ftp links separated by a semicolon; grab the first one
    ftp_link=$(echo "$fastq_ftp" | cut -d ';' -f 1)
    
    # Ensure link starts with ftp://
    if [[ "$ftp_link" != ftp://* ]]; then
        ftp_link="ftp://$ftp_link"
    fi

    echo "----------------------------------------"
    echo "Starting: $run_accession -> Target: $target_filename"
    
    # --- THE CHECKPOINT ---
    if grep -q "^${run_accession}$" "$COMPLETED_LOG"; then
        echo "Success: $run_accession already processed. Skipping..."
        continue
    fi

    # --- THE RETRY LOOP ---
    attempt=1
    success=0

    while [[ $attempt -le $MAX_RETRIES ]]; do
        echo "Attempt $attempt of $MAX_RETRIES for $run_accession..."

        # Download the gzipped file
        if wget -c -q --show-progress -O "${run_accession}.fastq.gz" "$ftp_link"; then
            echo "Download successful. Extracting and renaming to $target_filename..."
            
            # gunzip -c extracts the contents to standard output, which we redirect (>) to the target filename.
            # Then we remove the original .gz file to save space.
            if gunzip -c "${run_accession}.fastq.gz" > "$target_filename"; then
                rm "${run_accession}.fastq.gz"
                echo "$run_accession" >> "$COMPLETED_LOG"
                success=1
                break
            else
                echo "Extraction failed for ${run_accession}.fastq.gz"
            fi
        else
            echo "wget failed to download $run_accession."
        fi

        if [[ $attempt -lt $MAX_RETRIES ]]; then
            echo "Waiting $RETRY_DELAY seconds before trying again..."
            sleep $RETRY_DELAY
        fi
        
        ((attempt++))
    done

    if [[ $success -eq 0 ]]; then
        echo "ERROR: $run_accession failed after $MAX_RETRIES attempts. Logging to $FAILED_LOG"
        echo "$run_accession -> $target_filename (Download/Extraction Failed)" >> "$FAILED_LOG"
    fi

done < "$PLAN_FILE"

echo "========================================"
echo "All done! Ready for manifest creation."
echo "========================================"