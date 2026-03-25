#!/bin/zsh


#  Activate the conda environment
source ~/miniconda3-x86_64/etc/profile.d/conda.sh
conda activate sra-env

# Retry variables 
MAX_RETRIES=3
RETRY_DELAY=60 # Wait 60 seconds before trying again

#  Read the accessions file line-by-line
while IFS= read -r srr; do
    [[ -z "$srr" ]] && continue
    
    echo "========================================"
    echo "Starting processing for: $srr"
    echo "========================================"

# --- THE CHECKPOINT ---
    if [[ -f "${srr}.fastq" ]] || [[ -f "${srr}_1.fastq" ]]; then
        echo "Success: FASTQ files for $srr already exist. Skipping..."
        continue
    fi

    # --- THE RETRY LOOP ---
    attempt=1
    success=0

    while [[ $attempt -le $MAX_RETRIES ]]; do
        echo "Attempt $attempt of $MAX_RETRIES for $srr..."

        # 1. Download
        if prefetch "$srr" --output-directory .; then
            echo "Download successful. Extracting FASTQ..."
            
            # 2. Extract
            if fasterq-dump --split-files --progress "$srr"; then
                
                # 3. Cleanup (Deletes the raw .sra folder to save space)
                echo "Extraction successful. Cleaning up raw SRA file..."
                rm -rf "$srr" 
                
                success=1
                break # Break out of retry loop 
            else
                echo "fasterq-dump failed for $srr."
            fi
        else
            echo "prefetch failed to download $srr."
        fi

        # Pause before trying again if it failed
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            echo "Waiting $RETRY_DELAY seconds before trying again..."
            sleep $RETRY_DELAY
        fi
        
        ((attempt++))
    done

    # Log failures
    if [[ $success -eq 0 ]]; then
        echo "ERROR: $srr failed after $MAX_RETRIES attempts. Logging to failed_downloads.txt"
        echo "$srr" >> failed_downloads.txt
    fi

done < run_accessions.txt

# Deactivate
conda deactivate
echo "All done!"