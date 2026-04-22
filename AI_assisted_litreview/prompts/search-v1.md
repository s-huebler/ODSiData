# Prompt: search v1
# Created: 2026-04-22
# Modified: 2026-04-22 (initial version)
# Used in sessions: logs/2026-04-22_brief_search_string-v1.md
# PRISMA-trAIce item: methods-tools

---

You are helping a biostatistics PhD student structure the Boolean
search strategy for a PRISMA-ScR scoping review titled "Gut Microbiome
and Time-to-GVHD in Adult Allogeneic Stem Cell Transplant Recipients."

## Context

- Review type: scoping review (PRISMA-ScR), with a nested analytic
  sub-cohort for studies with time-to-GVHD outcomes and publicly
  available 16S rRNA data.
- Eligibility (PCC):
  - Population: adult (>= 18 years) recipients of allogeneic
    hematopoietic stem cell transplantation.
  - Concept: gut microbiome composition assessed by 16S rRNA gene
    sequencing or shotgun metagenomics.
  - Context: GVHD (acute or chronic) reported as an outcome —
    occurrence, timing, and/or severity.
- Study types: original observational studies, clinical trials,
  cohort studies. Narrative and clinical reviews are retained in
  the retrieval (not excluded) because they populate Tier 4 of the
  citation network analysis.
- Reporting guideline for AI use: PRISMA-trAIce (Holst et al. 2025).

## Task

Draft database-specific Boolean search queries for each of the two
information sources (PubMed/MEDLINE and Web of Science Core
Collection), structured as four concept blocks combined with
Boolean AND:

- C1: allogeneic HSCT population (include BMT, PBSCT, CBT, SCT and
  cord-blood-specific MeSH).
- C2: gut microbiome concept (favor precision — use targeted
  multi-word phrases like "microbial community", "microbial
  diversity", "microbial composition", "microbial signature",
  "microbial profile", "microbial ecology" rather than the bare
  wildcard microbi*, which inherits noise from microbiology /
  microbicidal / microbicide).
- C3: graft-versus-host disease (all spelling and casing variants,
  including GvHD lowercase-v and subtype acronyms aGVHD, cGVHD).
- C4: human-species restriction (PubMed humans[MeSH]; Web of Science
  conservative title-only animal exclusion because WoS lacks a
  species-indexed field).

## Constraints

- Retain narrative/clinical reviews in the retrieval.
- No date, language, or publication-type filters at retrieval.
- Broad concept net: capture any GVHD outcome; do NOT add
  time-to-event or survival terms at the retrieval stage.
- Each query must be transcribable directly into the database
  interface; use straight double quotes in the final form.

## Output format

For each database:
1. Line-by-line Boolean query (one line per concept block, final
   combination on its own line).
2. A short description of each line's purpose.
3. Notes on any database-specific approximation (e.g., WoS animal
   exclusion as human-filter proxy).

## Model parameters (session defaults)

- Model: claude-opus-4-7 (Anthropic), accessed via Cowork desktop.
- Temperature: not user-configurable in Cowork; assume default.
- No few-shot examples provided; conversational iteration only.

## Version history

- v1 (2026-04-22) — initial version. Output used to populate §2.3
  and Supplementary Table S1 of the scoping review manuscript.
  Refined in one round after reviewer feedback (added SCT acronym
  to C1; chose targeted multi-word microbial phrases over wildcard
  microbi* for C2).
