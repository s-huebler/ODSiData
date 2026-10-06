# Prompt: Extract tables from a PDF into a formatted Excel workbook

Copy everything below the line into Claude Code, then attach (or give the path to) the PDF you want processed. It works on one PDF at a time. Replace `<PDF_PATH>` and `<OUTPUT_NAME>` if they aren't obvious from context.

---

You are extracting **every table** from a scientific/review PDF into a single, clean `.xlsx` workbook, **one worksheet per table**. Accuracy of the transcribed cell contents matters more than speed. This is a known-hard task: automated table detectors (Camelot, Tabula, GROBID, `pdfplumber.extract_tables()`) routinely mangle these tables because cells wrap onto multiple lines, tables are rotated 90°, tables continue across pages, and footnote/abbreviation blocks sit directly under the grid. **Do not trust automated table detection. Read the tables visually from rendered page images and transcribe them.** That is the method that actually works.

Input PDF: `<PDF_PATH>`
Output workbook: `/path/to/output/<OUTPUT_NAME>_tables.xlsx`

## Environment setup

Use Python with these libraries (install if missing):

```bash
pip install pymupdf pdfplumber openpyxl --break-system-packages
# poppler-utils gives you pdftotext / pdfinfo; install if not present
# (apt-get install -y poppler-utils)  or  (brew install poppler)
```

Build the workbook with **openpyxl** only. Do not use pandas `to_excel` (it strips formatting and mangles multi-line cells).

## Workflow — follow in order

### 1. Inspect the document

```bash
pdfinfo "<PDF_PATH>"            # page count, page size, producer
pdffonts "<PDF_PATH>" | head    # embedded vs. not — hints at scanned/OCR need
```

Or with PyMuPDF:

```python
import fitz
doc = fitz.open("<PDF_PATH>")
print(len(doc), "pages")
print(doc.metadata)             # title, author, doi — you'll reuse these on the Source sheet
```

If pages have almost no extractable text (scanned image PDF), OCR first with `ocrmypdf` and then proceed. Most journal PDFs have real text, so check before assuming.

### 2. Locate the tables

```bash
pdftotext -layout "<PDF_PATH>" /tmp/layout.txt
grep -niE "table [0-9]" /tmp/layout.txt
```

This tells you how many tables exist and roughly which page each starts on. **Watch for `Table N (continued)`** — a single logical table can span 2+ pages and must be merged back into one sheet. Also note the caption text after each `Table N` — you'll use it as the sheet title.

### 3. Render the table pages to images — THIS IS THE SOURCE OF TRUTH

```bash
mkdir -p /tmp/renders
```

```python
import fitz
doc = fitz.open("<PDF_PATH>")
for pageno in [P1, P2, ...]:        # the table pages found in step 2 (0-indexed: page N -> N-1)
    page = doc[pageno]
    pix = page.get_pixmap(dpi=220)  # 200–300 dpi; go higher for dense/rotated tables
    pix.save(f"/tmp/renders/page-{pageno+1:02d}.png")
```

**Open and actually look at each rendered PNG.** The image is authoritative for: column boundaries, row boundaries, which text belongs in which cell, multi-line cells, superscript reference numbers, and rotated layouts. Read the table off the image.

### 4. Cross-check the text layers (don't transcribe blind)

For each table page, pull text three ways and reconcile against what you see in the image:

```bash
pdftotext -f <p> -l <p> -layout "<PDF_PATH>" -   # column-aligned; good for normal tables
pdftotext -f <p> -l <p> -raw    "<PDF_PATH>" -   # one token per line; best for ROTATED tables
```

```python
import pdfplumber
with pdfplumber.open("<PDF_PATH>") as pdf:
    page = pdf.pages[p]                 # 0-indexed
    print(page.extract_text())
    # For a rotated table, crop + rotate the region, or read word boxes with coords:
    for w in page.extract_words():
        pass  # (x0, top, text) lets you reconstruct columns when -layout fails
```

Rules of thumb:
- Normal table → `-layout` usually aligns columns; verify each cell against the image.
- **Rotated table** (90°) → `-layout` produces garbage; use `-raw` (one word per line) plus the image to rebuild rows, or crop the page region in pdfplumber and read word coordinates.
- The text layers are aids; **if text and image disagree, the image wins.**

### 5. Handle the known pitfalls explicitly

- **Multi-line / wrapped cells:** join the wrapped lines into one cell value. Do not create extra rows for visual line wraps. A new row only starts when the *first* (key) column starts a new entry in the image.
- **Continuation tables (`Table N (continued)`):** concatenate the data rows under ONE sheet; use the header only once.
- **Footnotes / abbreviation keys** (e.g., "allo-HCT allogeneic…, FMT fecal…") that appear under the grid: capture them as a single labeled note row beneath the table (e.g., a row whose first cell is `Footnotes / abbreviations` and second cell holds the full text), not as table data.
- **Reference/superscript numbers** in a "Ref." / "Refs." column: keep them as text exactly as printed (e.g., `33,100`, `[30, 90]`, `39–41`). Preserve commas and en-dashes.
- **Dashes:** keep en-dash `–` where the source uses it (number ranges like `328–350`); don't silently convert.
- **Empty cells:** if a cell is genuinely blank in the source, leave it blank — don't fill with the cell above unless the image clearly shows a vertical span.
- **NA / "Not applicable":** transcribe literally.

### 6. Build the workbook (openpyxl)

Represent each table as a Python dict, then write all of them. Use this exact builder (it mirrors a known-good layout: title row, source row, frozen filterable header, wrapped body cells, estimated row heights, plus a Source & Notes sheet).

```python
from math import ceil
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

OUTPUT = "/path/to/output/<OUTPUT_NAME>_tables.xlsx"

META = {
    "title":   "<full article title>",
    "authors": "<authors, semicolon-separated>",
    "journal": "<journal, volume, year, pages>",
    "doi":     "<https://doi.org/...>",
    "pdf":     "<PDF filename>",
}

# One dict per table. `widths` = column widths in Excel units. `rows` = list of rows,
# each row a list aligned to `columns`. Put footnotes in `notes`.
tables = [
    {
        "sheet":   "Table 1 - <short label>",   # <=31 chars, descriptive
        "page":    3,
        "caption": "<exact caption text>",
        "columns": ["Col A", "Col B", "Ref."],
        "widths":  [34, 70, 24],
        "rows": [
            ["cell a1", "cell b1 (wrapped text joined)", "(ref)"],
            # ...
        ],
        "notes": "Footnotes / abbreviations: <verbatim footnote text or ''>",
    },
    # ... more tables
]

# ---- styling ----
HEADER_FILL = PatternFill("solid", fgColor="0F4C81")
HEADER_FONT = Font(bold=True, color="FFFFFF")
TITLE_FILL  = PatternFill("solid", fgColor="EAF2F8")
THIN = Side(style="thin", color="D0D7DE")
BORDER = Border(left=THIN, right=THIN, top=THIN, bottom=THIN)
WRAP_TOP  = Alignment(wrap_text=True, vertical="top")
WRAP_CTR  = Alignment(wrap_text=True, vertical="center")
HDR_ALIGN = Alignment(wrap_text=True, vertical="center", horizontal="center")

def est_row_height(row, widths):
    """Estimate row height so wrapped cells stay visible without overgrowing."""
    max_lines = 1
    for val, w in zip(row, widths):
        s = "" if val is None else str(val)
        width = max(8, int(w * 0.95))
        lines = sum(max(1, ceil(len(part) / width)) for part in s.split("\n"))
        max_lines = max(max_lines, lines)
    return min(160, max(30, 15 * max_lines + 6))

def add_table_sheet(wb, t):
    ws = wb.create_sheet(t["sheet"][:31])
    ncols = len(t["columns"])
    last = get_column_letter(ncols)

    # Row 1: caption (merged)
    ws.merge_cells(f"A1:{last}1")
    c = ws["A1"]; c.value = f'{t["sheet"].split(" - ")[0]}. {t["caption"]}'
    c.fill = TITLE_FILL; c.font = Font(bold=True); c.alignment = WRAP_CTR
    ws.row_dimensions[1].height = 30

    # Row 2: source (merged)
    ws.merge_cells(f"A2:{last}2")
    c = ws["A2"]; c.value = f'Source page: {t["page"]}  |  DOI: {META["doi"]}'
    c.font = Font(color="475569"); c.alignment = WRAP_CTR
    ws.row_dimensions[2].height = 18

    # Row 4: header
    hdr = 4
    for j, name in enumerate(t["columns"], start=1):
        c = ws.cell(row=hdr, column=j, value=name)
        c.fill = HEADER_FILL; c.font = HEADER_FONT; c.alignment = HDR_ALIGN; c.border = BORDER
    ws.row_dimensions[hdr].height = 28

    # Data rows
    r = hdr + 1
    for row in t["rows"]:
        for j, val in enumerate(row, start=1):
            c = ws.cell(row=r, column=j, value=val)
            c.alignment = WRAP_TOP; c.border = BORDER
        ws.row_dimensions[r].height = est_row_height(row, t["widths"])
        r += 1

    # Column widths
    for j, w in enumerate(t["widths"], start=1):
        ws.column_dimensions[get_column_letter(j)].width = w

    # Optional footnote row
    if t.get("notes"):
        ws.merge_cells(f"A{r}:{last}{r}")
        c = ws[f"A{r}"]; c.value = t["notes"]
        c.font = Font(italic=True, color="475569"); c.alignment = WRAP_TOP
        ws.row_dimensions[r].height = est_row_height([t["notes"]], [sum(t["widths"])])

    # Filter + freeze the header row
    ws.auto_filter.ref = f"A{hdr}:{last}{r-1}"
    ws.freeze_panes = f"A{hdr+1}"

def add_source_sheet(wb, tables):
    ws = wb.create_sheet("Source & Notes", 0)
    rows = [
        ["Field", "Value"],
        ["Source title", META["title"]],
        ["Authors", META["authors"]],
        ["Journal", META["journal"]],
        ["DOI", META["doi"]],
        ["PDF filename", META["pdf"]],
        ["Tables extracted", "; ".join(f'{t["sheet"]} (p.{t["page"]})' for t in tables)],
        ["Method", "Tables transcribed from rendered page images; cross-checked against pdftotext -layout/-raw and pdfplumber. Each table on its own sheet."],
    ]
    for i, (k, v) in enumerate(rows, start=1):
        a = ws.cell(row=i, column=1, value=k); b = ws.cell(row=i, column=2, value=v)
        a.alignment = WRAP_TOP; b.alignment = WRAP_TOP
        if i == 1:
            a.fill = b.fill = HEADER_FILL; a.font = b.font = HEADER_FONT
        else:
            a.font = Font(bold=True)
        ws.row_dimensions[i].height = 40
    ws.column_dimensions["A"].width = 20
    ws.column_dimensions["B"].width = 100
    ws.freeze_panes = "A2"

wb = Workbook()
wb.remove(wb.active)               # drop default sheet
for t in tables:
    add_table_sheet(wb, t)
add_source_sheet(wb, tables)
wb.save(OUTPUT)
print("Saved", OUTPUT)
```

### 7. Verify before declaring done (do not skip)

1. **Re-open the saved workbook** and print each sheet's dimensions and first/last rows:
   ```python
   from openpyxl import load_workbook
   wb = load_workbook(OUTPUT)
   for ws in wb:
       print(ws.title, ws.max_row, ws.max_column)
   ```
2. **Count check:** for each table, the number of data rows and columns in the sheet must match the number you counted in the rendered image. If a table looked like it had 7 rows in the image, the sheet must have 7 data rows.
3. **Spot-check transcription:** open the PNG for each table again and compare the first column and the Ref. column cell-by-cell against the sheet. These are where row-merge and wrapping errors hide.
4. **No-empty-where-filled check:** scan for cells that came out blank but shouldn't be (a common symptom of a misaligned column read).
5. **Continuation check:** confirm continued tables were merged into one sheet, not split.
6. If anything is off, fix the `tables` data and rebuild — don't patch the xlsx by hand.

### 8. Deliver

Report: output path, the list of sheets created, and a one-line note of anything uncertain (e.g., "Table 2 was rotated; one footnote partly illegible at 220 dpi — re-rendered at 300"). Keep only the final `.xlsx`; delete intermediate renders/text dumps.

## Summary of why this works

The reliable path is **render → look → transcribe → cross-check text → build → verify against the image**. Automated table extractors fail on wrapped cells, rotation, cross-page continuation, and footnote blocks. Reading the rendered image and transcribing deliberately, with the text layers only as a cross-check, is what produces correct tables.
