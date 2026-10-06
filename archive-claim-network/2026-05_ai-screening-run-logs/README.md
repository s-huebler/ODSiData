# AI screening run logs (May 2026)

**When:** May 19 – 28 2026 (logs); `Updates.qmd` Jun 2 2026.

**What was being attempted:** Second-pass AI full-text screening of the ~475 candidate papers
for the scoping review (`AI_assisted_litreview/Screening2_AI/`). Claude read each PDF and
assigned tags like `SecondPassAI-Include`, `SecondPassAI-Exclude` or `SecondPassAI-EdgeCase-*`,
plus an exclusion reason. These `.rtf` files are the terminal transcripts, saved in batches by
paper number (`First20`, `Runs1_25` … `Runs432_474`).

`Updates.qmd` reads the combined screening output (`Screening2_AI/Final.csv`), splits the tags
into decision and reason columns and tidies the result.

**Relation to the claims network:** Upstream only. Screening picked the review papers that were
later mined for claims. These logs were kept with the claim-network testing files and moved here
as part of that folder; they arguably belong with `AI_assisted_litreview/logs/`.

**Superseded by:** The screening decisions in `AI_assisted_litreview/Screening2_AI/`.
