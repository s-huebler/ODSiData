import csv
import openpyxl

INPUT  = "Prompt_Gen_Training/Screen2.csv"
OUTPUT = "Prompt_Gen_Training/Screen2_classified.xlsx"

# Manual classifications derived from careful reading of each title/abstract
classifications = [
    # (Decision, Reasoning)
    # Row 1: skin recolonization
    (
        "Discard",
        "Cohort (allo-HSCT) and GVHD outcome satisfied, but gut microbiome dimension is insufficient: "
        "the substantive focus is the skin microbiome; intestinal dysbiosis is confirmed only as a "
        "secondary reference point, not as a study exposure."
    ),
    # Row 2: FK506 + Lactobacillus acidophilus
    (
        "Include",
        "All three dimensions satisfied: allo-HSCT cohort, gut microbiome (Lactobacillus probiotic "
        "intervention targeting the intestinal microbiome), and aGVHD as the primary outcome."
    ),
    # Row 3: nutritional intake
    (
        "Discard",
        "Cohort (allo-HCT) and GVHD outcome satisfied, but gut microbiome dimension is insufficient: "
        "the study examines enteral vs parenteral nutrition routes; 'gut microflora' appears only once "
        "as a speculative mechanism, not as a measured exposure."
    ),
    # Row 4: computational text mining (oral + gut microbiome)
    (
        "Include",
        "All three dimensions satisfied: allo-HSCT cohort, gut microbiome (Shannon diversity, gut taxa, "
        "microbial metabolic pathways), and aGVHD as the primary outcome; oral microbiome is co-studied "
        "but gut microbiome is a substantive focus."
    ),
    # Row 5: same paper, empty abstract
    (
        "Include",
        "Abstract absent; title clearly aligns with all three dimensions (allo-SCT cohort, oral and gut "
        "microbiome, aGVHD outcome); included on title alone per first-pass lean-Include rule."
    ),
    # Row 6: gut decontamination in children
    (
        "Include",
        "All three dimensions satisfied: pediatric allo-HSCT cohort, gut microbiota measured by 16S rRNA "
        "sequencing (primary focus), and GVHD/bloodstream infections as motivating clinical outcomes; "
        "gut microbiome is the substantive study subject."
    ),
    # Row 7: bone marrow transplantation (old review/perspective)
    (
        "Discard",
        "Cohort (allo-BMT) and GVHD outcome present, but gut microbiome dimension is insufficient: "
        "intestinal microflora is mentioned only as a future research direction and a brief speculative "
        "comment, not as a measured or substantive mechanistic focus."
    ),
    # Row 8: MAIT cells
    (
        "Include",
        "All three dimensions satisfied: allo-HCT cohort, gut microbiome (GI abundance of Blautia spp. "
        "explicitly quantified and associated with MAIT reconstitution), and GVHD risk as the outcome; "
        "gut microbiome is examined as a substantive correlate."
    ),
    # Row 9: early gut microbiota signature (pediatric)
    (
        "Include",
        "All three dimensions satisfied: pediatric allo-HSCT cohort, gut microbiota profiled by 16S rRNA "
        "sequencing (Blautia, Fusobacterium, diversity metrics), and aGVHD as the primary outcome."
    ),
    # Row 10: gut microbiota trajectory (pediatric)
    (
        "Include",
        "All three dimensions satisfied: pediatric allo-HSCT cohort, gut microbiota trajectory and "
        "short-chain fatty acid profiles as primary exposure, and aGVHD as the primary outcome."
    ),
]

# Read CSV
rows = []
with open(INPUT, newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        rows.append(row)

assert len(rows) == len(classifications), (
    f"Row count mismatch: CSV has {len(rows)}, classifications has {len(classifications)}"
)

# Build workbook
wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Classified"

headers = ["Title", "Abstract", "Decision", "Reasoning"]
ws.append(headers)

for row, (decision, reasoning) in zip(rows, classifications):
    ws.append([row["Title"], row["Abstract"], decision, reasoning])

# Basic column widths for readability
ws.column_dimensions["A"].width = 50
ws.column_dimensions["B"].width = 80
ws.column_dimensions["C"].width = 12
ws.column_dimensions["D"].width = 80

# Wrap text in all data cells
from openpyxl.styles import Alignment
for data_row in ws.iter_rows(min_row=2):
    for cell in data_row:
        cell.alignment = Alignment(wrap_text=True, vertical="top")

wb.save(OUTPUT)

# Summary
include_n = sum(1 for d, _ in classifications if d == "Include")
discard_n = sum(1 for d, _ in classifications if d == "Discard")
print(f"Saved: {OUTPUT}")
print(f"Include: {include_n}")
print(f"Discard: {discard_n}")
print(f"Total:   {include_n + discard_n}")
