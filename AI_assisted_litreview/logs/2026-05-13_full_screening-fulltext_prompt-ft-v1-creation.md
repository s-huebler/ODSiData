---
# ── PRISMA-trAIce Session Log ──────────────────────────────────────────────

date: "2026-05-13"
stage: "screening-fulltext"
session_slug: "prompt-ft-v1-creation"

# ── AI Tool ────────────────────────────────────────────────────────────────
ai_tool: "Claude"
ai_version: "claude-opus-4-7"
ai_provider: "Anthropic"

# ── Prompt Reference ───────────────────────────────────────────────────────
prompt_ref: "prompts/screening-ft_v1.md"
prompt_verbatim: ""
prompt_version: "v1"

# ── Human–AI Interaction Model ─────────────────────────────────────────────
human_verification: |
  No AI screening was performed in this session. The session was prompt
  engineering and wrapper-script design. Human (Sophie) had previously
  classified a 9-paper training subset by reading the full PDFs and recorded
  reasoning in a `Human Reasoning` column of
  `Screening2_AI/Prompt_Gen_V1/V1_output_human.csv`. The AI's role was to:
  (1) read all 9 training PDFs / reasoning entries; (2) abstract patterns
  from the reviewer's prose justifications; (3) propose a formalized
  screening prompt; (4) iterate based on reviewer feedback on prompt
  economy and clarity. Two rounds of reviewer feedback were applied
  (inline citekey examples → removed; worked-examples table and version
  history section → removed) before the prompt was accepted.

# ── Session Outputs ────────────────────────────────────────────────────────
outputs_summary: |
  Three artifacts produced:
  (1) `prompts/screening-ft_v1.md` — managed full-text screening prompt
      for second-pass classification of ~466 PDFs into
      Include / Exclude / EdgeCase-Include / EdgeCase-Exclude with a
      controlled reason-tag vocabulary.
  (2) `scripts/bash/screen_secondpass.sh` — resumable bash wrapper that
      invokes `claude -p` once per PDF, tracks completion via a sidecar
      `.processed.log`, and captures unmatched-PDF notices for manual
      reconciliation.
  (3) Updated `AI_assisted_litreview/CLAUDE.md` — added a
      "Second-Pass Screening Workflow" section documenting inputs,
      outputs, classification labels, tag schema, execution model, and
      rationale for the tags-in-CSV design.

  No paper-level screening decisions were made in this session.

output_files:
  - "prompts/screening-ft_v1.md"
  - "scripts/bash/screen_secondpass.sh"
  - "AI_assisted_litreview/CLAUDE.md"  # modified, not newly created

# ── Screening-Specific Fields ──────────────────────────────────────────────
# Not applicable — no screening was performed this session. The prompt
# created here will be validated against a 2nd training subset (V2) in a
# subsequent session.
n_records_presented: null
n_ai_include: null
n_ai_exclude: null
n_ai_uncertain: null
n_human_reviewed: null
n_final_include: null
n_final_exclude: null

# ── Validation Fields ──────────────────────────────────────────────────────
# Pending — V2 validation has not yet been run.
validation_sample_n: null
validation_sensitivity: null
validation_specificity: null
validation_kappa: null
validation_notes: ""
validation_file: ""

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

# ── Notes for Supplement ───────────────────────────────────────────────────
supplement_notes: |
  This session produced the v1 managed prompt for full-text screening
  (Table S4 — Prompt Documentation). The prompt's eligibility criteria
  were distilled from a 9-paper reviewer-labeled training set; the
  worked examples that motivated specific rules will appear in the
  Records section below, not in the runtime prompt body.

  Key formalizations to document in Methods §2.3 (Human–AI interaction):
  - "Any subset meets ALL criteria" rule for inclusion.
  - Humanized mouse models do NOT satisfy the human cohort criterion.
  - Non-gut microbiome sites (blood/bacteremia, vaginal, oral, skin, lung)
    do NOT satisfy the gut-microbiome-measured criterion on their own.
  - Non-English full text always routes to an edge-case bucket with
    reason `Language`.
  - Microbiome-targeting interventions without microbiome measurement →
    `EdgeCase-Exclude` with `UnmeasuredGutMicrobiome`.
  - Narrative reviews require substantive (not passing) engagement with
    both GVHD and the gut microbiome.

# ── Decisions and Deviations ──────────────────────────────────────────────
decisions_made: |
  Several protocol decisions locked in during this session:

  1. PDF↔CSV matching strategy: DOI extracted from PDF text → PMID
     fallback → title fallback. The PDF filenames exported by Papers
     (e.g. `Nat. Med.-2017.pdf`, `1954699.pdf`) are not reliably unique
     and do not match any CSV column directly.

  2. Reason-tag vocabulary model: hybrid. The prompt seeds a closed
     controlled list of 12 reason fragments (UnmeasuredGutMicrobiome,
     NonHuman, AutologousOnly, WrongCohort, NoGVHDOutcome,
     PassingMentionOnly, NoFullText, Language, CaseStudy,
     GVHDNotPrimary, DiversityMetricsOnly, SubsetOnly) but instructs
     Claude to emit a literal `SecondPassAI-NovelReason` flag tag when
     a paper does not fit any existing fragment, so novel reasons
     surface for manual review rather than getting scattered through
     the output.

  3. Tag format: normalized to `SecondPassAI-` (uppercase AI) with
     hyphen-separated bucket names (e.g. `SecondPassAI-EdgeCase-Include`,
     `SecondPassAI-ExcludeReason-UnmeasuredGutMicrobiome`). This
     differs from Sophie's V1 examples which used `SecondPassAi-` and
     `EdgeCaseInclude` (no hyphen). The V2 training run will use the
     normalized format.

  4. Output schema: a new CSV mirroring the Papers export schema, with
     classification + reason tags appended to the existing `Tags`
     column (comma-separated, preserving any pre-existing Papers tags
     like `Prompt Gen`, `Screen1`, `Screen2.1`). Chosen because Papers
     (ReadCube) builds sublists directly from the `Tags` column, so
     the second-pass output is re-importable for the next manual stage.

  5. Execution model: one PDF per `claude -p` invocation, wrapped in a
     bash loop. Resumability via a `.processed.log` sidecar file
     adjacent to the output CSV. PDFs are marked processed only after
     a clean `claude` exit (rc=0), so token-limit-induced failures
     leave the PDF un-marked and a rerun automatically retries it.
     Unmatched PDFs (no CSV row found by DOI/PMID/title) are written
     to a separate `.unmatched.log` for manual reconciliation.

  6. Prompt economy: after a first draft, two reviewer-requested cuts
     were applied to keep the runtime prompt lean.
     - Removed all inline `(Example: <citekey> → ...)` parentheticals.
       Claude cannot open the citekeyed PDFs at runtime, so the
       citekeys added tokens without signal. The rules in the prose
       were already stating the pattern.
     - Removed the 9-row worked-examples table and the version-history
       section. The table duplicated rules already in the prose;
       version history is documentation for the maintainer and belongs
       in this log, not in the runtime prompt body.
     Final runtime prompt is ~5KB (excluding the header comment block).

  Open: the v1 prompt has not yet been validated against the V2
  training subset (`Screening2_AI/Prompt_Gen_V2/V2_Papers`). Validation
  will be a separate FULL log entry once V2_input.csv is exported and
  the loop has been run.

---

## Session Summary

Designed and implemented the v1 full-text screening prompt
(`prompts/screening-ft_v1.md`) plus a resumable bash wrapper
(`scripts/bash/screen_secondpass.sh`) for second-pass classification of
~466 candidate PDFs from `Screening2_AI/Exported_PDFs/`. Eligibility
rules, the reason-tag controlled vocabulary, and the
PDF↔CSV-row matching strategy were distilled from a 9-paper
reviewer-labeled training subset in
`Screening2_AI/Prompt_Gen_V1/V1_output_human.csv`. Also added a
"Second-Pass Screening Workflow" section to
`AI_assisted_litreview/CLAUDE.md` so this context auto-loads for future
sessions in the directory. No paper-level screening decisions were made
this session. Next step: run the wrapper against the V2 training subset
to validate prompt behavior before launching the full 466-PDF screen.

## Records / Outputs

### Prompt Used

The prompt for this session was conversational (no managed prompt
file). The session produced a new managed prompt file
(`prompts/screening-ft_v1.md`) which is referenced via `prompt_ref` in
this log's frontmatter and which will be used in subsequent screening
sessions.

### Key Decisions / Results

- New managed prompt `prompts/screening-ft_v1.md` created (v1).
- New bash wrapper `scripts/bash/screen_secondpass.sh` created.
- `AI_assisted_litreview/CLAUDE.md` updated with the second-pass
  workflow section.
- Eligibility-criteria formalizations (any-subset rule; non-human
  cohort rule; non-gut-site-alone rule; non-English auto-edge-case
  rule; FMT-without-measurement → EdgeCase-Exclude rule) added to the
  prompt with explicit prose, distilled from reviewer reasoning on 9
  training papers.
- Controlled reason-tag vocabulary seeded with 12 fragments plus a
  `SecondPassAI-NovelReason` flag for unanticipated reasons.
- Tag format normalized to `SecondPassAI-` + hyphenated buckets.

### V1 Training Set (provenance for the prompt rules)

The following 9 papers were classified by Sophie (reading the full
PDFs) and their reasoning was used to derive the prompt's rules. Listed
here for audit-trail purposes; not included in the runtime prompt.

| Citekey                       | Decision          | Reason(s)                        | Pattern contributed to prompt |
|-------------------------------|-------------------|----------------------------------|-------------------------------|
| severyn2022microbiota-399     | Include           | —                                | Canonical positive example. |
| legoff2017eukaryotic-c5f      | Include           | —                                | Virome-focused paper still includable if 16S done and named gut taxa reported. |
| 大吾2015腸管gvhdのkey-5e9     | EdgeCase-Include  | Language                         | Non-English → automatic edge-case bucket. |
| gardner2022safety-8e8         | Exclude           | UnmeasuredGutMicrobiome          | Blood bacteremia ≠ gut microbiome. |
| araújo2025vulvar-544          | Exclude           | UnmeasuredGutMicrobiome          | Vaginal microbiome ≠ gut microbiome (organ-specific GVHD outcome itself is fine). |
| bu2023human-bf0               | Exclude           | NonHuman                         | Humanized mouse models do not satisfy the human cohort criterion despite "Human" in the title. |
| finotto2025fecal-403          | EdgeCase-Exclude  | UnmeasuredGutMicrobiome, CaseStudy | FMT case study targets gut microbiome but does not measure it. |
| júnior2025unraveling-3dd      | Include           | —                                | Canonical positive review example. |
| leardini2024levofloxacin-894  | Include           | —                                | Subset rule: 50-patient 16S subgroup inside a 144-patient cohort qualifies the whole paper. |

### Open Questions / Follow-up Needed

- Validate v1 prompt against the V2 training subset
  (`Screening2_AI/Prompt_Gen_V2/V2_Papers`). Requires
  `V2_input.csv` to be exported from Papers first.
- Decide whether to score V2 with confusion-matrix-style metrics
  (sensitivity / specificity on the Include vs. not-Include axis,
  plus agreement on reason tags) or qualitative review only.
- The V1 reviewer-labeled CSV used the unnormalized tag format
  (`SecondPassAi-EdgeCaseInclude` with no hyphen and lowercase 'i').
  Decide whether to retro-edit V1 to the normalized format or leave
  as a known minor discrepancy in the training data.
- The `Input481.csv` Papers export does not yet exist. Sophie will
  generate it from Papers before launching the full 466-PDF screen.
- After V2 validation passes, the wrapper run on the full 466 PDFs
  will be a FULL log session of its own.
