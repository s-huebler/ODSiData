# claim-network/lookups — Reference Tables

These CSV files are the controlled-vocabulary backbone of the claims synthesis
pipeline. Each table maps a verbatim string (as it appears in a source document
or workbook) to a canonical form used throughout the network. All files are
UTF-8, no BOM.

---

## subject_lookup.csv

**Purpose.** Translates every raw taxon token from `Atomic_Claims.taxon` to a
canonical `subject` name and classifies it by `subject_type`.

| Column | Description |
|---|---|
| `token_verbatim` | Exact string from the taxon cell (one row per distinct value) |
| `subject` | Canonical normalized form used everywhere downstream |
| `subject_type` | `taxon` \| `functional_group` \| `metabolite` \| `molecular_pattern` \| `other` |
| `note` | Why token differs from subject (e.g. "spelling corrected", "spp. abbreviation collapsed to genus", "Clostridia cluster collapsed to Clostridia class") |

**Adding a row.** Identify the token as it appears verbatim in the source. Choose
or add a canonical subject. Set `subject_type` based on `rank_lookup.rank_as_cited`:
species/genus/family/order/class/phylum → `taxon`; rank = functional → `functional_group`;
molecular_pattern → `molecular_pattern`. Leave `note` blank if token == subject.

**Conflicts** (same token → two different subjects) go to
`claim-network/review/seed_conflicts.csv` instead of here.

---

## rank_lookup.csv

**Purpose.** Records the taxonomic (or functional) rank at which each canonical
subject was cited. Used by step 03 of the pipeline.

| Column | Description |
|---|---|
| `subject` | Canonical subject name (one row per distinct subject) |
| `rank_as_cited` | `species` \| `genus` \| `family` \| `order` \| `class` \| `phylum` \| `functional` \| `molecular_pattern` |
| `source` | Provenance note (e.g. "July synthesis") |

**Adding a row.** Use the most specific rank actually cited in the literature for
that subject. If different papers cite at different ranks, use the most common one
and note any exceptions in `note` (add a note column if needed).

---

## valence_lookup.csv

**Purpose.** Maps every distinct `relationship_verbatim` string to a three-level
valence and a human-readable rule explaining the mapping.

| Column | Description |
|---|---|
| `relationship_verbatim` | Exact string from `Atomic_Claims.relationship_verbatim` |
| `valence` | `favourable` \| `unfavourable` \| `context` |
| `rule` | One-sentence rationale for the mapping |

**Valence semantics** (GVHD context):
- `favourable` — negative association with GVHD; taxon is protective or alleviative
- `unfavourable` — positive association with GVHD; taxon exacerbates or predicts disease
- `context` — complex, modulatory, no association, or purely prognostic; net direction unclear

**Adding a row.** Add the new verbatim string exactly as it appears in the source,
assign one of the three valence values, and write a brief rule. Do not reuse an
existing verbatim string for a different valence — if the same phrase maps
differently in a new study, flag it in `review/seed_conflicts.csv`.

---

## mechanism_lookup.csv

**Purpose.** Maps each distinct `mechanism_verbatim` string to semicolon-joined
controlled-vocabulary categories and a single primary category.

| Column | Description |
|---|---|
| `mechanism_verbatim` | Exact string from `Atomic_Claims.mechanism_verbatim` (blanks excluded) |
| `categories` | Semicolon-joined list of applicable controlled-vocabulary categories |
| `primary_category` | The single most salient category |

**Adding a row.** Choose categories from the established vocabulary (visible in
the existing rows). If a new category is genuinely needed, add it consistently
and update this README. Blank `mechanism_verbatim` rows are normal — not every
claim specifies a mechanism — and should not be added here.

---

## canonical_claims.csv

**Purpose.** Seed list of canonical claim IDs from the July 2026 synthesis.
Step 06 of the pipeline matches new atomic claims against this table.

| Column | Description |
|---|---|
| `claim_id` | Canonical claim identifier (e.g. CC-001) |
| `subject` | Canonical subject (matches rank_lookup.subject) |
| `rank_as_cited` | Rank from Canonical_Claims.subject_rank |
| `valence` | `favourable` \| `unfavourable` \| `context` |
| `claim_label` | Human-readable canonical claim wording |
| `first_seen` | ISO date when claim first entered the synthesis |

**Adding a row.** Assign the next sequential `claim_id`. Fill all columns. Set
`first_seen` to today's date in YYYY-MM-DD format. New claims that do not yet
match an existing ID should be routed through `review/needs_review_canonical.csv`
and added here only after human confirmation.

---

## july_flags.csv

**Purpose.** Verbatim copy of the `Flags` sheet from `Claims_Synthesis2.xlsx`.
Records data-quality flags raised during the July 2026 synthesis.

| Column | Description |
|---|---|
| `src_row` | Row number in the original source workbook |
| `field` | Column name where the flag applies |
| `flag` | Short flag code or description |
| `verbatim_value` | The flagged value as it appeared in the source |

This file is read-only for the pipeline; new flags from subsequent rounds should
go into a `flags_<date>.csv` file following the same schema.

---

## seed_conflicts.csv  (in review/, not lookups/)

Path: `claim-network/review/seed_conflicts.csv`

Captures any case where the same verbatim token maps to two different canonical
values. Requires human resolution before the token can be added to the relevant
lookup table.

| Column | Description |
|---|---|
| `token_verbatim` | The ambiguous token (subject conflicts) |
| `subject_a` / `subject_b` | The two competing canonical subjects |
| `subject_type_a` / `subject_type_b` | Corresponding subject types |
| `field` | "mechanism" for mechanism conflicts |
| `verbatim` | The ambiguous mechanism string |
| `value_a` / `value_b` | The two competing category strings |
