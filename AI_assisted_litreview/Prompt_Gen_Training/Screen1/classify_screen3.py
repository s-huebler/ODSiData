import csv
import openpyxl
from openpyxl.styles import Alignment

INPUT  = "Prompt_Gen_Training/Screen3.csv"
OUTPUT = "Prompt_Gen_Training/Screen3_classified.xlsx"

# Manual classifications — 12 papers
classifications = [
    # Row 1: FMT for intestinal steroid-resistant GvHD
    (
        "Include",
        "All three dimensions satisfied: allo-HSCT cohort, gut microbiome (FMT intervention, intestinal "
        "microflora as mechanism), and steroid-resistant intestinal aGVHD as the primary outcome."
    ),
    # Row 2: Gut colonization by antibiotic-resistant bacteria and allo-SCT outcomes
    (
        "Include",
        "All three dimensions satisfied: allo-SCT cohort, gut microbiome (gut colonization by named "
        "antibiotic-resistant taxa, framed in gut microbiota immunomodulatory context), and grades II-IV "
        "acute GVHD as an explicitly reported outcome."
    ),
    # Row 3: Circulating microbial cell-free DNA after allo-HCT
    (
        "Discard",
        "Cohort (allo-HCT) and gut microbiome (16S stool sequencing, named taxa) satisfied, but outcome "
        "dimension is insufficient: GVHD is never named; the study characterizes mcfDNA as a biomarker "
        "of 'immunologic complications' without specifying GVHD or other qualifying allo-SCT outcomes."
    ),
    # Row 4: Ocular GVHD biomarkers systematic review
    (
        "Discard",
        "Cohort (allo-HSCT with ocular GVHD) and GVHD outcome satisfied, but gut microbiome dimension "
        "is not satisfied: only ocular surface microbiota is examined; the gut microbiome is not "
        "mentioned."
    ),
    # Row 5: Pulmonary complications in allo-HCT (review)
    (
        "Discard",
        "Cohort (allo-HCT) satisfied, but gut microbiome dimension is not satisfied: the review covers "
        "lung complications and respiratory diagnostics (mNGS on BAL); gut microbiome is not mentioned."
    ),
    # Row 6: Inflammatory markers and microbiome dysbiosis in lung cGVHD (BOS)
    (
        "Include",
        "All three dimensions satisfied: allo-HCT cohort, gut microbiome explicitly sequenced and "
        "analyzed for diversity (qualifying signal even though results were minimal), and cGVHD/BOS as "
        "the primary outcome."
    ),
    # Row 7: hAMSCs prevent aGVHD in intestinal microbiome-dependent manner (mouse)
    (
        "Discard",
        "Gut microbiome (16S sequencing, SCFAs) and aGVHD outcome satisfied, but cohort dimension is "
        "not satisfied: the study uses humanized mouse models, not human patients undergoing allo-SCT."
    ),
    # Row 8: hAMSCs alleviate aGVHD via gut microbiota interactions (mouse)
    (
        "Discard",
        "Gut microbiome (diversity/composition) and aGVHD outcome satisfied, but cohort dimension is "
        "not satisfied: the study uses humanized aGVHD mouse models, not human patients undergoing "
        "allo-HSCT."
    ),
    # Row 9: Precision microbiome reconstitution and C. difficile resistance
    (
        "Discard",
        "Gut microbiome (bile acids, named taxa) is substantive, but cohort dimension (no allo-SCT "
        "patients) and outcome dimension (C. difficile infection, not GVHD) are both not satisfied."
    ),
    # Row 10: Adverse antibiotic effects in pediatric febrile neutropenia
    (
        "Discard",
        "Cohort (partially: HSCT patients mentioned alongside cancer patients) and gut microbiome "
        "(disturbance discussed substantively) are partially satisfied, but outcome dimension is not "
        "satisfied: GVHD is not mentioned; outcomes are antibiotic adverse effects and febrile "
        "neutropenia."
    ),
    # Row 11: Cutaneous dysbiosis post-allo-HSCT
    (
        "Discard",
        "Cohort (allo-HSCT) satisfied, but gut microbiome dimension is not satisfied: the study "
        "examines only the cutaneous microbiome by shotgun metagenomics; gut dysbiosis appears only "
        "as introductory background citing prior literature, not as an observed finding in this study."
    ),
    # Row 12: Role of microbiota in allo-HSCT (review)
    (
        "Include",
        "All three dimensions satisfied: allo-HSCT cohort, gut/intestinal microbiota as the substantive "
        "mechanistic focus (metabolites, immune crosstalk, dysbiosis), and acute GVHD as the primary "
        "outcome reviewed."
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
