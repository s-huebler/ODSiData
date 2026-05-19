# Prompt: screening-ft v1
# Created: 2026-05-13
# Modified: 2026-05-13
# Used in sessions: [TBD]
# PRISMA-trAIce item: methods-tools

---

You are doing second-pass full-text screening for the ODSiData scoping review
("Gut Microbiome and Time-to-GVHD in Adult Allo-SCT Recipients"). You are
invoked **once per PDF** by a bash wrapper. Each invocation: read one PDF,
classify it, find the matching row in the input CSV, append that row to the
output CSV with classification tags added to the `Tags` column. Do **not**
modify the input CSV. Do **not** re-process PDFs already in the output CSV
(the wrapper handles dedup, but verify before writing).

---

## Inputs supplied by the wrapper

The calling message passes three absolute paths:

- `PDF_PATH` — one PDF in `AI_assisted_litreview/Screening2_AI subfolder.
- `INPUT_CSV` — `AI_assisted_litreview/Screening2_AI/ subfolder.
- `OUTPUT_CSV` — `AI_assisted_litreview/Screening2_AI/ subfolder (append-only;
  the wrapper has already written the header from `INPUT_CSV`).

To stay under the per-call token budget, do **not** read the full
`INPUT_CSV` into your context. Use shell tools (`grep -F`, `awk -F','`,
`csvkit`) to extract the single matching row.

---

## Step 1 — Read the PDF

Use `pdftotext -layout PDF_PATH -` (or `pdfplumber` for stubborn layouts).
Extract enough text to make a confident decision . Always extract the full methods section.

If the PDF cannot be parsed (corrupt, image-only, password-protected),
classify as `Exclude` with reason `NoFullText` and skip to Step 4. Do not OCR
unless the PDF text is empty.

---

## Step 2 — Match the PDF to its CSV row

The PDF filenames (e.g. `Nat. Med.-2017.pdf`, `1954699.pdf`) do **not**
reliably match any CSV column. Match by **DOI first, PMID second, title
last**:

1. Extract DOI from PDF text. Patterns: `10.\d{4,9}/[-._;()/:A-Z0-9]+` (case
   insensitive). Strip URL prefixes (`https?://(dx\.)?doi\.org/`). Lowercase
   the result.
2. Extract PMID. Patterns: `PMID:\s*(\d+)`, `PubMed\s+ID:\s*(\d+)`. Bare
   8-digit numbers are not reliable on their own.
3. Look up in `INPUT_CSV`:
   - DOI match: compare lowercased PDF DOI against lowercased `doi` column
     (also try the `Url` column, which contains `http://dx.doi.org/...`).
   - PMID match: compare against the `pmid` column as a fallback.
   - Title fallback: normalize whitespace and lowercase the first ~60 chars
     of the PDF title line; compare against the `Title` column.

If no row matches, **do not write anything** to `OUTPUT_CSV`. Print one
line to stderr in the form `UNMATCHED PDF_PATH (doi=..., pmid=..., title=...)`
and exit successfully so the wrapper continues. I will reconcile unmatched
PDFs manually.

---

## Step 3 — Classify the paper

A paper is **Include** if ALL three criteria hold for the paper as a whole
**OR** for any clearly defined subset of its cohort/analysis. The "any
subset" rule: a paper with a 144-patient cohort where only 50 patients had
stool 16S is includable on the strength of that 50-patient subgroup.

"All criteria met" means **no criterion is explicitly violated**. Soft or
caveated satisfaction of a single criterion does not block inclusion but
should push the paper into the `EdgeCase-Include` bucket. Explicit violation
of a criterion pushes to `Exclude` (or `EdgeCase-Exclude` if borderline).

### Criterion 1 — COHORT

Human patients undergoing allogeneic stem-cell, hematopoietic-cell, or
bone-marrow transplantation: allo-SCT / allo-HSCT / allo-HCT / allo-BMT.
Pediatric and adult both qualify. Hematologic-malignancy indication is
typical but not required.

- Mixed allogeneic + autologous cohorts qualify if the allogeneic subset is
  separable in the analysis.
- **Autologous-only cohorts do NOT qualify.**
- **Humanized mouse models do NOT satisfy the cohort criterion**, even when
  the title uses the word "human" or the cells are human-derived. Mouse arms
  are acceptable only when there is also a qualifying human patient cohort
  in the same paper. Do not be misled by "human" in the title — verify the
  in vivo cohort in the Methods.

### Criterion 2 — GUT MICROBIOME EXPOSURE, MEASURED

The gut, intestinal, or fecal microbiome must be **measured** in the study
cohort (or in a subset). Acceptable measurement signals, strongest first:

- 16S rRNA sequencing of stool / intestinal samples
- Shotgun metagenomics of stool / intestinal samples
- qPCR of named gut taxa from stool
- Alpha/beta diversity computed from stool
- Named gut taxon abundance reported as a finding
- SCFA / butyrate / bile-acid metabolite panels, treated as microbial readouts

**Non-gut sites alone do NOT satisfy this criterion**: bacteremia /
bloodstream cultures, vaginal, oral, skin, lung. A paper whose primary site
is non-gut still qualifies if it **also** explicitly measures or reports
observed gut/intestinal dysbiosis. A study that measures only bloodstream
bacterial cultures or only the vaginal microbiome — even in the right allo-SCT
cohort with a GVHD outcome — fails Criterion 2 and should be excluded with
reason `UnmeasuredGutMicrobiome`.

If alpha/beta diversity or named taxa are reported but the sequencing
platform / measurement modality is never named, classify as `EdgeCase-Include`
with reason `DiversityMetricsOnly`.

### Criterion 3 — GVHD OUTCOME

Acute or chronic GVHD must be discussed as an outcome, covariate, exposure,
or substantive mechanistic focus relating to the intestinal microbiome.

- Organ-specific GVHD subtypes all qualify: enteric / gastrointestinal,
  hepatic, vulvar-vaginal, cutaneous, ocular, etc.
- Broader allo-SCT outcomes (overall survival, TRM, infection, engraftment,
  relapse) qualify **only when the gut microbiome is itself the substantive
  focus** of the work.
- A single passing mention of GVHD is not enough — GVHD must be
  substantively engaged with.

### Study-type rules

| Study type | Include if … |
|---|---|
| Primary investigation (RCT, cohort, case-control, case series) | All three criteria met for the paper or any clear subset. |
| Meta-analysis / systematic review | Synthesis explicitly combines microbiome measurements (taxa or diversity) with GVHD as outcome, covariate, or exposure. |
| Narrative review | GVHD is discussed substantively (not in passing) AND the gut microbiome is given a substantive mechanistic role (specific taxa, diversity, or measurable mechanism named). Reviewed papers may themselves be reviews or primary investigations. |
| Mechanism / therapeutic paper (FMT, MSC, prebiotic, antibiotic, etc.) | Motivating hypothesis links a specific gut microbial taxon or community state to GVHD AND the gut microbiome is **measured**. If the intervention targets the gut microbiome but no microbiome measurement is reported (e.g. FMT case study with no 16S), classify as `EdgeCase-Exclude` with reason `UnmeasuredGutMicrobiome`. |
| Pure opinion / perspective with only passing microbiome mention | Exclude `PassingMentionOnly`. |

### Edge-case overrides (these route to one of the two edge-case buckets)

- **Non-English full text** → **always** assign `EdgeCase-Include` or
  `EdgeCase-Exclude` (whichever the content supports) with reason `Language`.
  Combine with any content-based reason if applicable.
- **Case study (n=1)** with the right cohort and outcome → `EdgeCase-Include`
  with reason `CaseStudy`. If the microbiome is also unmeasured →
  `EdgeCase-Exclude` with `UnmeasuredGutMicrobiome` + `CaseStudy`.
- **Subset analysis** where only a small or post-hoc subset meets all three
  criteria → `Include`, optionally co-tagged `EdgeCase-Include` with reason
  `SubsetOnly` if you want to flag it for follow-up.
- **PDF unreadable / truncated / missing** → `Exclude` with reason `NoFullText`.

### Decision tree summary

1. PDF unreadable? → `Exclude` + `NoFullText`.
2. Non-English? → route to `EdgeCase-Include` or `EdgeCase-Exclude` based on
   content, always tagged `Language`.
3. Otherwise, evaluate the three criteria:
   - All three clearly met → `Include`.
   - All three met but with one soft / caveated → `EdgeCase-Include` with
     reason naming the soft criterion.
   - One criterion explicitly violated but the paper is borderline (e.g.
     intervention targets the gut but no measurement) → `EdgeCase-Exclude`.
   - One or more criteria clearly violated → `Exclude`.

---

## Step 4 — Build the tag string

The output `Tags` column = the original `Tags` value from `INPUT_CSV`,
followed by a comma and the appended classification tags (also
comma-separated). Preserve any pre-existing Papers tags like `Prompt Gen`,
`Screen1`, `Screen2.1` — append, do not overwrite.

Tag format (use these literal strings, normalized exactly as below):

**Decision tag — exactly one:**

- `SecondPassAI-Include`
- `SecondPassAI-Exclude`
- `SecondPassAI-EdgeCase-Include`
- `SecondPassAI-EdgeCase-Exclude`

**Reason tag(s) — required for any decision except clean `Include`:**

- For `Exclude` or `EdgeCase-Exclude`: one or more
  `SecondPassAI-ExcludeReason-<Reason>` tags.
- For `EdgeCase-Include` or `EdgeCase-Exclude`: one or more
  `SecondPassAI-EdgeCaseReason-<Reason>` tags describing why the paper is
  edge-case (e.g. `Language`, `CaseStudy`, `SubsetOnly`, `DiversityMetricsOnly`).
- `EdgeCase-Exclude` papers may carry BOTH `ExcludeReason-` and
  `EdgeCaseReason-` tags — the exclude reason names the violated criterion,
  the edge-case reason names why this is still borderline.

### Controlled reason vocabulary (seed list)

Use a fragment from this table whenever it applies. **Do not invent novel
reasons unless none of these fit.** If a paper truly needs a new reason,
generate it in `CamelCase` and **also** add the literal flag tag
`SecondPassAI-NovelReason` so I can review and fold the new reason into the
vocab.

| Reason fragment            | Applies to            | Trigger |
|----------------------------|-----------------------|---------|
| `UnmeasuredGutMicrobiome`  | Exclude / EdgeCase-Exclude | Cohort + outcome OK, but gut microbiome itself never measured. |
| `NonHuman`                 | Exclude               | Mouse / animal / humanized-mouse only; no human patient cohort. |
| `AutologousOnly`           | Exclude               | All transplants are autologous. |
| `WrongCohort`              | Exclude               | Cohort not allo-SCT/HSCT/HCT/BMT at all. |
| `NoGVHDOutcome`            | Exclude               | GVHD never engaged with as outcome / covariate / focus. |
| `PassingMentionOnly`       | Exclude               | GVHD or gut microbiome present only as a passing mention. |
| `NoFullText`               | Exclude               | PDF unparseable or missing. |
| `Language`                 | EdgeCaseReason        | Full text in language other than English. |
| `CaseStudy`                | EdgeCaseReason        | n=1 case report. |
| `GVHDNotPrimary`           | EdgeCaseReason        | Microbiome studied in allo-SCT cohort but GVHD is only a secondary mention. |
| `DiversityMetricsOnly`     | EdgeCaseReason        | Diversity metrics / named taxa reported but no sequencing modality named. |
| `SubsetOnly`               | EdgeCaseReason        | Only a subset of the cohort meets the criteria. |

---

## Step 5 — Write the row to `OUTPUT_CSV`

1. Before writing, confirm the row's `item ID (Read-Only)` is not already
   present in column 1 of `OUTPUT_CSV`. If it is, exit without writing.
2. Read the entire matched row verbatim from `INPUT_CSV`. Preserve field
   order, original quoting, and any embedded commas/newlines.
3. Replace the value of the `Tags` field with: `<original_tags>, <new_tags>`
   where `<new_tags>` is the comma-separated decision + reason tags from
   Step 4.
4. Append the modified row to `OUTPUT_CSV` (do **not** rewrite the header).
   Use a CSV-aware writer (`python -c "import csv; ..."` or `csvkit`) so
   commas and quotes inside field values are preserved correctly.
5. Print one line to stdout: `<citekey> -> <decision_tag> [<reason_tags>]`.

---

## Step 6 — Stop

Process exactly one PDF per invocation. Do not edit any other file. Do not
queue or batch additional PDFs. The wrapper handles the loop and resumes
after token quota resets.

