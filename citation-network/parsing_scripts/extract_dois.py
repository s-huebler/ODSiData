import os
import re
import pandas as pd

INPUT_PATH = "~/Desktop/Batch2_ToExtractDoi.xlsx"
OUTPUT_PATH = "~/Desktop/Batch2_ExtractedDoi.xlsx"
SHEET_NAME = "Sheet1"

# DOI pattern: matches 10.XXXX/... (no spaces)
DOI_PATTERN = re.compile(r'10\.\d{4,9}/\S+')

# Trailing noise characters to strip (when not mid-DOI digit context)
TRAILING_NOISE = re.compile(r'[.,;)\]]+$')


def clean_doi(raw):
    """Trim trailing punctuation that's sentence/markup noise, not part of the DOI."""
    doi = raw
    # Iteratively strip trailing noise chars that aren't clearly part of the DOI
    while True:
        m = TRAILING_NOISE.search(doi)
        if not m:
            break
        # Keep trailing ) or ] if preceded by a digit (e.g. S2352-3026(15)00028-9)
        tail = doi[m.start():]
        stripped = doi[:m.start()]
        # Check char by char from the right
        new_doi = doi
        for i in range(len(doi) - 1, -1, -1):
            ch = doi[i]
            if ch in '.,;':
                new_doi = doi[:i]
            elif ch in ')]':
                # Keep if preceded by a digit
                if i > 0 and doi[i-1].isdigit():
                    break  # stop stripping here
                else:
                    new_doi = doi[:i]
            else:
                break
        if new_doi == doi:
            break
        doi = new_doi
    return doi


def extract_doi(text):
    """Extract first DOI from text, cleaned of trailing noise."""
    if not isinstance(text, str):
        return None
    m = DOI_PATTERN.search(text)
    if not m:
        return None
    raw = m.group(0)
    doi = clean_doi(raw)
    # Validate
    if re.match(r'^10\.\d{4,9}/\S+$', doi):
        return doi
    return None


def validate_doi(doi):
    """Final validation check."""
    if not doi:
        return True
    return bool(re.match(r'^10\.\d{4,9}/\S+$', doi))


# Load (input is a CSV despite the .xlsx extension)
df = pd.read_csv(os.path.expanduser(INPUT_PATH), dtype=str)
df['local_number'] = pd.to_numeric(df['local_number'], errors='coerce')

# Ensure doi and doi_source columns exist
if 'doi' not in df.columns:
    df['doi'] = ''
if 'doi_source' not in df.columns:
    df['doi_source'] = ''

# Clear existing doi/doi_source so we start fresh
df['doi'] = ''
df['doi_source'] = ''

# Process each citing_paper group
results = []
for citing_paper, group in df.groupby('citing_paper', sort=False):
    group_sorted = group.sort_values('local_number')
    indices = group_sorted.index.tolist()

    # Check local_number 1 and 2 for embedded DOI
    embedded = False
    found_in = None
    for ln in [1, 2]:
        rows = group_sorted[group_sorted['local_number'] == ln]
        if rows.empty:
            continue
        row = rows.iloc[0]
        doi_found = extract_doi(row['full_citation'])
        if doi_found:
            embedded = True
            found_in = int(ln)
            break

    if embedded:
        filled = 0
        blank = 0
        for idx in indices:
            fc = df.at[idx, 'full_citation']
            doi = extract_doi(fc)
            if doi and validate_doi(doi):
                df.at[idx, 'doi'] = doi
                df.at[idx, 'doi_source'] = 'embedded'
                filled += 1
            else:
                df.at[idx, 'doi'] = ''
                df.at[idx, 'doi_source'] = ''
                blank += 1
        status = f"embedded=True (found in local_number={found_in})"
    else:
        filled = 0
        blank = len(indices)
        status = "embedded=False"

    total = len(indices)
    print(f"{citing_paper} ({total} refs): {status} | filled={filled}, blank={blank}")
    results.append({
        'citing_paper': citing_paper,
        'total': total,
        'embedded': embedded,
        'filled': filled,
        'blank': blank,
    })

# Spot-check a few
print("\n--- Spot-check sample DOIs ---")
sample = df[df['doi'] != ''].sample(min(10, (df['doi'] != '').sum()), random_state=42)
for _, row in sample.iterrows():
    print(f"  doi={row['doi']}")
    print(f"    from: {str(row['full_citation'])[:120]}")

# Validate all
invalid = df[(df['doi'] != '') & (~df['doi'].apply(validate_doi))]
if not invalid.empty:
    print(f"\nWARNING: {len(invalid)} DOIs failed validation!")
    print(invalid[['citing_paper', 'local_number', 'doi']].to_string())
else:
    print(f"\nAll {(df['doi'] != '').sum()} extracted DOIs pass validation.")

# Write output
df.to_excel(os.path.expanduser(OUTPUT_PATH), sheet_name=SHEET_NAME, index=False)
print(f"\nOutput written to {OUTPUT_PATH}")

# Summary
print("\n=== Final Summary ===")
total_refs = sum(r['total'] for r in results)
total_filled = sum(r['filled'] for r in results)
total_blank = sum(r['blank'] for r in results)
embedded_groups = sum(1 for r in results if r['embedded'])
not_embedded_groups = sum(1 for r in results if not r['embedded'])
print(f"Groups: {len(results)} total | {embedded_groups} embedded=True | {not_embedded_groups} embedded=False")
print(f"Rows:   {total_refs} total | {total_filled} filled | {total_blank} blank")
