# Prompt 2: Crossref lookup for remaining blank DOIs

You are processing **one** spreadsheet of references (the output of a prior pass that already
filled in DOIs it could extract directly from `full_citation` text). Your job is to fill in a DOI
for **every row that still has a blank `doi` cell**, using Crossref lookups. **Never invent a
DOI** — if you cannot find or verify one with confidence, leave the cell blank.

The harness supplies these values in the message; use them verbatim:

- `INPUT_PATH`  — ~/Desktop/References_Pubmed_parsed_dois.xlsx 
- `OUTPUT_PATH` — ~/Desktop/References_Pubmed_parsed_dois2.xlsx 
- `SHEET_NAME`  — Sheet1


Expected columns (case-sensitive, may have others alongside — leave any other columns untouched):
`citing_paper`, `citing_doi`, `local_number`, `full_citation`, `abbrev_citation`, `doi` (and
possibly a `doi_source` column from the first pass — ignore it other than as a hint).

```bash
pip install openpyxl pandas requests rapidfuzz --break-system-packages
```

---

## 1. Load and select rows to process

Load the sheet preserving row order. Select every row where `doi` is blank/empty/NaN — these are
the leftovers from the first pass. Leave every row that already has a non-blank `doi` completely
untouched (don't re-derive or "improve" it).

**Do not use `abbrev_citation` to copy DOIs between rows**, even within this leftover set.
Multiple citing papers can share a reference (same `abbrev_citation`, e.g. `Gratwohl_2015`), but
`abbrev_citation` is **not guaranteed unique** — two unrelated references can collide on the same
abbreviation (e.g. two different first-author "Smith 2020" papers). Every row's DOI must come from
an **independent** Crossref lookup keyed on that row's own `full_citation`. It's fine — expected,
even — for rows that share an `abbrev_citation` to end up with the same DOI, as long as each was
derived independently rather than copied.

---

## 2. Crossref lookup

For each selected row:

```
GET https://api.crossref.org/works?query.bibliographic=<full_citation text>
User-Agent: mailto:sophhuebler@gmail.com
```

- **Hard timeout: 5 seconds max per row.** Pass `timeout=5` to the request (e.g.
  `requests.get(..., timeout=5)`). If it raises `requests.exceptions.Timeout` or
  `requests.exceptions.ConnectionError`, do not retry that row further — log it, leave `doi`
  blank, and move on to the next row immediately. A single stalled lookup must never hold up the
  rest of the run.
- Retry on `429`/`5xx` with exponential backoff, but the retry loop's total time for one row must
  still respect the 5-second cap — don't let backoff sleeps push a single row past that budget.
- Sleep 0.3–1.0 s between calls (be polite; this may run to a few hundred rows).
- Parse a rough title/year/first-author from `full_citation` to support a confidence check — the
  citation format varies by citing paper, so keep this parsing forgiving; you don't need a
  structured citation parser, just enough signal to sanity-check the Crossref match.
- From the top candidate(s), accept the DOI only when confident:
  - `rapidfuzz.fuzz.token_set_ratio(candidate_title, citation_text)` ≥ ~88 **and** (year within
    ±1 of the year parsed from the citation **and** the first author's surname appears in the
    candidate's author list), **or**
  - title similarity ≥ ~95 alone.
- Otherwise leave `doi` blank. Book chapters, registry entries, and some preprints legitimately
  have no DOI — a blank result is correct, not a failure.

---

## 3. Validate before writing

- Every newly filled `doi` matches `^10\.\d{4,9}/\S+$` (no spaces).
- Spot-check 3–5 newly filled DOIs by resolving `https://doi.org/<doi>` (HEAD, follow redirects)
  to confirm they're live.
- Informational check (don't auto-correct): flag any case where two rows share the same
  `abbrev_citation` but ended up with different non-blank DOIs after this pass — could be a
  legitimate abbreviation collision, but worth a line in the report so it can be eyeballed.

## 4. Save progress as you go

Don't hold everything in memory until the very end. **Write the current state of the spreadsheet
to `OUTPUT_PATH` after every 25 rows processed** (i.e. every 25 Crossref lookups attempted,
whether or not they succeeded — a timeout/blank still counts toward the 25). This means the run
can be interrupted at any point and resumed without losing more than ~24 rows of work.

To make resuming cheap: at the start of the script, if `OUTPUT_PATH` already exists, load it
instead of `INPUT_PATH` and skip any row that already has a non-blank `doi` — this lets you
re-run the exact same command after an interruption and it will pick up where it left off rather
than redoing already-completed lookups.

Print a one-line progress log at each checkpoint, e.g.:
`Checkpoint: 75/238 rows processed, 61 filled via Crossref, 14 left blank — saved to OUTPUT_PATH`.

## 5. Write final output

Write to `OUTPUT_PATH` in the same format/columns as the input — only blank `doi` cells are
changed. If a `doi_source` column exists from the first pass, mark newly filled rows `crossref`
and leave rows that stayed blank as `blank` (or empty).

Report at the end: total rows processed in this pass, how many resolved via Crossref, how many
left blank, and any `abbrev_citation` DOI mismatches flagged in Step 3 — broken down by
`citing_paper` if that's easy to include.
