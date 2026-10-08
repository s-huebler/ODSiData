# Mechanism Inventory Extraction Progress

## Step 0: Text extraction
Status: done

## Papers

### Moses_2026
Status: done
Last page done: 11
Next statement_id: MOS_085

### Paredes_2026
Status: done
Last page done: 19
Next statement_id: PAR_246

### Samarkhazan_2025
Status: done
Last page done: 12
Next statement_id: SAM_146

### Weber_2026
Status: done
Last page done: 8
Next statement_id: WEB_135

## Step 2b: Merge
Status: done
Merged rows: 608 mechanism statements across Moses_2026 (84), Paredes_2026 (245), Samarkhazan_2025 (145), Weber_2026 (134)
All statement_ids unique
Output: mechanisms_raw.csv, flags_prompt1.csv

## Prompt 1B: Categorization schemes
Step 3.0: done
Output: mechanisms_categorized.csv (608 rows × 31 cols)
Joined: mechanisms_raw.csv + scheme_A–E + crosswalk_existing; 0 unmatched names
Step 3A: done
Step 3B: done
Step 3C: done
Step 3D: done
Step 3E: done
Step 4: done
Output: categorization_options.md, schemes/scheme_A–E.csv, crosswalk_existing.csv
