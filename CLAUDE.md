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
