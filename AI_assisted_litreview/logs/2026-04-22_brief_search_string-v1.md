---
# ── BRIEF Session Log (PRISMA-trAIce) ─────────────────────────────────────
# Use for: planning, search string, eligibility decisions, protocol changes.
# Use the FULL template (session_log_template.md) for: screening, extraction, validation.

date: "2026-04-22"
stage: "search"
session_slug: "search-string-v1"

ai_tool: "Claude"
ai_version: "claude-opus-4-7"
ai_provider: "Anthropic"

prompt_ref: "prompts/search-v1.md"
prompt_verbatim: ""
prompt_version: "v1"

outputs_summary: |
  Drafted and locked Boolean search queries for PubMed/MEDLINE and
  Web of Science Core Collection, structured as four concept blocks
  (allo-HSCT population, gut microbiome, GVHD, human-species
  restriction). Populated §2.3 "Information Sources and Search
  Strategy" and Supplementary Table S1 in ScopingReview_Outline.tex.
  Graduated the search-drafting prompt from verbatim to managed
  file (prompts/search-v1.md).

decisions_made: |
  - Databases: PubMed/MEDLINE and Web of Science Core Collection
    only. Embase excluded from this protocol (access/cost).
  - Search scope: broad — any GVHD outcome (occurrence, severity,
    or timing). Time-to-event restriction applied later at the
    analytic-cohort stage, not at retrieval.
  - Population filter: human-species restriction at retrieval.
    PubMed uses humans[MeSH]; Web of Science uses a conservative
    title-only exclusion of animal-model terms because WoS lacks a
    species-indexed MeSH field. Pediatric studies are caught at
    title/abstract screening.
  - C2 concept block uses targeted multi-word microbial phrases
    rather than the bare wildcard microbi*, trading minor recall
    loss for tighter precision and a more auditable string.
  - SCT added as a standalone acronym to C1 (reviewer suggestion).
  - Narrative/clinical reviews retained in the retrieval (required
    for Tier 4 citation network analysis); the eligibility criterion
    "exclude narrative reviews" refers to primary-evidence
    inclusion, not retrieval.
  - Search strategy not peer-reviewed by a medical librarian;
    disclosed as a PRISMA-trAIce D1 limitation in §2.3. Decision
    confirmed 2026-04-22: no Eccles Library consult planned.
  - PubMed human-species filter: confirmed to use humans[MeSH]
    (not humans[Filter]). Trade-off accepted: MeSH-indexed records
    only; ahead-of-print records may be missed at retrieval but
    would be captured on a re-run closer to submission if needed.
  - Prompt graduated to managed file prompts/search-v1.md; all
    future search-related sessions should reference this prompt.

prisma_traice_items:
  - methods-tools
  - methods-human-ai
  - discussion-limitations

---

## Summary

Conversational drafting session. The reviewer (S.H.) specified four
scoping parameters via a multiple-choice exchange (broad search,
human-species filter, two databases, AI-drafts / human-refines
workflow). Claude proposed an initial query design; the reviewer
iterated once, adding SCT to C1 and choosing precise microbial
phrases over the bare wildcard for C2. The resulting queries were
written into the manuscript and the prompt was saved to
prompts/search-v1.md.

## Open Questions

- Exact search execution date is TBD; when executed, update the
  red-flagged placeholders in §2.3 and both panels of Table S1,
  and record retrieval counts (n) in each line of Table S1.
- Embase remains excluded under current University of Utah access;
  if access changes later, this prompt will need a v2 with an
  Emtree-mapped translation.
