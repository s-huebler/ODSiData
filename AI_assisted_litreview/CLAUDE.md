# AI-Assisted Literature Review — Logging Rules

This directory tracks all AI-assisted work for the scoping review:
**"Gut Microbiome and Time-to-GVHD in Adult Allo-SCT Recipients"**

All records are structured for synthesis into the PRISMA-trAIce supplement.

---

## LOGGING TIERS

Not every conversation needs the full template. Use the correct tier to avoid
burning tokens on unnecessary bookkeeping.

### FULL log — required when AI made reportable decisions
Trigger a FULL log (using `templates/session_log_template.md`) only when the
session involved AI performing one or more of:
- Title/abstract screening (any batch size)
- Full-text inclusion/exclusion flagging
- Data extraction (any paper)
- Validation of AI decisions against a human gold standard
- Creation or modification of a managed prompt file in `prompts/`

### BRIEF log — required for methodology sessions with outputs
Trigger a BRIEF log (using `templates/brief_log_template.md`) when the session:
- Drafted or refined the search string
- Changed eligibility criteria
- Made a protocol decision (e.g., changed baseline definition, added a study tier)
- Produced outputs that will appear in the paper or supplement, but no AI screening/extraction

### NO log needed
Skip logging entirely for:
- General background reading or discussion with no protocol decisions
- Debugging code (citation network, R pipeline) with no data decisions
- Reformatting or editing text that doesn't affect Methods/Results content
- Conversations that produced no outputs and changed no decisions

---

## CONFIRM BEFORE WRITING

**Rule: never auto-write a log. Always ask first.**

Before creating or appending to any file in `logs/`:
1. Recommend a logging status — one of `FULL`, `BRIEF`, or `NO log` — and give a
   one-line reason based on the tier rules above.
2. Ask the user to accept, reject, or defer the recommendation.
3. If the user supplies a note indicating the log should wait for a pending decision
   (e.g., "defer — eligibility criteria still being revised", "hold until validation
   numbers are in"), record the deferral reason in the scratch stub and do **not**
   create the log file.
4. Only write the log after the user has explicitly accepted the recommendation.

This applies to both FULL and BRIEF logs, including "inline at end of session"
BRIEF logs — still ask before writing.

---

## WHEN TO WRITE THE LOG

**Rule: do not write the log inside a long work session.**

Writing a full YAML log at the end of a 100-paper screening session wastes the
remaining context. Instead:

1. **During the session:** note key numbers in a scratch comment (n screened,
   n included, n uncertain) — just enough to reconstruct the log later.
2. **After the session:** open a *fresh, short conversation* and say:
   > "Log the screening session from [date]. Here are the numbers: [paste stub]."
   Claude will fill in the full template in a clean context window.

For BRIEF logs, writing inline at the end of the session is fine — they're short.

---

## PROMPT FIELD GUIDE

The session log has three prompt fields. Use exactly one of `prompt_ref` or
`prompt_verbatim` per session — never both.

### `prompt_ref`
Use when the prompt is a managed, versioned file saved in `prompts/`.
This is the preferred approach for any prompt used more than once (e.g.,
the screening prompt, the extraction prompt).

```yaml
prompt_ref: "prompts/screening-ta_v1.md"
prompt_version: "v1"
prompt_verbatim: ""   # leave blank
```

### `prompt_verbatim`
Use for one-off prompts, ad hoc questions, or planning sessions where there
is no single structured prompt. Also use during the experimental phase before
a prompt is stable enough to manage as a file.

```yaml
prompt_ref: ""        # leave blank
prompt_version: ""    # leave blank
prompt_verbatim: |
  [Paste exact prompt here, or write "Conversational session — no structured prompt."]
```

### `prompt_version`
The version number of a managed prompt file (`v1`, `v2`, ...). Only populated
when `prompt_ref` is used. Increment the version whenever you modify a prompt
and create a new file (e.g., `screening-ta_v2.md`). Document the reason for
the change in the new prompt file's header.

### Graduating a prompt from verbatim to managed
When a prompt you've been using ad hoc is ready to stabilize:
1. Save it to `prompts/<stage>_v1.md`
2. Switch from `prompt_verbatim` to `prompt_ref` in future logs
3. Note the graduation in the log: "Prompt moved to prompts/screening-ta_v1.md"

---

## PROMPT FILE FORMAT

Each file in `prompts/` should follow this header:

```markdown
# Prompt: <stage> v<N>
# Created: YYYY-MM-DD
# Modified: YYYY-MM-DD (reason: ...)
# Used in sessions: [list log files that reference this prompt]
# PRISMA-trAIce item: methods-tools

---

[Verbatim prompt text here]
```

---

## FILE NAMING

```
logs/YYYY-MM-DD_<tier>_<stage>_<slug>.md
```

- `<tier>`: `full` or `brief`
- `<stage>`: `planning` | `search` | `screening-ta` | `screening-ft` |
             `extraction` | `citation-network` | `validation` | `other`
- `<slug>`: short descriptor, e.g. `batch1`, `bergeron2017`, `prompt-revision`

Examples:
```
logs/2026-04-08_brief_planning_outline-and-goals.md
logs/2026-04-15_full_screening-ta_batch1.md
logs/2026-04-22_full_extraction_bergeron2017.md
logs/2026-04-23_brief_search_string-refinement.md
```

---

## SYNTHESIS

At the end of the review, ask Claude:
> "Synthesize the PRISMA-trAIce supplement tables from all logs in
> AI_assisted_litreview/logs/, prompts/, and validation/."

This will produce draft text for:
- Supplement Table S3: PRISMA-trAIce 14-item checklist
- Supplement Table S4: Prompt documentation (all versioned prompts)
- Methods §2.3: Human–AI interaction narrative
- Validation performance table

---

## QUICK REFERENCE

| Situation | Action |
|-----------|--------|
| Just discussed eligibility criteria, made a decision | BRIEF log, inline |
| Screened 50 title/abstracts with AI | FULL log, fresh session after |
| Extracted data from one paper | FULL log, fresh session after |
| Ran validation against gold standard | FULL log, fresh session after |
| Revised and saved a new prompt version | BRIEF log + new file in prompts/ |
| Debugged the citation network R script | No log |
| Planned the paper outline | BRIEF log (already done: 2026-04-08) |

---

## SECOND-PASS SCREENING WORKFLOW (full-text AI screening)

After the title/abstract pass yields ~481 candidates, the second pass uses
Claude Code to read each full-text PDF and label it for inclusion.

### Inputs
- **PDF folder:** `AI_assisted_litreview/Screening2_AI/Exported_PDFs/`
  Contains the full-text PDFs exported from Papers / ReadCube.
- **Reference CSV:** `AI_assisted_litreview/Screening2_AI/Input481.csv`
  (not yet exported) — the Papers export of all 481 candidate references,
  one row per paper, including a `Tags` column. Schema matches the Papers
  CSV export format (see `Prompt_Gen_V1/V1_input.csv` for column layout —
  e.g. `item ID`, `doi`, `pmid`, `Title`, `Author`, `Tags`, etc.).

### Output
- **Output CSV:** a new CSV mirroring the input schema, with each row's
  `Tags` column updated to include classification tags. The output CSV is
  re-importable into Papers (ReadCube), which lets Sophie build sublists
  from any tag.

### Classification labels (one per paper)
- `SecondPassAI-Include`
- `SecondPassAI-Exclude`
- `SecondPassAI-EdgeCase-Include`
- `SecondPassAI-EdgeCase-Exclude`

### Reason tags (required for any Exclude or EdgeCase decision)
Reason tags follow the pattern:
`SecondPassAI-ExcludeReason-<ShortCamelCaseReason>`
e.g. `SecondPassAI-ExcludeReason-UnmeasuredGutMicrobiome`. The full
controlled vocabulary of reason tags will be developed iteratively with
Sophie — the prompt should constrain the model to a fixed list once
finalized.

Tags are appended to the existing comma-separated `Tags` column without
overwriting any pre-existing Papers tags (e.g. `Prompt Gen`, `Screen2.1`).

### Execution model — looped bash script
A bash wrapper (drafted in `scripts/bash/screen_loop_template.sh`)
processes the PDFs one at a time so each PDF gets its own fresh Claude
Code context. Loop behavior:
1. Find PDFs in `Exported_PDFs/` that are not yet represented in the
   output CSV.
2. For each next PDF, invoke `claude -p --dangerously-skip-permissions`
   with a prompt that:
   - Points Claude at the managed prompt file
     (likely `prompts/screening-ft_v1.md`).
   - Identifies the PDF path and the matching row in `Input481.csv`
     (matched on filename / identifier).
   - Instructs Claude to copy that row verbatim into the output CSV,
     append the classification + reason tags to the `Tags` column, and
     leave `Input481.csv` untouched.
3. When token limits hit, the script exits / pauses; Sophie restarts it
   after the quota resets. The script is idempotent — it skips PDFs
   already present in the output CSV, so reruns resume where they
   stopped.

### Prompt file location
The finalized full-text screening prompt will live in
`prompts/screening-ft_v1.md` and be referenced from session logs via
`prompt_ref` (same convention as `screening-ta_v*.md`).

### Why tags-in-CSV (rather than a separate decisions table)
Papers (ReadCube) lets Sophie filter and build sublists from the `Tags`
column. Writing decisions as tags means the second-pass output is
directly importable into her reference manager for the next stage
(e.g. manual review of EdgeCase papers, data extraction on Includes).
