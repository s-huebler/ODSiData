---
date: "2026-04-08"
stage: "planning"
session_slug: "outline-goals-ai-methodology"

ai_tool: "Claude"
ai_version: "claude-sonnet-4-6"
ai_provider: "Anthropic"

prompt_ref: ""
prompt_verbatim: |
  Conversational planning session — no single structured prompt. Sophie described
  the paper goals, venue, and design questions; Claude synthesized recommendations
  and generated the paper outline and planning documents.
prompt_version: "n/a — planning session"

human_verification: |
  Full human-in-the-loop planning session. All recommendations reviewed and
  approved by Sophie before documents were finalized. Sophie answered four
  structured clarifying questions (AskUserQuestion) covering venue, reference map
  format, baseline definition, and review methodology. No automated screening or
  extraction occurred.

outputs_summary: |
  1. Paper goals formalized into three interlocking objectives (therapeutic pipeline,
     evidence mapping, time-to-GVHD analytic cohort).
  2. Methodology decisions documented: PRISMA-ScR + PRISMA-trAIce, target venue
     (TCT/Blood Advances), baseline framing as a finding.
  3. Full paper outline drafted (Introduction through Supplementary).
  4. Five figure placeholders designed (PRISMA flow, citation network, sample flow,
     cohort composition, beta diversity PCoA panels).
  5. Phased action items documented across five phases.
  6. PAPER_PLAN.md and ScopingReview_Outline.tex created in manuscript/.
  7. PRISMA flow diagram updated to PRISMA-trAIce format (AI and human steps
     tracked separately, validation note box added).
  8. AI_assisted_litreview/ directory scaffolded with CLAUDE.md logging rules,
     session log template, and performance summary tracker.

output_files:
  - manuscript/PAPER_PLAN.md
  - manuscript/ScopingReview_Outline.tex
  - AI_assisted_litreview/CLAUDE.md
  - AI_assisted_litreview/templates/session_log_template.md
  - AI_assisted_litreview/validation/performance_summary.md

n_records_presented: null
n_ai_include: null
n_ai_exclude: null
n_ai_uncertain: null
n_human_reviewed: null
n_final_include: null
n_final_exclude: null

validation_sample_n: null
validation_sensitivity: null
validation_specificity: null
validation_kappa: null
validation_notes: "No screening performed — planning session only."
validation_file: ""

study_id: ""
fields_extracted: []
fields_requiring_human_correction: []
extraction_notes: ""

source_review: ""
n_references_parsed: null
n_primary_identified: null
n_reviews_identified: null
parsing_method: ""
parsing_notes: ""

prisma_traice_items:
  - methods-tools
  - methods-human-ai
  - introduction

supplement_notes: |
  This session established the AI methodology framework. Key decisions for the
  PRISMA-trAIce supplement:
  - AI tool: Claude (claude-sonnet-4-6, Anthropic)
  - AI will be used for title/abstract screening (first-pass), full-text flagging,
    and data extraction first-pass
  - All AI screening decisions require human verification (includes + uncertain cases)
  - Validation will be performed on a ~10% random gold-standard sample
  - Citation network will be constructed computationally (R/Python), not by LLM inference
  - All prompts will be versioned and saved in AI_assisted_litreview/prompts/
  - Reference: PRISMA-trAIce (https://ai.jmir.org/2025/1/e80247)

decisions_made: |
  1. Adopt PRISMA-trAIce framework for all AI use reporting.
  2. Target venue: Transplantation and Cellular Therapy or Blood Advances (primary);
     Microbiome/ISME J (stretch).
  3. Baseline = closest sample to day 0 of transplant; frame heterogeneity as a finding.
  4. PRISMA-ScR followed but protocol not pre-registered.
  5. Citation network is a computational/code task, not LLM inference — different
     reporting requirements apply (reproducibility via GitHub, not PRISMA-trAIce AI tool disclosure).

---

## Session Summary

This was an initial planning session to formalize the paper goals, scope, and methodology for the scoping review. Sophie described the three-part argument (therapeutic pipeline → microbial targets known → more research needed), the citation echo-chamber problem she identified, and the analytic sub-cohort work in progress. Claude synthesized these into a structured paper outline, figure plan, and phased action items, then generated two deliverable files (PAPER_PLAN.md, ScopingReview_Outline.tex). A second session covered AI-assisted review guidelines, leading to PRISMA-trAIce adoption and updates to both documents. This session log directory was then scaffolded. No screening or extraction occurred.

## Key Decisions / Results

- Paper goals: three-part therapeutic-evidence-gap argument
- Novel contribution: citation network analysis (amplification ratios)
- Figure 1 (PRISMA flow) modified to PRISMA-trAIce standard with separate AI/human exclusion tracking
- New §2.3 "Use of Artificial Intelligence" added to Methods outline
- New Supplementary Tables S3 (PRISMA-trAIce checklist) and S4 (prompt documentation) added

## Open Questions / Follow-up Needed

- Sophie to confirm target journal before formatting Methods section to journal style
- Baseline variable in analytic cohort code needs formal documentation (currently hardcoded in Create_Analytic_Cohort.qmd)
- Search string not yet drafted — next priority action item (Phase 1)
- Overleaf sync workflow: `workflow_dispatch` trigger added to `overleaf-push.yml`; needs to be pushed to main
