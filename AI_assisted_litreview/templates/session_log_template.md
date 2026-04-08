---
# ── PRISMA-trAIce Session Log ──────────────────────────────────────────────
# Copy this template to logs/YYYY-MM-DD_<stage>_<slug>.md and fill in ALL fields.
# Fields marked (M) are MANDATORY per PRISMA-trAIce. Others are required
# when applicable to the session type.

date: "YYYY-MM-DD"                      # (M) Date of session
stage: ""                               # (M) One of: planning | search | screening-ta |
                                        #     screening-fulltext | extraction | citation-network |
                                        #     synthesis | validation | other
session_slug: ""                        # Short descriptor for filename, e.g. "title-abstract-batch1"

# ── AI Tool ────────────────────────────────────────────────────────────────
ai_tool: "Claude"                       # (M) Tool name
ai_version: ""                          # (M) Model version, e.g. "claude-sonnet-4-6"
ai_provider: "Anthropic"               # (M)

# ── Prompt Reference ───────────────────────────────────────────────────────
prompt_ref: ""                          # (M) Path to prompt file, e.g. prompts/screening-ta_v1.md
                                        #     OR use prompt_verbatim below for one-off prompts
prompt_verbatim: |                      # (M if no prompt_ref) Paste exact prompt used
  [paste prompt here]
prompt_version: ""                      # Version number if using a managed prompt file

# ── Human–AI Interaction Model ─────────────────────────────────────────────
human_verification: |                   # (M) Describe exactly what human review was performed
  [Describe: did human review all AI decisions, or only uncertain/include?
   Did human independently screen a subset? Were disagreements adjudicated?]

# ── Session Outputs ────────────────────────────────────────────────────────
outputs_summary: |                      # (M) What did this session produce?
  [Describe outputs: decisions made, records screened, data extracted, etc.]

output_files: []                        # List any files created, e.g.:
                                        # - logs/screening_batch1_results.csv
                                        # - validation/validation_2026-04-15.csv

# ── Screening-Specific Fields (required for stage: screening-ta or screening-fulltext)
n_records_presented: null              # Number of records AI was shown
n_ai_include: null                     # Number AI recommended including
n_ai_exclude: null                     # Number AI recommended excluding
n_ai_uncertain: null                   # Number AI flagged as uncertain
n_human_reviewed: null                 # Number reviewed by human (should = include + uncertain)
n_final_include: null                  # Final count after human review
n_final_exclude: null                  # Final count after human review

# ── Validation Fields (required when a human gold standard was evaluated)
validation_sample_n: null              # Size of validation sample
validation_sensitivity: null           # AI sensitivity vs. human gold standard
validation_specificity: null           # AI specificity vs. human gold standard
validation_kappa: null                 # Cohen's kappa
validation_notes: ""                   # Any notes on discrepancies or borderline cases
validation_file: ""                    # Path to validation CSV, e.g. validation/validation_2026-04-15.csv

# ── Data Extraction Fields (required for stage: extraction)
study_id: ""                           # BioProject accession or AuthorYear, e.g. "Bergeron2017"
fields_extracted: []                   # List of fields AI extracted, e.g.:
                                       # - study_design
                                       # - n_patients
                                       # - gvhd_outcome_type
fields_requiring_human_correction: []  # Fields where AI was wrong or uncertain (empty list if none)
extraction_notes: ""                   # Any issues, ambiguities, or judgment calls

# ── Citation Network Fields (required for stage: citation-network)
source_review: ""                      # Which review paper was processed, e.g. "Hong2021"
n_references_parsed: null             # Total references in that paper
n_primary_identified: null            # References identified as primary empirical studies
n_reviews_identified: null            # References identified as reviews/narratives
parsing_method: ""                    # e.g. "R script: citation_network.R"
parsing_notes: ""

# ── PRISMA-trAIce Checklist Mapping ────────────────────────────────────────
# List which PRISMA-trAIce items this session contributes evidence for.
# Items: title | abstract | introduction | methods-tools | methods-human-ai |
#        methods-performance | results-flow | results-performance |
#        discussion-limitations | other
prisma_traice_items: []                # (M) e.g. [methods-tools, methods-human-ai, methods-performance]

# ── Notes for Supplement ───────────────────────────────────────────────────
supplement_notes: |                    # Any text that should be quoted or summarized in the supplement
  [Notes here]

# ── Decisions and Deviations ──────────────────────────────────────────────
decisions_made: |                      # Document any judgment calls or protocol deviations
  [Describe here, or "None — followed protocol as specified."]

---

## Session Summary

<!-- Write a 2–5 sentence plain-language summary of what happened in this session,
     what was decided, and what the next step is. This is what will be read during
     synthesis to understand the session without parsing the frontmatter. -->

[Summary here]

## Records / Outputs

<!-- Paste relevant outputs here: screening decisions, extracted data, prompts used
     inline, notes on specific papers, etc. Use subsections as needed. -->

### Prompt Used

```
[Paste verbatim prompt if not in a separate file]
```

### Key Decisions / Results

<!-- Bullet list of the most important outcomes of this session -->

- 

### Open Questions / Follow-up Needed

<!-- Things that need to be revisited, clarified, or escalated to human review -->

- 
