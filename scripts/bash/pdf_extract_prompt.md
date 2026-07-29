# Prompt: Extract tables AND references from one journal PDF into a single Excel workbook

You are processing **exactly one** scientific/review PDF and writing **one** `.xlsx` workbook
that contains every table (one worksheet each), a `References` sheet, and a `Source & Notes`
sheet. Accuracy of transcribed content matters more than speed. **Never invent data** — if you
cannot find or verify something, leave it blank.

The harness supplies these three values in the message; use them verbatim:

- `INPUT_PDF`  — absolute path to the PDF to process
- `OUTPUT_XLSX` — absolute path to write (named `<Lastname_Year>_tables.xlsx`)
- `NAME_YEAR`  — short label, e.g. `Hsu_2026` (use for the references sheet title)

Process only this PDF, then stop. Do not produce intermediate logs, decision files, or progress
notes — the only deliverable is `OUTPUT_XLSX`. Delete any temporary renders/text dumps before you
finish.

---

## 0. Setup and shared inspection (do once, reuse for both tables and references)

```bash
pip install pymupdf pdfplumber openpyxl requests rapidfuzz --break-system-packages
# system poppler-utils provides pdftotext / pdftohtml / pdfinfo / pdffonts
```

Open the PDF **once** and reuse this across both halves of the task:

```python
import fitz
doc = fitz.open(INPUT_PDF)
print(len(doc), "pages"); print(doc.metadata)   # title, author, doi → reused on Source sheet
```

Capture metadata now: `title`, `authors`, `journal/year`, `doi`, `pdf` filename. If pages have
almost no extractable text (scanned image PDF), OCR first with `ocrmypdf`, then proceed. Build the
workbook with **openpyxl only** — never pandas `to_excel` (it mangles multi-line cells).

Locate structure in one pass:

```bash
pdftotext -layout "INPUT_PDF" /tmp/layout.txt
grep -niE "table [0-9]" /tmp/layout.txt              # table count + start pages
grep -n -iE "^(references|bibliography)\b" /tmp/layout.txt | tail   # references heading/page
```

---

## PART A — Tables (render → look → transcribe → cross-check → verify)

Automated table detectors (Camelot, Tabula, GROBID, `pdfplumber.extract_tables()`) routinely
mangle these tables: cells wrap onto multiple lines, tables rotate 90°, tables continue across
pages, and footnote/abbreviation blocks sit under the grid. **Do not trust automated detection.
Read tables visually from rendered page images and transcribe them.**

1. **Render the table pages** (the source of truth) at 220 dpi (higher for dense/rotated):
   ```python
   for pageno in TABLE_PAGES:                 # 0-indexed: printed page N -> N-1
       doc[pageno].get_pixmap(dpi=220).save(f"/tmp/renders/page-{pageno+1:02d}.png")
   ```
   **Open and actually look at each PNG.** The image is authoritative for column/row boundaries,
   cell membership, multi-line cells, superscript refs, and rotation.

2. **Cross-check the text layers** — `pdftotext -f <p> -l <p> -layout` (normal tables),
   `pdftotext ... -raw` (rotated tables: one token per line), or `pdfplumber` word boxes
   `(x0, top, text)` to rebuild columns. **If text and image disagree, the image wins.**

3. **Known pitfalls:** join wrapped lines into one cell (a new row only starts when the first/key
   column starts a new entry); merge `Table N (continued)` into ONE sheet with the header used
   once; capture footnote/abbreviation blocks as a single labeled note row beneath the table, not
   as data; preserve Ref./superscript numbers exactly as printed (`33,100`, `[30, 90]`, `39–41`),
   keeping commas and en-dashes; leave genuinely blank cells blank; transcribe `NA`/`Not
   applicable` literally.

Represent each table as a dict (`sheet`, `page`, `caption`, `columns`, `widths`, `rows`, `notes`)
and build with the styling helper in PART C.

---

## PART B — References (detect family → extract → clean → DOIs → validate)

Flat `pdftotext` scrambles two-column reference lists (interleaved columns, running
headers/footers, author-bio blocks, numbers split from bodies). **Do not parse references from
flat `pdftotext`.** Don't use GROBID. Detect the family first, then use the matching extractor.

**Detect family:**

```bash
pdftohtml -xml -i -stdout "INPUT_PDF" | grep -c "sbref"          # >0 → Elsevier (Extractor A)
pdftotext -layout "INPUT_PDF" | sed -n '/^[Rr]eferences/,+12p'   # starts "1." → numbered (B)
```
Count embedded `doi.org` links via PyMuPDF `page.get_links()`; ≈one per ref (common MDPI) → DOIs
are in the PDF (DOI strategy 1).

**Extractors** (each yields an ordered list of `(number, raw_lines)`):
- **A — Elsevier `sbref` anchors:** `pdftohtml -xml -i -f <F> -l <L>`; group `<text>` fragments by
  shared `sbrefN` id; order within a group by `(page, top, left)` ±3 px. Recover unanchored leader
  entries with geometry (Extractor C) and place them in reading order before `sbref1`.
- **B — Numbered (MDPI/Vancouver/APA):** B1 `pdftotext -layout`, split on
  `(?m)^\s*(\d{1,3})\.\s+` (require whitespace after the period so `917.e1–917.e12` doesn't split).
  B2 (messy columns, e.g. JTM) PyMuPDF `get_text("blocks")`, drop `y0<90`/`y0>760` margins, sort
  left column (`x<300`) then right, then split as B1. Filter mid-column running headers and bare
  page numbers; stop at the author-bio block. **Assert numbers form a contiguous `1..N`.**
- **C — Coordinate-only fallback:** `pdftohtml -xml` fragments, per-page column boxes, group lines
  by `top` (±3 px), new ref when `left` is at column start (±8 px); reach the footer but exclude it.

**Clean each `full_citation`:** if a line ends with `-` and the next starts lowercase, join with no
space (de-hyphenate); else single space. Collapse whitespace; strip spaces before punctuation.
NFC-normalize to repair split accents (`Daill\`ere`→`Daillère`, `Lazarevi´c`→`Lazarević`). Keep
otherwise verbatim. MDPI `[CrossRef]`/`[PubMed]` tags: keep or strip, but be consistent.

**`abbreviated_citation`:** `year` = first `\b(19|20)\d{2}\b`. `Surname1_year` (one author or et
al.); `Surname1&Surname2_year` (exactly two authors, no et al.). Handle Elsevier/MDPI (`,`/`;`),
Vancouver (`Torfi E, Bahreiny SS, et al.`), APA, and institutional leaders (first word). Keep
multiword surnames joined (`Burgos da Silva`→`BurgosdaSilva`).

**DOIs — embedded links first, then Crossref:**
- Strategy 1: map `page.get_links()` `10.\d{4,9}/...` URIs to refs by `(page, column, y0)` reading
  order; a ref overlapping a link's rect owns that DOI.
- Strategy 2 (fallback): Crossref `query.bibliographic`, retry on 429/5xx with backoff, polite
  `User-Agent` (mailto:sophhuebler@gmail.com). Accept only when confident: title
  `fuzz.token_set_ratio` ≥ ~88 AND (year ±1 AND first-author surname present), or title ≥ ~95
  alone. Else leave blank. Sleep 0.3–1.0 s between calls. Book chapters / registry / some preprints
  legitimately have no DOI — blank is correct.

**Validate (do not skip):** contiguous numbering `1..N`; N matches max printed ref number; every
ref has a year and the abbreviation ends with it; no header/footer/bio fragments; no truncated
refs (spot-check last ref per column and page-spanning refs); every DOI matches `^10\.\d{4,9}/\S+$`;
spot-check 3–5 DOIs by resolving `https://doi.org/<doi>` (HEAD, follow redirects).

References sheet columns (header row 1, data from row 2): `number`, `full_citation`,
`abbreviated_citation`, `doi`, `doi_source_url`.

---

## PART C — Build the single workbook (openpyxl)

One workbook, sheet order: `Source & Notes` (index 0), then one sheet per table, then `References`.

```python
from math import ceil
from openpyxl import Workbook, load_workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

META = {"title": "...", "authors": "...", "journal": "...", "doi": "...", "pdf": "..."}
tables = [ {"sheet": "Table 1 - short label", "page": 3, "caption": "...",
            "columns": ["Col A","Col B","Ref."], "widths": [34,70,24],
            "rows": [["a1","b1 (wrapped joined)","(ref)"]], "notes": "Footnotes: ..."} ]
references = [ (1, "full citation", "Surname_Year", "10.xxxx/yyy"), ]  # (num, full, abbrev, doi)

HEADER_FILL = PatternFill("solid", fgColor="0F4C81"); HEADER_FONT = Font(bold=True, color="FFFFFF")
TITLE_FILL  = PatternFill("solid", fgColor="EAF2F8")
THIN = Side(style="thin", color="D0D7DE"); BORDER = Border(left=THIN,right=THIN,top=THIN,bottom=THIN)
WRAP_TOP = Alignment(wrap_text=True, vertical="top"); WRAP_CTR = Alignment(wrap_text=True, vertical="center")
HDR_ALIGN = Alignment(wrap_text=True, vertical="center", horizontal="center")

def est_row_height(row, widths):
    mx = 1
    for val, w in zip(row, widths):
        s = "" if val is None else str(val); width = max(8, int(w*0.95))
        lines = sum(max(1, ceil(len(p)/width)) for p in s.split("\n")); mx = max(mx, lines)
    return min(160, max(30, 15*mx + 6))

def add_table_sheet(wb, t):
    ws = wb.create_sheet(t["sheet"][:31]); ncols = len(t["columns"]); last = get_column_letter(ncols)
    ws.merge_cells(f"A1:{last}1"); c = ws["A1"]
    c.value = f'{t["sheet"].split(" - ")[0]}. {t["caption"]}'; c.fill = TITLE_FILL; c.font = Font(bold=True); c.alignment = WRAP_CTR
    ws.row_dimensions[1].height = 30
    ws.merge_cells(f"A2:{last}2"); c = ws["A2"]
    c.value = f'Source page: {t["page"]}  |  DOI: {META["doi"]}'; c.font = Font(color="475569"); c.alignment = WRAP_CTR
    hdr = 4
    for j, name in enumerate(t["columns"], 1):
        c = ws.cell(hdr, j, name); c.fill = HEADER_FILL; c.font = HEADER_FONT; c.alignment = HDR_ALIGN; c.border = BORDER
    ws.row_dimensions[hdr].height = 28
    r = hdr + 1
    for row in t["rows"]:
        for j, val in enumerate(row, 1):
            c = ws.cell(r, j, val); c.alignment = WRAP_TOP; c.border = BORDER
        ws.row_dimensions[r].height = est_row_height(row, t["widths"]); r += 1
    for j, w in enumerate(t["widths"], 1): ws.column_dimensions[get_column_letter(j)].width = w
    if t.get("notes"):
        ws.merge_cells(f"A{r}:{last}{r}"); c = ws[f"A{r}"]
        c.value = t["notes"]; c.font = Font(italic=True, color="475569"); c.alignment = WRAP_TOP
    ws.auto_filter.ref = f"A{hdr}:{last}{r-1}"; ws.freeze_panes = f"A{hdr+1}"

def add_refs_sheet(wb, refs):
    ws = wb.create_sheet(f"References")
    cols = ["number","full_citation","abbreviated_citation","doi","doi_source_url"]; widths=[8,105,28,42,45]
    for j,name in enumerate(cols,1):
        c = ws.cell(1,j,name); c.fill=HEADER_FILL; c.font=HEADER_FONT; c.alignment=HDR_ALIGN
    for i,(n,full,abbrev,doi) in enumerate(refs, start=2):
        vals=[n, full, abbrev, doi, f"https://doi.org/{doi}" if doi else ""]
        for j,v in enumerate(vals,1):
            c=ws.cell(i,j,v); c.alignment=WRAP_TOP
    for j,w in enumerate(widths,1): ws.column_dimensions[get_column_letter(j)].width=w
    ws.freeze_panes="A2"

def add_source_sheet(wb, tables, refs):
    ws = wb.create_sheet("Source & Notes", 0)
    rows = [["Field","Value"], ["Source title",META["title"]], ["Authors",META["authors"]],
            ["Journal",META["journal"]], ["DOI",META["doi"]], ["PDF filename",META["pdf"]],
            ["Tables extracted","; ".join(f'{t["sheet"]} (p.{t["page"]})' for t in tables)],
            ["References extracted", str(len(refs))],
            ["DOI sourcing","<X embedded, Y Crossref, Z blank — list blank/low-confidence ref #s>"],
            ["Method","Tables transcribed from rendered page images, cross-checked vs pdftotext/pdfplumber. References extracted format-aware, DOIs from embedded links then Crossref."]]
    for i,(k,v) in enumerate(rows,1):
        a=ws.cell(i,1,k); b=ws.cell(i,2,v); a.alignment=WRAP_TOP; b.alignment=WRAP_TOP
        if i==1: a.fill=b.fill=HEADER_FILL; a.font=b.font=HEADER_FONT
        else: a.font=Font(bold=True)
        ws.row_dimensions[i].height=40
    ws.column_dimensions["A"].width=22; ws.column_dimensions["B"].width=100; ws.freeze_panes="A2"

wb = Workbook(); wb.remove(wb.active)
for t in tables: add_table_sheet(wb, t)
add_refs_sheet(wb, references)
add_source_sheet(wb, tables, references)
wb.save(OUTPUT_XLSX); print("Saved", OUTPUT_XLSX)
```

**Verify before finishing:** reopen `OUTPUT_XLSX`; print each sheet's `max_row`/`max_column`;
confirm each table's data rows/cols match the rendered image; confirm `References` row count ==
N + 1; spot-check first column + Ref. column of each table against the PNG. Fix the data and
rebuild if anything is off — don't hand-patch the xlsx. Then delete `/tmp/renders` and any text
dumps, and report only: the output path, sheets created, and one line on anything uncertain.
