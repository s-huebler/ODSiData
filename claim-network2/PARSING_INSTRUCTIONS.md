# Quotes → Claims / Studies Parsing Instructions

Reusable procedure for the GVHD microbiome claim-network workbook
(`claim-network2/Claims_<date>.xlsx`). When Sophie says **"parse the quotes page
into Claims and Studies"**, follow this document.

Companion to the persistent `claim-synthesis-procedure` memory. This file governs the
*mechanical* parse of a review's quotes; that memory governs cross-review claim
harmonization.

## Goal

Sophie reads GVHD-microbiome **review papers** and pulls verbatim quotes into the
**Quotes** sheet, one quote per row: column A = citing review (e.g. `Sohouli_2025`),
column B = the quote, column C = optional notes. This procedure converts those quotes
into structured rows in the **Claims** and **Studies** sheets, matching the style of
the already-organized `Paredes_2026` and `Moses_2026` entries.

Two downstream research goals drive what to capture:

1. **Taxa synthesis** — for each bacterial taxon (or class of taxa), the *direction* of
   its association with GVHD and the *strength of evidence* (how many primary studies
   support it). → Claims sheet.
2. **Translational gaps** — classify associations by *mechanism*, then track how far the
   *therapeutic potential* of each mechanism has been explored. → Claims (mechanism +
   therapeutic implication) and Studies (actual interventions).

## Step 1 — Read the Quotes sheet

Group rows by column A (citing review). Each source may use a different citation style
(see Step 5). Note that Sophie has already flagged some quotes may not be relevant — that
is expected.

## Step 2 — Relevance filter (default: microbiome ↔ GVHD only)

Keep a quote only if it ties a **taxon, microbial class, microbial metabolite, microbial
mechanism, or microbiome-directed therapy** to **GVHD** (acute or chronic, including
gut/GI, skin, hepatic, and pulmonary/BOS cGVHD; mortality/OS and TRM in the HSCT context
count).

Drop quotes that are about:
- other diseases (e.g. ITP, chronic fatigue syndrome, ulcerative colitis) with no GVHD link;
- generic FMT/antibiotic mechanics with no GVHD outcome;
- purely host-side biology (immune cells, epithelial cells) with no microbial actor —
  *unless* the microbiome is explicitly implicated.

If Sophie asks for a looser filter, also capture general microbiome/immune-mechanism
quotes even when the GVHD link is indirect.

## Step 3 — Split each kept quote into Claims vs Studies

- **Claim** = a directional association or mechanism between a microbe/metabolite and
  GVHD (observational, hypothesized, or mechanistic). One row per distinct taxon/direction.
  A single quote often yields several claim rows (e.g. "X up, Y down in GVHD" = 2 rows).
- **Study** = a specific translational study with an **intervention/therapy** and an
  **outcome** (measured or planned): antibiotics, probiotics, prebiotics, diet, FMT,
  drugs, decontamination — in humans or mice. Record design, therapy, outcome, N, timing,
  and trial ID where given.
- A quote describing an intervention that *also* implies a taxon direction gets **both** a
  Study row and one or more Claim rows.

Split a quote into multiple rows whenever it names multiple taxa or multiple directions.
Deduplicate: several sources restate the same primary study (e.g. Hayase 2022, Shono 2016,
Jenq 2012); within one review, merge repeated quotes into a single row and combine their
citations with `; `.

## Step 3b — What qualifies as a Claim entity (tree-placeable rule)

The Claims sheet feeds a phylogenetic-tree figure (favourable vs unfavourable clades).
So the **Taxa** or **Nonspecific Microbes** column of every Claim row must hold something
that could be **placed on a phylogenetic tree** (a named taxon) or used to **circle a
group of tips** (a functional grouping that maps onto one or more clades).

**Keep** (goes in a Claim row):
- Named taxa at any rank — species, genus, family, order, class, phylum
  (e.g. *Blautia*, Clostridiales, Firmicutes, *Bacteroides thetaiotaomicron*). → **Taxa** column.
- Circle-able functional groups that correspond to a set of tips
  (e.g. "SCFA (butyrate) producers", "propionate producers", "gram-negative bacteria (LPS)",
  "gram-positive bacteria", "butyrate-synthesizing bacteria"). → **Nonspecific Microbes** column.
- **Edge case — metabolite claims:** a quote like "butyrate reduces GVHD" is recorded as
  Nonspecific = "SCFA (butyrate) producers", Relationship = negative/protective,
  Mechanism General = the metabolite. Record the *producer group*, never the bare metabolite.

**Drop** (do NOT create a Claim row; a Study row may still apply):
- **Interventions / therapeutic strategies** — probiotics, prebiotics (FOS/GOS/inulin),
  FMT, antibiotic stewardship, gut decontamination, drugs. These belong in **Studies** only,
  never in Claims.
- **Host-side mechanisms with no microbial actor** — Paneth cells / AMPs, goblet-cell
  damage, MHC II expression, PRR/MAMP signalling, IL-17A / IL-22 / LCN2 / neutrophil or
  Treg biology *stated as the entity*. (The microbe that drives them can still be a claim if
  named or circle-able, e.g. "gram-negative bacteria (LPS)" instead of "MAMP translocation".)
- **Over-general descriptors** — "healthy gut microbiota", "beneficial commensals",
  "specific gut bacteria", "intestinal commensal bacteria". Too vague to place or circle;
  identifying the specific taxa is the whole point of the project.
- **Community-level properties** — microbial diversity / "low diversity" / total abundance.
  Not a clade, so not tree-placeable. (A diversity quote that *also* names a taxon, e.g.
  "low diversity with Enterococcus mono-dominance", is kept as an Enterococcus row.)

Note: **segmented filamentous bacteria** is a functional/colloquial group, so it goes in
**Nonspecific Microbes**, not Taxa.

## Step 4 — Claims sheet columns

| Column | What to record |
|---|---|
| **Citing** | The review (col A of Quotes), e.g. `Sohouli_2025`. |
| **Cited** | Reference(s) the review attributes the claim to, **in the review's own citation style** (Step 5), multiple separated by `; `. Blank if the review states it generally. |
| **Taxa** | Specific taxon/taxa (species, genus, family, order, phylum). Multiple separated by `; `. Leave blank if only a non-specific descriptor applies. |
| **Nonspecific Microbes** | Non-taxonomic descriptors: "low diversity", "SCFA-producing bacteria", "gram-negative bacteria (LPS)", "propionate producers", a therapy class, etc. |
| **Suspected Relationship to GVHD** | Direction + role, following existing phrasing: `Positive; exacerbative`, `Positive; exacerbative or causal`, `Negative association; protective`, `Positive; predictive of aGVHD`, `Complex; context-dependent`, `Prognostic (survival indicator)`, etc. **Convention: "Positive" = more of the taxon → more/worse GVHD; "Negative/protective" = more of the taxon → less GVHD.** Record faithfully even when reviews conflict, and add a short note in the mechanism column when they do. |
| **Mechanism General** | Category bucket. Reuse existing buckets where possible: `Immune - Microbial antigens`, `Immune - MHC II inducer/suppressor`, `Immune - T reg`, `Immune - Th17`, `Immune - PRR / MAMP translocation`, `Immune - AMP (Paneth)`, `Immune - IL-17`, `Immune - IL-22 / ILC`, `Immune - MAIT`, `Immune - Neutrophils`, `Immune - Nlrp3 inflammasome / IL-1`, `Metabolites - SCFA (butyrate/propionate)`, `Metabolites - Bile acid`, `Metabolites - Metalloprotease`, `Metabolites - Indole / tryptophan`, `Mucus`, `Barrier / epithelial`, `Diversity`, `Dysbiosis`, `Biomarker`, `Virome`, `Therapeutic strategy`, `General`. Add new buckets sparingly. |
| **Mechanism Specific** | One-line mechanism. |
| **Mechanism Detailed** | Longer mechanistic description when the quote provides one. |
| **Therapeutic Implication** | Any therapy/intervention the quote ties to this taxon/mechanism. |
| **Evidence** | Combine with `; `: `Hypothesis`, `Observed association in humans`, `Observed mechanism in humans`, `Observed mechanism in mice`, `Observed association in mice`, `Reviewed in literature`. |
| **Source** | `Primary` when a specific primary study is cited; `General` when the review states it without attribution. |

## Step 5 — Citation style per source (record as-is in `Cited`)

Reviews cite differently. **Do not convert between styles** — record whatever the review
uses, separating multiple with `; `.

- **Numeric reviews** (e.g. `Sohouli_2025`, `Bai_2025`, `Paredes_2026`, `Moses_2026`):
  use the bracketed reference numbers, e.g. `5; 6; 7`.
- **Author-name reviews** (e.g. `AzharUdDin_2025`): use `Author et al. YEAR`, e.g.
  `Hayase et al. 2022; Shono et al. 2016`. Note AzharUdDin occasionally drops in a numeric
  ref (e.g. `[57]`) — record that literally too.

(Reflink resolution to canonical references, if needed, happens later via the
`*_reflinked.xlsx` workflow, not in this parse.)

## Step 6 — Studies sheet columns

| Column | What to record |
|---|---|
| **Citing** | The review. |
| **Cited** | Reference(s) for the study, in the review's citation style. |
| **Study** | Design: `RCT`, `Randomized phase II`, `Phase III`, `Cohort`, `Case series`, `Retrospective`, `Prospective randomized`, `Feasibility`, `Pilot`, `Preclinical (mouse)`, `Longitudinal`, etc. Add population in parentheses if notable (e.g. `Retrospective (pediatric)`). |
| **Therapy** | The intervention (and comparator, `vs`). |
| **Outcome** | Result if measured; `Ongoing`/planned endpoint if not. |
| **N** | Participant/subject count if given. |
| **Therapy Time** | Timing window (e.g. `Day -7 to day +100`, `After neutrophil recovery`). |
| **Study ID** | Trial identifier (e.g. `NCT03057054`, `ACCL1633`). |

## Step 7 — Write output

- Write to a **new versioned workbook** `Claims_<DDMonth>.xlsx` (e.g. `Claims_15July.xlsx`),
  loaded from the latest existing workbook so `Paredes`/`Moses` and prior rows are preserved.
- **Append** new rows below existing data in the Claims and Studies sheets; never overwrite
  existing rows. Leave the Quotes sheet in place.
- Preserve the existing header/column order exactly (Claims cols 1–11; Studies cols 1–8;
  ignore the trailing `Column3/4/5` filler columns).

## Step 8 — Verify

- Print per-review row counts for Claims and Studies and confirm existing counts are
  unchanged (Moses = 15 claims / 15 studies; Paredes = 29 claims / 20 studies as of
  14 July 2026).
- Spot-check that each new row's values land under the intended headers (no column drift).
- Report which quotes were dropped by the relevance filter and any inter-review
  contradictions worth noting.

## Sources parsed so far

| Review | Quotes | Citation style | Notes |
|---|---|---|---|
| `Paredes_2026` | — | numeric | organized (baseline style) |
| `Moses_2026` | — | numeric | organized (baseline style) |
| `Sohouli_2025` | 22 | numeric | pediatric meta-analysis/review |
| `Bai_2025` | 30 | numeric | Sophie's "Din"; many quotes off-topic (ITP, CFS) and filtered out |
| `AzharUdDin_2025` | 81 | `Author et al. YEAR` (+ occasional `[57]`) | heavy on antibiotics, SCFA/immune mechanisms, and FMT trials; several repeated quotes merged |
