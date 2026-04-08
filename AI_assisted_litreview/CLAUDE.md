# AI-Assisted Literature Review — Logging Rules

This directory tracks all AI-assisted work for the scoping review:
**"Gut Microbiome and Time-to-GVHD in Adult Allo-SCT Recipients"**

All records are structured for synthesis into the PRISMA-trAIce supplement.

---

## AUTOMATIC LOGGING RULE

**Trigger:** Any conversation that involves one or more of the following activities:
- Discussing, refining, or testing search strings
- Screening decisions (title/abstract or full-text)
- Data extraction from any paper
- Citation network construction, parsing, or analysis
- Discussing eligibility criteria or inclusion/exclusion decisions
- Evaluating AI screening performance (validation, sensitivity/specificity)
- Reviewing or updating the evidence table
- Any other step that will be reported in the Methods or Supplement of the paper

**Action:** At the END of any such conversation, before finishing, create a new session
log file in `AI_assisted_litreview/logs/` using the template at
`AI_assisted_litreview/templates/session_log_template.md`.

**File naming convention:** `YYYY-MM-DD_<stage>_<brief-slug>.md`
Examples:
- `2026-04-08_planning_outline-and-goals.md`
- `2026-04-15_screening_title-abstract-batch1.md`
- `2026-04-22_extraction_bergeron2017.md`

**Important:** If a conversation spans multiple stages, create one log file per stage,
or clearly section the log by stage. Do NOT aggregate weeks of work into a single log.

---

## LOG FORMAT REQUIREMENTS

Every log file must use the template exactly. The frontmatter fields map directly
to PRISMA-trAIce checklist items as noted in the template. Incomplete logs cannot
be synthesized into the supplement.

**Mandatory fields** (PRISMA-trAIce items marked M):
- `date`, `stage`, `ai_tool`, `ai_version`, `prompt_ref` or `prompt_verbatim`
- `human_verification` description
- `outputs_summary`
- `prisma_traice_items` (list which checklist items this session addresses)

**Required for screening sessions:**
- `n_records_presented`
- `n_ai_include`, `n_ai_exclude`, `n_ai_uncertain`
- `human_review_of_uncertain` (always required — AI uncertain cases must go to human)
- `validation_sample` (if this is a validation session: n, sensitivity, specificity, kappa)

**Required for data extraction sessions:**
- `study_id` (BioProject accession or author-year)
- `fields_extracted` (list)
- `fields_requiring_human_correction` (list — even if empty, state "none identified")

---

## PROMPT MANAGEMENT

Whenever a new prompt is created or an existing prompt is modified:
1. Save the verbatim prompt to `AI_assisted_litreview/prompts/<stage>_v<N>.md`
2. Record the version in the session log under `prompt_ref`
3. Document the reason for any modification

Prompt versioning ensures that the supplement can report exactly which prompt
was used at each stage of the review.

---

## VALIDATION RECORDS

Whenever AI screening is validated against a human gold standard:
1. Save the comparison table to `AI_assisted_litreview/validation/validation_<date>.csv`
   - Columns: `record_id`, `ai_decision`, `human_decision`, `agreement`
2. Record sensitivity, specificity, and kappa in the session log
3. Update `AI_assisted_litreview/validation/performance_summary.md`

---

## SYNTHESIS INSTRUCTIONS

At the end of the review (before submission), the logs directory will be synthesized
into the PRISMA-trAIce supplement tables as follows:

| Supplement Table | Synthesized from |
|------------------|-----------------|
| Table S3: PRISMA-trAIce checklist | All logs — `prisma_traice_items` fields |
| Table S4: AI prompts documentation | `prompts/` directory |
| Table S4 (validation): AI performance | `validation/performance_summary.md` |
| Methods §2.3 (AI use): human–AI interaction | All screening logs |

To generate a synthesis draft, ask Claude to:
> "Synthesize the PRISMA-trAIce supplement tables from all logs in
> AI_assisted_litreview/logs/ and the prompts/ and validation/ directories."
