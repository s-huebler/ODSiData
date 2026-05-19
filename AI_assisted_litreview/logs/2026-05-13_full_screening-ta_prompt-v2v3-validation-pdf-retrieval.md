---
# ── PRISMA-trAIce Session Log ──────────────────────────────────────────────

date: "2026-05-13"
stage: "screening-ta"
session_slug: "prompt-v2v3-validation-pdf-retrieval"

# ── AI Tool ────────────────────────────────────────────────────────────────
ai_tool: "Claude"
ai_version: "unknown (session conducted offline / by human)"
ai_provider: "Anthropic"

# ── Human–AI Interaction Model ─────────────────────────────────────────────
human_verification: |
  All work in this log was conducted by the human reviewer (S.H.) independently,
  without AI assistance in the session itself. This log was created post-hoc
  on 2026-05-13 to record completed milestones. AI was used only for
  classification (applying the prompts); all review, adjudication, and
  PDF-retrieval decisions were human.

# ── Prompt Reference ───────────────────────────────────────────────────────
prompt_ref: "prompts/screening-ta_v3.md"
prompt_version: "v3"

---

## Session Summary

This log records three completed milestones that followed the v1 validation
session (logged 2026-05-06):

1. **Prompt v2 validation** — screened 12 papers (Screen3_classified); 2 human–AI
   disagreements traced to an overly narrow treatment of "training" in the v2 rubric.
   Resolved by updating the prompt to v3, which encodes allowable generalizations.

2. **Prompt v3 validation** — screened 10 papers (Screen4_classified); 0 disagreements.
   v3 is considered validated and ready for full-corpus application.

3. **Full-corpus run + PDF retrieval** — v3 applied to all files; 481 papers passed
   first-pass screening. PDF retrieval was completed via ReadCube location data,
   manual open-source search, ILL requests, and triage of unresolvable records.

---

## Records / Outputs

### v2 Validation (Screen3_classified, n=12)

AI classified all 12 records using prompt v2. Human (S.H.) reviewed independently
and compared labels.

| Outcome | Count |
|---------|-------|
| Agreement | 10 |
| Disagreement | 2 |
| Total | 12 |

Raw agreement (Po): 10/12 = 0.833  
Cohen's κ: not precisely computable without full confusion matrix; estimated
range ≈ 0.49–0.63 given typical screening marginals (majority-Include distribution).

**Disagreement analysis:** Both disagreements stemmed from the same root cause —
prompt v2's definition of "training" was interpreted too narrowly by the AI,
causing it to exclude papers that presented generalizable methods or used
populations that could be considered broadly representative. Human reviewer
judged these as includable.

**Resolution:** Prompt updated to v3, adding explicit language permitting
allowable generalizations in the training/exposure criterion. See
`prompts/screening-ta_v3.md` for the full diff.

### v3 Validation (Screen4_classified, n=10)

AI classified all 10 records using prompt v3. Human (S.H.) reviewed and compared.

| Outcome | Count |
|---------|-------|
| Agreement | 10 |
| Disagreement | 0 |
| Total | 10 |

Raw agreement (Po): 10/10 = 1.0  
Cohen's κ: 1.0 (perfect agreement)

v3 is validated. No further prompt revisions required before full-corpus
application.

### Full-Corpus Screening Run

Prompt v3 was applied to all files in the corpus. Result: **481 papers** passed
first-pass title/abstract screening (Include label).

### PDF Retrieval (n=481)

PDF location was attempted for all 481 papers. Summary:

| Status | Count |
|--------|-------|
| Located via ReadCube PDF location | 449 |
| Manually located (open-source / OA) | 10 |
| **Total with full text in hand** | **459** |
| Abstract or announcement only (no affiliated full text exists) | 3 |
| Title could not be reliably translated / located | 3 |
| Requested via interlibrary loan (ILL) | 16 |
| **Total accounted for** | **481** |

Notes on unresolved records:
- The 3 abstract/announcement records were confirmed to have no linked full-text
  article; they will be recorded as "no full text available" in the PRISMA flow.
- The 3 untranslatable-title records could not be matched to a retrievable PDF
  with sufficient confidence; these will be flagged for manual follow-up or
  exclusion at full-text screening.
- The 16 ILL requests are pending; PDFs will be added to the corpus as they arrive.

---

## Screening-Specific Fields

n_records_presented: 481  
n_include_firstpass: 481  
n_fulltext_retrieved: 459  
n_fulltext_pending_ill: 16  
n_fulltext_unavailable: 6  (3 abstract-only + 3 untranslatable)

## Validation Summary

| Round | Prompt | N | Agreements | Disagreements | Po | κ |
|-------|--------|---|------------|---------------|-----|---|
| Screen3 | v2 | 12 | 10 | 2 | 0.833 | ~0.49–0.63 (est.) |
| Screen4 | v3 | 10 | 10 | 0 | 1.000 | 1.000 |

## Output Files

- `AI_assisted_litreview/prompts/screening-ta_v2.md` (prior version; superseded)
- `AI_assisted_litreview/prompts/screening-ta_v3.md` (validated; applied to full corpus)
- `AI_assisted_litreview/Prompt_Gen_Training/Screen3_classified` (v2 validation set)
- `AI_assisted_litreview/Prompt_Gen_Training/Screen4_classified` (v3 validation set)
- Full-corpus Include list (481 records) — location TBD / confirm path

## PRISMA-trAIce Checklist Mapping

- methods-tools
- methods-human-ai
- methods-performance
- results-screening

## Decisions Made

- v2 disagreements attributed to overly narrow "training" definition; resolved by
  encoding allowable generalizations in v3.
- v3 accepted as the production screening prompt after 10/10 agreement on Screen4.
- 16 papers sent to ILL; will be added to full-text corpus as PDFs are received.
- 3 abstract-only and 3 untranslatable-title records will be recorded as
  "no full text available" / "unable to locate" in the PRISMA flow diagram.

## Open Questions

- Confirm the file path / filename for the 481-paper Include list produced by the
  full-corpus run.
- Determine how to handle the 3 untranslatable-title records at full-text screening
  (exclude or flag for expert review).
- Track ILL return status; update retrieval counts when PDFs arrive.
- Decide whether abstract-only records should be excluded now or carried forward
  to full-text screening stage for formal exclusion with reason code.

---
