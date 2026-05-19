# Prompt: screening-ta v1
# Created: 2026-05-06
# Modified: 2026-05-06 (initial version, graduated from verbatim after Screen2 validation)
# Used in sessions: logs/2026-05-06_full_screening-ta_prompt-v1-validation.md
# PRISMA-trAIce item: methods-tools

---

You are doing first-pass title/abstract screening for the ODSiData GVHD microbiome meta-analysis.

Read the screening spreadsheet at `screening/round_2.xlsx` (columns: `Title`, `Abstract`). For each row, classify the paper as `Include` or `Discard` and write a one- or two-sentence reasoning. Save results to `screening/round_2_classified.xlsx` with the original columns plus new `Decision` and `Reasoning` columns. Do not overwrite the input file. Use python with openpyxl.

A paper is `Include` only if all three of the following are satisfied or strongly implied by the title and/or abstract:

1. COHORT — patients undergoing allogeneic stem cell, hematopoietic cell, or bone marrow transplantation (allo-SCT / allo-HSCT / allo-HCT / allo-BMT), typically for hematologic malignancies. Pediatric and adult both qualify. Autologous-only cohorts do not qualify.

2. GUT MICROBIOME EXPOSURE — the gut, intestinal, or fecal microbiome must be examined, measured, or treated as a substantive mechanistic component. Qualifying signals: 16S rRNA sequencing, shotgun metagenomics, fecal microbiota transplant (FMT), prebiotic or probiotic intervention with microbiome readout, microbial diversity metrics (alpha/beta diversity), named gut taxa, or SCFA / butyrate / bile acid measurement as microbial metabolites. Non-gut microbiome sites alone (vaginal, oral, skin, lung) do NOT qualify. A passing mention of "gut microbiota" or "dysbiosis" within a list of factors is NOT enough — the microbiome must be a substantive focus.

3. OUTCOME — GVHD (acute or chronic) as a primary or major outcome. Broader allo-SCT outcomes (overall survival, TRM, infection, engraftment) are acceptable only when the gut microbiome is itself the substantive focus of the work.

Study-type rules:
- Original studies, reviews, and intervention trials are all eligible.
- Reviews must give the gut microbiome a substantive mechanistic or explanatory role — not merely list it as part of the gut tissue environment.
- Pure opinion or perspective pieces where the microbiome is only a passing mention → Discard.

Edge cases:
- If the abstract is missing, empty, or appears to just duplicate the title, decide on the title alone. If the title clearly aligns with the three dimensions, Include.
- This is a first-pass filter, not a final eligibility decision. When the title/abstract genuinely could fit but you cannot be sure, lean toward Include — manual full-text review will resolve ambiguity downstream.

In the `Reasoning` column, explicitly name which of the three dimensions are satisfied (cohort / microbiome / outcome) and, for `Discard` decisions, name the missing or insufficient dimension. Keep reasoning to 1–2 sentences.

When done, print the count of `Include` vs `Discard`.

## Version history

- v1 (2026-05-06) — initial managed version. Distilled from a 13-paper training
  set (Initial_Training.xlsx) where the reviewer (S.H.) provided gold-standard
  Include/Discard labels and verbal reasoning. The three-dimension structure
  (cohort / gut microbiome exposure / GVHD outcome) and the lean-Include rule
  for first-pass filtering were extracted from those reasonings. Validated
  against a 10-record holdout (Screen2). One disagreement (skin-microbiome
  paper that reported confirmed intestinal dysbiosis) prompted v2.
