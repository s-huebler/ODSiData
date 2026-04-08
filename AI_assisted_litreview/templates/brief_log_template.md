---
# ── BRIEF Session Log (PRISMA-trAIce) ─────────────────────────────────────
# Use for: planning, search string, eligibility decisions, protocol changes.
# Use the FULL template (session_log_template.md) for: screening, extraction, validation.

date: "YYYY-MM-DD"
stage: ""           # planning | search | screening-ta | screening-ft |
                    # extraction | citation-network | validation | other
session_slug: ""

ai_tool: "Claude"
ai_version: ""      # e.g. claude-sonnet-4-6
ai_provider: "Anthropic"

# Use prompt_ref OR prompt_verbatim — not both
prompt_ref: ""                 # path to prompts/<stage>_v<N>.md, if applicable
prompt_verbatim: |             # paste prompt, or "Conversational session — no structured prompt."
  [prompt or note]
prompt_version: ""

outputs_summary: |             # What did this session produce?
  [1-3 sentences]

decisions_made: |              # Protocol decisions or changes made
  [bullet list, or "None — discussion only."]

prisma_traice_items: []        # Which PRISMA-trAIce items this session affects:
                               # methods-tools | methods-human-ai | methods-performance |
                               # results-flow | discussion-limitations | introduction | other

---

## Summary

<!-- 2–4 sentences. What was discussed, what was decided, what is next. -->

## Open Questions

- 
