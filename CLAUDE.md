# Sophie Huebler — Dissertation Workspace
## Biostatistics PhD | GVHD Microbiome + Bayesian Hierarchical Methods

---

## Dissertation Overview
Three-project dissertation on microbiome analysis in graft-versus-host disease (GVHD),
grounded in the T32 grant proposal (see proposal/). Projects connect: Project 1 builds
the harmonized dataset that Project 3 will apply Project 2's method to.

## Active Projects

### Project 1 — ODSiData (`../ODSi/ODSiData`)
Curation and harmonization of open-source 16S rRNA microbiome datasets from allogeneic
stem cell transplant / GVHD studies. QIIME2-based processing pipeline, R/phyloseq
downstream analysis. GitHub: https://github.com/s-huebler/ODSiData

### Project 2 — bhCRR (`../bhCRR`)
Bayesian Hierarchical Competing Risks Regression — R package implementing a semi-
supervised spike-and-slab lasso method for high-dimensional competing risks data.
GitHub: https://github.com/s-huebler/bhCRR

### Project 3 (planned)
Application of bhCRR to the harmonized ODSiData cohort.

## Related Archives
- `../SSL/CmpRsk_SSL/` — early scratch work that evolved into bhCRR. Archival,
  not actively developed, but useful historical context.

## Key Paths
| Resource              | Path                                      |
|-----------------------|-------------------------------------------|
| Project 1 data        | ~/Documents/ODSi/ODSiData                 |
| Project 2 package     | ~/Documents/bhCRR                         |
| T32 proposal          | ~/Documents/dissertation-hub/proposal/    |
| Shared references     | ~/Documents/dissertation-hub/shared/references/ |

## Manuscript Locations
- Project 1 manuscript: Overleaf [add link] → sync target: ODSiData/outputs/
- Project 2 manuscript: Overleaf [add link] → sync target: bhCRR/outputs/

## Environment Notes
- Machine: MacBook Pro M4 Pro (arm64 / Apple Silicon)
- QIIME2 requires Rosetta x86 emulation — see Project 1 CLAUDE.md for details
- R dependency management: renv (both projects have renv.lock)
- Default conda (arm64): ~/miniconda3
- QIIME conda (x86): ~/miniconda3-x86_64/envs/qiime2-env

## CHPC (University of Utah)
- Connect: ssh [username]@chpc.utah.edu
- Workflow: develop locally → push to GitHub → pull on CHPC → submit SLURM jobs
- Job scripts live in each project's chpc/ folder

## CHPC Login-Node Policy — DO NOT run compute on interactive nodes
CHPC login/interactive nodes (lonepeak1/2, kingspeak1/2, notchpeak1/2, granite1/2)
are shared front-ends for editing, staging, and submitting jobs ONLY. Running
computationally intensive or long-running work on them violates CHPC Policy 2.1.1
(https://www.chpc.utah.edu/documentation/policies/2.1GeneralHPCClusterPolicies.php#Pol2.1.1)
and triggers automatic penalties (temporary CPU/memory caps across all login nodes).
This already happened once (conda env solve on lonepeak2, 2026-08-05).

- **Never instruct Sophie to run heavy work directly on a login node.** This includes,
  but is not limited to: `conda`/`mamba` env creation or solves, `pip install` of
  compiled packages, compiling from source (`make`, `./configure && make`), QIIME2
  commands, vsearch/DADA2/BLAST or any bioinformatics binary, large file
  decompression, and anything that runs more than a minute or two or uses real CPU/RAM.
- **Route all such work through Slurm**: either a batch job (`sbatch`) or an
  interactive allocation (`salloc`/`srun`) on a compute node. Only then run the
  intensive command.
- **Fine on a login node**: `git` operations, editing files, small `wget`/`curl`
  downloads + `tar` extraction of modest archives, `module load`/`module spider`,
  writing/inspecting job scripts, and quick `--version`/`--help` checks.
- When a task needs a package installed or built (e.g. the generic bioconda vsearch
  in `load_qiime2_env`), wrap the install in an `salloc`/`srun` on a compute node,
  or add it as a one-off `sbatch` step — do NOT hand Sophie a bare `conda create`
  to paste on the login node.

## Git Conventions
- Project 1 commits: "[Study] brief description" e.g. "[Liu2017] fix DADA2 params"
- Project 2 commits: "feat/fix/docs/test: brief description"
- Always run devtools::check() before pushing bhCRR

## LaTeX Compilation — Overfull Errors
When compiling manuscripts (Overleaf sync, local `pdflatex`/`latexmk`, etc.):
- On the **first compile**, do not iteratively chase overfull hbox/vbox warnings.
- For each overfull warning, insert a comment in the `.tex` source at or immediately
  above the offending line in the form:
  `% flagged to do: fix overfull (hbox, <size>pt at line <N>)`
- If an overfull location already carries a `% flagged to do: fix overfull` comment,
  ignore it on subsequent compiles unless the user specifically asks for it to be
  addressed.
- Other LaTeX errors (undefined references, missing packages, syntax errors) should
  still be resolved normally — this rule applies only to overfull box warnings.

## Prompt Requests
When Sophie asks for a "prompt", says "help me with a prompt", "write me a prompt",
"give me a prompt", or any similar phrasing, interpret this as a request for a
**Claude Code prompt** that she will copy-paste into the Claude Code CLI running in
the Positron terminal.

Formatting rules for these prompt requests:
- Output the prompt as plain text in a single fenced code block so it can be copied
  and pasted directly into the terminal. No surrounding commentary inside the block.
- Write in the second person, directed at Claude Code (e.g., "Read X, then do Y").
- Assume Claude Code is running from the relevant project root
  (usually `~/Documents/ODSi/ODSiData` or `~/Documents/bhCRR`) — use paths relative
  to that root unless an absolute path is needed.
- Reference the `run_qiime` alias for any QIIME2 commands rather than raw conda activation.
- Respect the repo's commit convention ("[Study] brief description" for Project 1;
  "feat/fix/docs/test: brief description" for Project 2) whenever the prompt includes
  a commit step.
- Keep each prompt focused on a single, verifiable unit of work.

Multi-step / complex tasks:
- If the task is complex or multi-step, do **not** cram everything into one prompt.
  Split it into a numbered sequence of prompts, each in its own fenced code block,
  with a brief one-line heading above each block describing the step.
- Order the prompts so each one can be run and verified before moving to the next
  (e.g., explore → plan → implement → test → commit).
- Explicitly note any handoffs between prompts (files produced, state changed) so
  Sophie knows what to check before pasting the next one.

## CHPC Sparse-Checkout — Adding a Study

The CHPC clone of this repo uses **non-cone** sparse-checkout (`core.sparseCheckoutCone
= false`) so root-level files stay hidden on the cluster. Patterns live in
`.git/info/sparse-checkout`.

When Sophie says she wants to add a study to the CHPC checkout — e.g. "add Liu2017 to
the chpc", "track Fujimoto2024 on chpc", or any similar phrasing — respond with the
full sparse-checkout rewrite prompt for her to copy-paste, as a single plain-text
fenced code block with no surrounding commentary inside the block. The block rewrites
`.git/info/sparse-checkout` with the entire canonical pattern list **plus the new
study's folder**, then reapplies:

```
cat > .git/info/sparse-checkout <<'EOF'
/CLAUDE.md
/Artacho2024/
/DAmico2019/
/Ingham2019/
/chpc/
/Vallet2023/
/Liu2017/
/Jarosch2023/
/Fujimoto2024/
/Greengenes2/
/Merging/
EOF
git sparse-checkout reapply
```

Rules for this prompt:
- Use a trailing slash on every study folder (e.g. `/NewStudy/`) so the whole tree
  is included; keep `/CLAUDE.md` as a bare file entry.
- Append the new study to the END of the list, preserving the existing order.
- **Update this canonical list in CLAUDE.md every time** a study is added, so the block
  above always reflects the current CHPC checkout. The list currently tracks:
  CLAUDE.md, Artacho2024, DAmico2019, Ingham2019, chpc, Vallet2023, Liu2017,
  Jarosch2023, Fujimoto2024, Greengenes2, Merging.
- The study folder must already be committed and pushed to the branch CHPC tracks, or
  `reapply` will materialize nothing — flag this if the study is new to the repo.

## Known gotchas

### openxlsx corrupts xlsx for openpyxl
`openxlsx::saveWorkbook()` emits dangling `<Relationship>` entries in every
`xl/worksheets/_rels/sheetN.xml.rels` that point at `../drawings/drawingN.xml`,
`../drawings/vmlDrawingN.vml`, and `../printerSettings/printerSettingsN.bin` — none
of which it actually writes into the archive. It also emits a stale
`<dimension ref="A1"/>` in every sheet XML.

Consequences:
- `openpyxl.load_workbook()` (default mode) raises `KeyError: 'xl/drawings/drawing1.xml'`
- `openpyxl.load_workbook(read_only=True)` silently returns only the header row per
  sheet (stale dimension fools the read-only range scanner)

**Rule for this repo:** use `writexl::write_xlsx()` for writing and `readxl::read_excel()`
for reading xlsx files. Never use openxlsx for output. Never use openpyxl `read_only=True`
on files produced by openxlsx.

## Harmonization Variable Additions (Project 1)

Standing rules for adding a variable to the harmonized GVHD metadata. A
per-variable prompt supplies only the spec and the per-study construction; every
rule below applies automatically and should not be restated in the prompt.

### Files

| Role | Path |
|---|---|
| Harmonizer | `Merging/Harmonization/harmonize_gvhd_metadata.R` |
| Tests | `Merging/Harmonization/test_harmonize_gvhd_metadata.R` |
| Decision log | `Merging/Harmonization/to_log/harmonization_decisions.md` |
| Data dictionary | `Merging/Harmonization/data_dictionaries_harmonized.xlsx` |

**Never edit the xlsx during a variable addition.** It is updated in one batch at
the end of a round. Instead, end each decision-log entry with a "Workbook edits
still owed" list naming the sheets, rows and columns that will need changing.
Check for an Excel lock file (`~$data_dictionaries_harmonized.xlsx`) before any
batch edit — it means the workbook is open and the write will collide.

### Raw source metadata

One row per sample. Read with `read_tsv(path, show_col_types = FALSE, name_repair = "minimal")`
so source headers survive verbatim, including spaces and punctuation.

```
Artacho2024/Metadata/artacho_meta_qiime.tsv
DAmico2019/Metadata/damico_meta_qiime.tsv
Fujimoto2024/Metadata/fuji_meta_qiime.tsv
Ingham2019/Metadata/ingham_meta_qiime.tsv
Liu2017/Metadata/liu_meta_qiime.tsv
Vallet2023/Metadata/vallet_meta_qiime.tsv
```

Column meanings, value sets and missingness are documented per study in the
sheets of `data_dictionaries_harmonized.xlsx` (one sheet per study, plus
`Canonical_Schema`, `Value_Map`, `Coverage`, `Harmonization_Summary`). Read the
relevant study sheet before writing construction logic — do not infer a column's
meaning from its name.

### Coding contract by variable shape

- **Binary / event** — `"1"` / `"0"` / `NA` via `harmonize_binary(<logical>)`.
  Add the column to `binary_outcome_cols` so QA validates it automatically. A
  documented negative is `0`, never `NA`; reserve `NA` for genuinely unknown or
  not-applicable. Never introduce a yes/no column.
- **Time-to-event** — always the triple `<outcome>`, `<outcome>_day_rel_transplant`,
  and a severity/stage column where the source supports one. Days are relative to
  transplant day 0, negative before. **Mask every day column by its own event**:
  retain a day only where that outcome is `1`, so censoring, last-follow-up and
  diagnosis times can never be mistaken for event times.
- **Categorical covariate** — one `harmonize_<var>()` with an explicit `case_when`
  over lower-cased, cleaned input, returning a documented canonical vocabulary.
  Define the vocabulary as a `<var>_levels` vector next to the function.
  Unrecognized source values return `NA` and must be surfaced by a QA table
  (follow `noncanonical_disease_values`), never silently passed through.
- **Numeric covariate** — `as_num()`. No rounding, no unit conversion unless the
  prompt asks; state the units in the column comment in `target_cols`.
- **Dates** — `parse_date_flexible()`, emitted as ISO `YYYY-MM-DD`.

Everything is coerced to character by `to_schema()` at the end — that is expected
and is not a bug.

### Placement and documentation

- Add new columns to `target_cols` in a semantically grouped position with a
  short comment. The order in `target_cols` **is** the output column order.
- Per-study rules live at the point of use: a comment inside the relevant
  `harmonize_<study>()` explaining what the source actually records and why the
  rule is what it is. A reader should not need the dictionary open to follow it.
- Logic shared by two or more studies factors into a helper defined above the
  study functions, with a block comment covering the families of source encoding
  it handles.

### GOTCHA: `transmute()` shadows locals with source columns

`transmute()` resolves bare names against the source data frame **before** the
calling environment. A local named like a raw column is silently shadowed. This
has already caused real bugs: DAmico's `gvhd_day`, Ingham's `transplant_date`
and `agvhd_date`. Two failure modes — a type error, or (worse) silently using
the uncleaned source column.

**Rule:** before adding a local that feeds a `transmute()`, check it against
`names(df)` for that study. If it collides, suffix it (`_num`, `_parsed`, `_event`)
and leave a comment saying why.

### QA

Extend `build_qa()` for every addition. Every new binary joins
`binary_outcome_cols`. Every new vocabulary gets a validity table listing
non-canonical values by study. Every new outcome gets a coverage row. Prefer
tables that would be **empty when correct**, so a non-zero row count is a
failure signal rather than something to interpret.

### Testing is not optional

Add both unit tests (helper behaviour, boundaries, edge values) and end-to-end
assertions (cross-tabulate the harmonized column against the source column, per
study) to `test_harmonize_gvhd_metadata.R`. Then run it and paste the output.

```
Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R
```

**Never report a variable addition as done without a passing run against the real
metadata.** Synthetic fixtures do not catch source-data anomalies, which is where
the real problems have been.

If R is unavailable in the environment (e.g. a cloud Cowork session rather than
the local Positron terminal):

```
apt-get update && apt-get install -y r-base-core r-cran-dplyr r-cran-lubridate \
  r-cran-stringr r-cran-purrr r-cran-readr r-cran-tibble
```

### Decision log entry structure

Append to `to_log/harmonization_decisions.md` using this shape:

```
## YYYY-MM-DD — <short title>

**Decision.** What the variable is and how it is coded.
**Why.** The analytic reason it exists in this form.
### Per-study rules
<table: study | rule | source columns>
### Decisions taken along the way
<bullets: every judgement call, with the evidence and counts that justified it>
### Verification
<what was run, and the observed counts per study>
**Workbook edits still owed.**
<bullets naming sheet, row and column>
```

Also append anything unresolved to the `## Open questions` section at the end of
the file. Record judgement calls even when they felt obvious — the point of the
log is that a decision can be re-examined later without re-deriving it.

### Stop and ask before implementing

Inspect the source columns and cross-tabulate the real data first. Stop and ask
rather than guessing when any of these appear — each has already produced a
wrong or near-wrong result in this project:

- A source column that looks derived, duplicated or internally inconsistent
  (Liu's `time_to_cgvhd` duplicates `time_to_agvhd` in 78/79 rows and is unusable).
- A competing-risk or multi-level code where collapsing to binary loses meaning
  (Vallet's `agvhd` = 2 means died before aGVHD, not "no aGVHD").
- Ambiguity about whether a documented zero should be `0` or `NA`.
- Two studies whose vocabularies look alignable but come from different
  instruments (Liu's cGVHD "Stage 1/2/3" vs Vallet's NIH "mild/moderate/severe").
- A value that would be pooled across studies while actually measuring different
  quantities (organ stage vs overall composite grade in the `_stage` columns).
- The spec conflicting with existing behaviour in the file.

State the ambiguity, give the counts from the real data that make it matter, and
propose a default. Do not silently pick one.
