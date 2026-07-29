# Table + Reference Extraction — Redesign

**Status:** design proposal (not yet built)
**Replaces:** `extract_pdf_xlsx.sh` + `pdf_extract_prompt.md` (one full `claude -p` agent per PDF)
**Goal:** same deliverable (one `<Lastname_Year>_tables.xlsx` per paper: table sheets + References sheet + Source & Notes), at a fraction of the tokens and wall-clock, as a **general** process for any incoming paper.

---

## Why the current process is expensive

The current script spawns a complete agentic Claude session for *every* PDF. Inside that session Claude renders every table page to PNG, visually transcribes it, then re-derives the reference list from scratch with hand-rolled column geometry plus Crossref lookups. Two problems:

1. **The unit of work is a whole agent, not a task.** Orchestration, tool setup, and re-reading the prompt happen once per PDF and dominate the token bill.
2. **It does hard work that a structured source already did for free.** Open-access publishers expose the *same* tables and references as clean XML/HTML. Reading them from a PDF image is the most expensive possible way to get data that is available as machine-readable text.

The fix is a **router**: get each piece of data from the cheapest source that can supply it correctly, and only escalate to vision when nothing structured exists.

---

## Core principle — escalate, don't default to vision

```
Resolve IDs → try structured full text → try publisher HTML → fall back to PDF
                    (deterministic, ~0 tokens)          (LLM only here, and cheaply)
```

Every paper is routed to the **lowest tier that works**. Most GVHD/microbiome papers of interest are in PMC's open-access subset, so the majority never touch a PDF or a vision model.

---

## Tier 0 — Resolve identifiers and pick a route

Input is a manifest row with whatever is known: PDF path, DOI, PMID, PMCID, title. Normalize to a canonical ID set and decide the route.

- **ID crosswalk:** NCBI ID Converter (`https://www.ncbi.nlm.nih.gov/pmc/utils/idconv/v1.0/`) maps DOI ↔ PMID ↔ PMCID in one call. If only a title is known, resolve DOI via Crossref `query.bibliographic` first (fuzzy-match gate, see QC).
- **Open-access check:** Europe PMC (`.../search?query=EXT_ID:<pmid>&resultType=core`) returns `isOpenAccess` and whether `fullTextXML` is available; the PMC OA web service confirms OA-subset membership.
- **Route decision, cached** so reruns are free:
  - Structured XML available → **Tier 1**
  - No XML but clean publisher HTML full text → **Tier 2**
  - Neither (paywalled / scan-only) → **Tier 3**

Record the chosen route as **provenance** on every output — it becomes the trust signal downstream.

---

## Tier 1 — Structured full text (JATS XML) — preferred, near-zero tokens

This single tier supplies **both** tables and references, correctly, with no LLM.

- **Fetch:** Europe PMC `.../{PMCID}/fullTextXML`, or NCBI `efetch db=pmc id=<PMCID> rettype=xml`. Cache the raw XML.
- **Tables** — parse `<table-wrap>`: `<label>` + `<caption>` → sheet title; `<table>` `<thead>`/`<tbody>` → header + rows; `<table-wrap-foot>` → the footnote/abbreviation note row. `rowspan`/`colspan` are explicit attributes, so multi-line cells and spanned headers are handled deterministically — the exact failure modes the vision prompt warns about disappear because the structure is given, not inferred.
- **References** — parse `<ref-list>/<ref>`: `<element-citation>`/`<mixed-citation>` give ordered authors, year, article title, and `<pub-id pub-id-type="doi">` directly. Clean, contiguous, correctly ordered — and notably better than GROBID, which in spot checks introduced errors on these papers.
- **DOIs** come from the XML itself; Crossref is only a backfill for the occasional missing one.

Feed the parsed dicts straight into the existing openpyxl builder (PART C of `pdf_extract_prompt.md`) — that styling code is fine and worth keeping.

---

## Tier 2 — Publisher HTML (fallback when no JATS)

Some publishers without a PMC deposit (or with an embargo) still serve clean HTML full text — MDPI, Frontiers, Nature, Wiley, and similar. This is the second half of the "use the link, not the PDF" idea.

- Fetch the article HTML; extract tables from `<table>` nodes (pandas `read_html` / a fast HTML parser) and references from the reference section.
- HTML is per-publisher and messier than JATS, so keep this tier **thin and optional**: support the handful of publishers that dominate your corpus, and let anything else drop to Tier 3. Tag provenance as `html:<publisher>` so it can be reviewed with appropriate skepticism.

---

## Tier 3 — PDF fallback (only when nothing structured exists)

Reached only for paywalled or scan-only papers. Split the two tasks so each uses the cheapest adequate method.

- **References:** GROBID `processReferences` → TEI. Because GROBID errs on these papers, **do not trust it silently** — run the reference QC below, gate DOI matches through Crossref fuzzy confidence, and **flag** low-confidence refs for human review rather than shipping them as clean.
- **Tables:** render **only the table pages** (located from `pdftotext -layout` caption search) and do a **single vision pass with a small model (Haiku)** — not a full agent per PDF. Send the page image *and* the `pdftotext -layout` text of that page together, so the model transcribes against a text layer instead of reasoning from pixels alone. No orchestration, no per-PDF agent boot; that removes the biggest cost driver of the current design.

---

## Extra checks (the trust layer you asked for)

Cheap sources are only worth it if you can tell when they went wrong. Every output carries provenance and passes QC before it counts as done.

**Table QC:** row/column counts consistent across the sheet; numeric columns parse as numeric; caption/label present and matched; footnote block captured as a note row, not as data.

**Reference QC:** numbering is contiguous `1..N` and `N` matches the max printed number; every reference has a year and the abbreviation ends in it; every DOI matches `^10\.\d{4,9}/\S+$`; HEAD-resolve a random 3–5 DOIs; Crossref backfill accepted only when title `token_set_ratio ≥ 88` **and** (year ±1 **and** first-author surname present), else left blank.

**Provenance + review queue:** each workbook's Source & Notes sheet records the route (`jats` / `html:<pub>` / `grobid+qc` / `vision`) and any QC flags. A per-batch summary lists every paper that fell to Tier 3 or failed a check, so review effort goes only where the cheap path couldn't reach. This replaces "silently trust the extraction" with "trust the structured tiers, review the flagged tail."

---

## Architecture

```
manifest.csv ─► 00_resolve_ids.py ─► route + cached IDs/OA status
                                         │
        ┌────────────────────────────────┼───────────────────────────┐
   Tier 1 (JATS)                    Tier 2 (HTML)               Tier 3 (PDF)
 parse_jats.py                    parse_html.py         grobid_refs.py + vision_tables.py
        └────────────────────────────────┼───────────────────────────┘
                                         ▼
                       build_workbook.py  (reuse PART C openpyxl)
                                         ▼
                          <Lastname_Year>_tables.xlsx  +  batch_qc_report.csv
```

- **Manifest-driven** (columns: `pdf, doi, pmid, pmcid, title`) so it generalizes to any future paper set, not just the current 29.
- **Idempotent / resumable:** keep the existing skip-if-`.xlsx`-exists behavior; also cache resolved IDs and fetched XML/HTML so reruns cost nothing.
- **One shared workbook builder** across all tiers → identical output schema regardless of source, plus provenance/QC columns on Source & Notes.
- **Polite networking:** cache aggressively, backoff on 429/5xx, `User-Agent` with `mailto:sophhuebler@gmail.com` for Crossref/NCBI.

---

## Expected effect

For an open-access-heavy corpus, the common case (Tier 1) is a deterministic XML parse with **no LLM tokens at all** for either tables or references. The LLM is reserved for Tier 3 table transcription only, on a small model, scoped to specific pages, with no per-PDF agent — the three things that made the current version slow and token-hungry.

---

## Open questions before building

1. **Corpus OA rate** — worth measuring PMC/OA coverage on a real target list; it sets how often Tier 3 (the only expensive tier) actually fires.
2. **HTML tier scope** — which publishers appear often enough to justify a Tier 2 parser vs. letting them fall to Tier 3.
3. **Vision model choice** for Tier 3 tables (Haiku vs. Sonnet) — trade transcription fidelity on dense tables against cost.
4. **Where this lives** — new `scripts/extraction/` module vs. extending `citation-network/scripts/` (which already runs GROBID and TEI parsing).
