# Prompt 1: Extract embedded DOIs from `full_citation` text

You are processing **one** spreadsheet of references pooled from ~20 citing papers. Each row is
one reference (`local_number` within its `citing_paper`). Your only job in this pass is to fill in
DOIs that are **already present as text inside `full_citation`** — no network lookups in this
prompt. **Never invent a DOI**; if it's not extractable from the text, leave the cell blank (it
will be handled by a second pass later).

The harness supplies these values in the message; use them verbatim:

- `INPUT_PATH`  — ~/Desktop/Batch2_ToExtractDoi.xlsx
- `OUTPUT_PATH` —~/Desktop/Batch2_ExtractedDoi.xlsx
- `SHEET_NAME`  — Sheet1

Expected columns (case-sensitive, may have others alongside — leave any other columns untouched):
`citing_paper`, `citing_doi`, `local_number`, `full_citation`, `abbrev_citation`, `doi`.

```bash
pip install openpyxl pandas --break-system-packages
```

---

## 1. Load and group

Load the sheet preserving row order. Group rows by `citing_paper`, and within each group sort by
`local_number` ascending. Process one `citing_paper` group at a time, top to bottom.

**Do not use `abbrev_citation` to copy DOIs between rows.** Multiple citing papers can share a
reference (same `abbrev_citation`, e.g. `Gratwohl_2015`), but `abbrev_citation` is **not
guaranteed unique** — two unrelated references can collide on the same abbreviation. Every row's
DOI in this pass must come only from that row's own `full_citation` text.

---

## 2. Per-`citing_paper` embedded-DOI probe

DOI-in-text pattern to search for: a substring matching

```
10\.\d{4,9}/\S+
```

then trimmed of trailing punctuation that's clearly sentence/markup noise rather than part of the
DOI (trailing `.` `,` `;` `)` `]` when not immediately preceded by a digit that looks mid-DOI —
use judgement; e.g. `10.1016/S2352-3026(15)00028-9` keep the parenthetical, but `...00028-9.` at a
sentence end loses the final period; `...00028-9 - DOI - PubMed` stops at the whitespace before
`-` because of `\S+`). A DOI must not contain spaces.

For each `citing_paper` group:

1. Look at the `full_citation` of the row with `local_number == 1`. Search it for the pattern
   above.
2. If not found, also check `local_number == 2` (if it exists).
3. **If either of those two citations contains a DOI-shaped substring** → mark this group
   `embedded = True`. Extract the DOI from **every** row in the group using its own
   `full_citation` (Step 3).
4. **If neither of the first two citations contains one** → mark this group `embedded = False`.
   Leave `doi` blank for **every** row in this group — do not keep scanning later rows in the
   group for a stray embedded DOI (citation format is assumed consistent within one citing
   paper's list), and do not attempt any lookup here. These rows are intentionally left for the
   second prompt.

Print a one-line summary per group as you go, e.g.:
`Limpert_2023 (18 refs): embedded=True (found in local_number=1)`.

---

## 3. Extract into the `doi` column

For every row in an `embedded=True` group, apply the pattern from Step 2 to that row's own
`full_citation` and write the result into `doi`. If extraction unexpectedly fails on a particular
row despite the group being `embedded=True` (a format inconsistency), leave that row's `doi`
blank rather than guessing — it will be picked up in the second pass.

For every row in an `embedded=False` group, leave `doi` blank.

---

## 4. Validate before writing

- Every non-blank `doi` matches `^10\.\d{4,9}/\S+$` (no spaces, no leftover brackets/quotes from
  extraction, no trailing period unless it's genuinely part of the DOI).
- Spot-check a handful of extracted DOIs visually against their source `full_citation` text.

## 5. Write output

Write to `OUTPUT_PATH` in the same format/columns as the input — only the `doi` column changes.
Optionally add a `doi_source` column with `embedded` for rows filled in this pass, left blank
otherwise (useful so the second prompt can see at a glance which rows still need work, though it
should treat any blank `doi` cell as needing work regardless).

Report at the end, per `citing_paper`: total refs, `embedded=True` or `False`, and how many rows
were filled vs. left blank (should be all-or-nothing per group except for extraction-failure
edge cases).
