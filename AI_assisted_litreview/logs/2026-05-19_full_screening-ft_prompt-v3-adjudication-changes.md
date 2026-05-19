---
# ── PRISMA-trAIce Session Log ──────────────────────────────────────────────

date: "2026-05-19"
stage: "screening-fulltext"
session_slug: "screening-ft_prompt-v3-adjudication-changes"

# ── AI Tool ────────────────────────────────────────────────────────────────
ai_tool: "Claude"
ai_version: "claude-opus-4-7"
ai_provider: "Anthropic"

# ── Prompt Reference ───────────────────────────────────────────────────────
prompt_ref: "prompts/screening-ft_v3.md"
prompt_version: "v3"

# ── Human–AI Interaction Model ─────────────────────────────────────────────
human_verification: |
  Human (Sophie) independently adjudicated a sample of 43 full-text PDFs that
  had been classified by screening-ft v2. For each record, the human
  recorded an Agree / Disagree / Semi-agree verdict against the AI-assigned
  decision and reason tags, plus a free-text rationale on disagreements.
  The adjudication file (Adjudication.xlsx, 43 rows) was the input to this
  session. This session did not produce new classifications — it used the
  adjudication results to revise the screening-ft prompt to v3.

# ── Session Outputs ────────────────────────────────────────────────────────
outputs_summary: |
  Updated screening-ft v3 prompt with four changes derived from the
  43-paper adjudication sample of v2 outputs:
    1. Extended the Criterion 2 acceptable-measurement bullet list to
       explicitly include (a) surveillance cultures of stool / rectal swabs
       for named alert pathogens (VRE, ESBL/carbapenem-resistant organisms,
       MRSA, etc.) and (b) clinical microbiology records of stool-based
       enteric pathogen testing (C. difficile, bacterial / protozoal /
       viral stool panels). Fixes two false-`UnmeasuredGutMicrobiome`
       excludes in the sample.
    2. Added `StudyProtocol` as an Exclude reason and a new study-type
       rule for trial / protocol papers with no pilot data. Replaces the
       misleading `UnmeasuredGutMicrobiome` reason used by v2 on the
       FMT-allo and MAST trial protocol papers.
    3. Promoted `CorrectionNotice` from a v2 `NovelReason` flag to a
       standard Exclude reason in the controlled vocabulary; added a
       study-type rule row.
    4. Promoted `MycobiomeOnly` from a v2 `NovelReason` flag to a
       standard EdgeCaseReason; added an explanatory paragraph under
       Criterion 2 and a vocab table row. Defined as a catch-all for
       non-bacterial-only gut-microbiome characterization (fungal ITS,
       archaea-only, virome-only).
  Note: v3 already contained a `PossibleDataSource` edge-case override
  (added 2026-05-19, earlier in the day) addressing the Lee 2017 CDI
  disagreement in the adjudication sample. That change is documented in
  the v3 prompt changelog but not separately re-logged here.

output_files:
  - prompts/screening-ft_v3.md

# ── Screening-Specific Fields ──────────────────────────────────────────────
# This session is prompt revision, not a screening pass. Counts below
# describe the adjudication sample used as input rather than newly
# screened records.
n_records_presented: 43          # adjudication sample size
n_ai_include: null                # not retabulated this session
n_ai_exclude: null
n_ai_uncertain: null
n_human_reviewed: 43              # full adjudication
n_final_include: null             # no re-classification done this session
n_final_exclude: null

# ── Validation Fields ──────────────────────────────────────────────────────
validation_sample_n: 43
validation_sensitivity: null      # not formally computed; qualitative review
validation_specificity: null
validation_kappa: null
validation_notes: |
  Adjudication: 36 / 43 Agree, 2 Semi-agree (FMT-allo and MAST protocols —
  human accepted Exclude decision but wanted a more specific reason than
  v2's `UnmeasuredGutMicrobiome`), 3 Disagree on reason/decision:
    - Lee 2017 (Protective Factors / SCFA): v2 Excluded for
      `NoGVHDOutcome`; human wants to keep as a possible raw-data source.
      Addressed by `PossibleDataSource` override added earlier in v3.
    - "Colonization with multidrug-resistant bacteria..." (Bilinski et al.):
      v2 Excluded for `UnmeasuredGutMicrobiome`; human notes stool samples
      were collected and cultured for specific bacteria (VRE, ESBL, CRPA).
      Addressed by Criterion 2 bullet-list extension.
    - "Non-viral pathogens of infectious diarrhoea...": v2 Excluded for
      `UnmeasuredGutMicrobiome`; human notes microbiological specimen
      records were reviewed. Addressed by Criterion 2 bullet-list extension.
  Two NovelReason flags (CorrectionNotice on the Microbiota-Predict
  correction notice; MycobiomeOnly on the Zhai et al. mycobiome paper)
  were accepted by the human and folded into the standard vocabulary.
validation_file: "uploads/Adjudication.xlsx"  # source adjudication file

# ── Data Extraction Fields ─────────────────────────────────────────────────
study_id: ""
fields_extracted: []
fields_requiring_human_correction: []
extraction_notes: ""

# ── Citation Network Fields ────────────────────────────────────────────────
source_review: ""
n_references_parsed: null
n_primary_identified: null
n_reviews_identified: null
parsing_method: ""
parsing_notes: ""

# ── PRISMA-trAIce Checklist Mapping ────────────────────────────────────────
prisma_traice_items:
  - methods-tools
  - methods-human-ai
  - methods-performance

# ── Notes for Supplement ───────────────────────────────────────────────────
supplement_notes: |
  This iteration is the first formal validation pass on the screening-ft
  prompt. The 43-paper adjudication sample yielded an Agree rate of
  ~84% (36/43) on the v2 prompt before revision. Three of the four v3
  changes target specific false-negative or mis-reasoned categories
  surfaced by adjudication; one is a vocabulary-rescue (PossibleDataSource)
  protecting analytic-subcohort candidates from hard-exclude. Sensitivity /
  specificity / kappa were not formally tabulated for this sample — the
  adjudication used a free-text Agree / Disagree / Semi-agree schema
  rather than a confusion-matrix-compatible label set. A formal 2x2
  validation pass against gold-standard human labels is planned before
  the full Screening2_AI run.

# ── Decisions and Deviations ───────────────────────────────────────────────
decisions_made: |
  - Decided to extend the Criterion 2 acceptable-measurement bullet list
    rather than add a separate "common false-negatives" callout (human
    preference). Goal: keep the criterion definition self-contained.
  - Decided to use `StudyProtocol` as an Exclude reason rather than an
    EdgeCaseReason. Rationale: a protocol without pilot data cannot
    contribute to the analytic cohort regardless of how the eventual
    trial reads.
  - `MycobiomeOnly` is currently defined to subsume archaea-only and
    virome-only cases. Flagged in the v3 changelog as a tightening
    candidate if archaea/virome cases appear and merit distinct tags.
  - Did not separately log the `PossibleDataSource` override addition —
    that change pre-dated this adjudication session and is captured in
    the v3 prompt changelog.

---

## Session Summary

Adjudicated screening-ft v2 against a 43-paper sample (the
`Adjudication.xlsx` file uploaded by Sophie). Identified four classes
of fix and applied them to screening-ft v3: (1) extended Criterion 2 to
explicitly cover stool / rectal surveillance cultures and clinical
stool-pathogen microbiology records; (2) added `StudyProtocol` to the
Exclude vocabulary for trial protocols with no pilot data; (3) promoted
`CorrectionNotice` and (4) `MycobiomeOnly` from NovelReason flags to the
standard controlled vocabulary. The v3 prompt header had been
inadvertently mis-versioned during editing and was corrected back to v3
by Sophie at end of session. Next step: re-run screening-ft v3 against
the same 43-paper sample (or a larger validation sample) and tabulate a
formal confusion matrix before committing to the full Screening2_AI run.

## Records / Outputs

### Prompt Used

The prompt under revision in this session is the file:
`prompts/screening-ft_v3.md` (header now correctly reads v3).

This session did not invoke the prompt — it modified the prompt source.
For verbatim text, see the file itself; for change provenance, see the
changelog block at the top of `screening-ft_v3.md`.

### Key Decisions / Results

- 36 / 43 Agree, 2 Semi-agree, 3 Disagree on adjudicating screening-ft v2
  against human classification.
- Four v3 changes applied this session:
  - Criterion 2 bullet list extended with surveillance cultures +
    clinical stool-pathogen records.
  - `StudyProtocol` added as Exclude reason + new study-type rule.
  - `CorrectionNotice` promoted from NovelReason to vocab + new
    study-type rule.
  - `MycobiomeOnly` promoted from NovelReason to vocab + Criterion 2
    explanatory paragraph; defined to cover non-bacterial-only gut
    measurement (fungal / archaea / virome).
- `PossibleDataSource` edge-case override (added to v3 earlier in the
  day, before this session) handles the Lee 2017 CDI disagreement.
- Prompt header re-set to v3 by Sophie after a versioning slip during
  editing.

### Open Questions / Follow-up Needed

- Re-run screening-ft v3 against the 43-paper adjudication sample (or a
  larger sample) and tabulate a proper confusion matrix
  (sensitivity / specificity / Cohen's kappa) before the full
  Screening2_AI run. The current 84% Agree figure is qualitative and
  not directly comparable to PRISMA-trAIce performance reporting.
- Watch for archaea-only or virome-only papers in subsequent screening
  passes. If they appear, decide whether to keep `MycobiomeOnly` as a
  catch-all or split into distinct EdgeCaseReasons.
- Confirm that the new Criterion 2 bullets do not silently re-include
  papers that should be `EdgeCase-Exclude` for some other reason
  (e.g. autologous-only cohorts that happen to have stool culture
  surveillance — the cohort criterion should still block these).
