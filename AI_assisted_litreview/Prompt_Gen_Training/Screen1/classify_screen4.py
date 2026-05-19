import csv
import openpyxl
from openpyxl.styles import Alignment

INPUT  = "Prompt_Gen_Training/Screen4.csv"
OUTPUT = "Prompt_Gen_Training/Screen4_classified.xlsx"

# Manual classifications — 10 papers
classifications = [
    # Row 1: TMAVA modulates CNS-aGVHD
    (
        "Include",
        "All three dimensions satisfied: allo-HCT cohort (mouse model plus patient blood data), gut "
        "microbiota-derived metabolite TMAVA as substantive mechanistic exposure, and CNS-aGVHD as "
        "the primary outcome."
    ),
    # Row 2: Role of intestinal microbiota in aGVHD (review)
    (
        "Include",
        "All three dimensions satisfied: allo-HSCT cohort, intestinal microbiota and probiotic "
        "interventions as substantive focus, and aGVHD as the primary outcome reviewed."
    ),
    # Row 3: Microbial diversity and GI GVHD post-allo-HSCT
    (
        "Include",
        "All three dimensions satisfied: allo-HSCT cohort, gut microbial diversity measured by 16S rRNA "
        "sequencing on fecal samples, and GI GVHD as the primary outcome."
    ),
    # Row 4: Cell-free DNA profiling informs HCT complications
    (
        "Discard",
        "Cohort (allo-HCT) and GVHD outcome satisfied, but gut microbiome dimension is not satisfied: "
        "the study profiles plasma cell-free DNA (cfDNA) for detecting GVHD, infection, and relapse; "
        "the gut microbiome itself is not examined as an exposure."
    ),
    # Row 5: Targeting the gut microbiome in HSCT (review)
    (
        "Include",
        "All three dimensions satisfied: HSCT cohort, gut microbiome (microbial diversity, FMT, "
        "probiotics, prebiotics) as substantive focus, and GvHD and mortality as primary outcomes."
    ),
    # Row 6: Same title as Row 5, no abstract
    (
        "Include",
        "Abstract absent; title clearly aligns with all three dimensions (HSCT cohort, gut microbiome "
        "as stated focus, GVHD-related outcomes implied); included on title alone per lean-Include rule."
    ),
    # Row 7: Potential novel biomarkers in cGVHD (review)
    (
        "Include",
        "All three dimensions satisfied: allo-HSCT cohort, microbiome given a substantive "
        "pathophysiological role in cGVHD with bacterial strains and metabolites as candidate biomarkers, "
        "and cGVHD as the primary outcome; lean-Include applied given first-pass context."
    ),
    # Row 8: Lipocalin-2 neutrophil population in intestinal aGVHD
    (
        "Discard",
        "Cohort (allo-HCT) and aGVHD outcome satisfied, but gut microbiome dimension is insufficient: "
        "microbiome alterations appear only as a secondary consequence of LCN2 manipulation; the "
        "substantive focus is LCN2-expressing neutrophils and macrophage signaling, not the gut "
        "microbiome."
    ),
    # Row 9: Gut resistome in pediatric allo-HSCT
    (
        "Include",
        "All three dimensions satisfied: pediatric allo-HSCT cohort, gut microbiome examined by shotgun "
        "metagenomics (resistome = antibiotic resistance genes in gut microbiota), and aGVHD as a "
        "primary comparator outcome."
    ),
    # Row 10: Clinical effects of gut microbiome in hematologic malignancies (review)
    (
        "Include",
        "All three dimensions satisfied: allo-SCT cohort explicitly discussed, gut microbiome is the "
        "substantive focus (biomarker role, microbiota manipulation), and allo-SCT clinical outcomes "
        "are a primary domain; broader hematologic malignancy scope does not exclude this."
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

ws.append(["Title", "Abstract", "Decision", "Reasoning"])

for row, (decision, reasoning) in zip(rows, classifications):
    ws.append([row["Title"], row["Abstract"], decision, reasoning])

ws.column_dimensions["A"].width = 50
ws.column_dimensions["B"].width = 80
ws.column_dimensions["C"].width = 12
ws.column_dimensions["D"].width = 80

for data_row in ws.iter_rows(min_row=2):
    for cell in data_row:
        cell.alignment = Alignment(wrap_text=True, vertical="top")

wb.save(OUTPUT)

include_n = sum(1 for d, _ in classifications if d == "Include")
discard_n = sum(1 for d, _ in classifications if d == "Discard")
print(f"Saved: {OUTPUT}")
print(f"Include: {include_n}")
print(f"Discard: {discard_n}")
print(f"Total:   {include_n + discard_n}")
