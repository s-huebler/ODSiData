# Jarosch2023 — recovering the run → patient mapping

**The problem.** Jarosch et al. 2023 (*Cell Rep Med* 4:101125) deposited 53
sequencing runs in ENA (PRJEB60178) under anonymous library aliases (`AAX11`,
`R000000616`, …), and separately published alpha diversity for 46 stool samples
keyed by **Patient + day after aHSCT**. They never published the link between
the two. Without it, the sequencing data cannot be joined to any clinical
covariate — which makes the study unusable for the meta-analysis.

**The approach.** Reproduce the authors' own pipeline (Trimmomatic → cutadapt →
DADA2, not QIIME2) closely enough that our alpha diversity values reproduce
theirs, then use the `(Richness, Shannon, Simpson)` triple as a **fingerprint**
to identify which run is which sample.

This works because the published values carry a lot of information: `Richness`
is an exact integer, `Shannon`/`Simpson` are given to ~7 decimal places, and all
46 published triples are mutually distinct. A faithful reproduction should give
near-zero distance for the true pairing and clearly larger distances for every
alternative.

**Reproduction fidelity is the means, not the end.** The closer steps 1–3 get,
the more confident the mapping in step 4 can be. Simulated on these published
values, recovery of the correct pairing degrades sharply with pipeline error:

| systematic richness bias (ours ÷ theirs) | correct matches |
|---|---|
| none — faithful reproduction | 98–100% |
| 0.90 | 74% |
| 0.75 | 28% |
| 0.45 | 10% |

The existing QIIME2 attempt sits at ratio ≈ 0.45 (median richness 28 vs the
paper's 62), which is why `../Metadata/jarosch_sample_to_clinical.tsv` yielded
only 18 high-confidence matches. That file is superseded by this work.

Published target: `../Metadata/Original_alpha.tsv` (46 samples, 39 patients —
several patients have multiple timepoints, so `Patient + day` is the key).

This sits alongside — not replacing — the QIIME2 attempt in `../QiimeData/`
and `../Preprocessing.qmd`.

---

## What the paper actually specifies

| Step | Tool | Reported settings |
|---|---|---|
| Quality trim | Trimmomatic "0.9" | **none given** |
| Adapter + primer removal, demux | cutadapt 3.5 | **none given** |
| ASV inference | dada2 1.16 on R 4.1.1 | trim 15 bp from 5' ends; "minEE" 5; `HOMOPOLYMER_GAP_PENALTY = -1`; `BAND_SIZE = 32` |
| Taxonomy | DECIPHER 2.19 IDTAXA, LTP 12.2021 | 50% confidence |

Sequencing: Ion Torrent GeneStudio S5 Plus, 600 bp protocol, **single-end**,
V1–V3 amplicon (~500 bp).
Primers: `S-D-Bact-0008-c-S-20` (27F) and `S-D-Bact-0517-a-A-18` (519R).

Taxonomy is out of scope here — Richness, Shannon, and Simpson are computed
from the ASV count table and do not depend on the classifier.

## Known gaps in the published methods

These are the places a mismatch is most likely to originate. Each is flagged
inline in the scripts as `ASSUMPTION` or `INFERRED`.

1. **"Trimmomatic 0.9" is not a real release.** Trimmomatic versions run
   0.30–0.39. The image installs 0.39.
2. **No Trimmomatic parameters are given.** `scripts/02_trim.sh` uses
   `LEADING:3 TRAILING:3 SLIDINGWINDOW:20:15 MINLEN:200`. This is the single
   biggest lever on the `depth` column — vary it first. Override without
   editing the script:
   `TRIMMOMATIC_ARGS="LEADING:3 TRAILING:3 MINLEN:200" ./docker/run.sh bash scripts/02_trim.sh`

   The Illumina-default `SLIDINGWINDOW:4:15` is actively wrong here: measured
   on these reads it keeps only 66% and cuts the median from 449 to 321 bp,
   yielding 140–165 bp ASV fragments instead of a ~490 bp V1–V3 amplicon.
   A 20-base window keeps 98.7% at median 448 bp.
3. **"minEE value of 5"** — dada2 has no `minEE` argument. `maxEE = 5` is
   the only expected-error filter and is what the scripts use.
4. **"Demultiplexed using cutadapt"** — ENA serves the runs already
   demultiplexed, so only primer stripping is reproducible.
5. **Chimera removal is never mentioned.** Step 3 writes both
   `seqtab_prechimera.rds` and `seqtab_nochim.rds`; step 4 compares both.
6. **`pool` is not specified** in the `dada()` call. Default `FALSE` is used.
   If Richness is systematically low, try `pool = TRUE`.
7. **The definitions of Shannon and Simpson are not stated.** Step 4 sweeps
   log base (ln / log2 / log10) and Simpson form (Gini `1-D`, classic `D`,
   inverse `1/D`) and reports which convention fits.
8. **Does `trimLeft = 15` come before or after primer removal?** These scripts
   run cutadapt first, then `trimLeft = 15` on top. The alternative — skipping
   cutadapt and letting `trimLeft = 15` serve as the primer trim — is a
   plausible reading of the methods and worth testing if results diverge.

---

## Setup (one time)

You need Docker Desktop. The old R/dada2 toolchain does not build on arm64, so
the image is `linux/amd64` and runs under emulation.

```bash
# 1. Install Docker Desktop for Mac (Apple Silicon build), then launch it once.
#    https://www.docker.com/products/docker-desktop/

# 2. Build the image (20-40 min under emulation; go get coffee)
cd ~/Documents/ODSi/ODSiData/Jarosch2023/Repro
bash docker/build.sh

# 3. Confirm versions
docker run --rm --platform linux/amd64 jarosch2023-repro:1.0 \
  R -q -e "cat(R.version.string, as.character(packageVersion('dada2')))"
# expect: R version 4.1.1 ... 1.16.0
```

Nothing here touches your `~/miniconda3-x86_64/envs/qiime2-env` or the
project's `renv` library.

### If the build fails

Docker caches each step, so a re-run picks up from the first changed layer —
you never repeat the two ~8-minute R package layers unless those lines change.

**The dada2 compile step should take several minutes.** If it finishes in
seconds, it did not actually build. The Dockerfile now uses
`git clone` + `R CMD INSTALL` under `set -e` rather than
`remotes::install_github`, specifically because remotes downgrades a failed
compile to a *warning* — R then exits 0 and the build continues without the
package, only failing later at the version check.

The verification layer loads the package and calls into it, so it catches a
missing package, a wrong version, and a bad shared-object link.

### Threading and emulation

`scripts/03_dada2.R` runs **serial by default**. R's multicore backend forks,
and forked workers die unpredictably under x86 emulation on Apple Silicon —
they return nothing and dada2 fails with a misleading message like:

```
Error in names(answer) <- dots[[1L]] :
  'names' attribute [53] must be the same length as the vector [44]
```

That is not a data problem: 9 of 53 jobs silently vanished. Serial execution
avoids it and is deterministic, which is what a replication wants anyway. The
cost is runtime — budget 1–3 hours for step 3 on this dataset (~1.95M reads).

If you want to try parallel anyway:

```bash
NCORES=4 ./docker/run.sh Rscript scripts/03_dada2.R
```

If it fails the same way, go back to serial. Raising Docker Desktop's memory
allocation (Settings → Resources → Memory, 8 GB or more) makes parallel runs
somewhat more survivable but does not fully fix the forking issue.

## Running the pipeline

```bash
cd ~/Documents/ODSi/ODSiData/Jarosch2023/Repro

# Step 1 — download 53 runs from ENA (host, not container; needs ~5-15 GB)
# Safe to re-run: verified files are skipped, so it retries only what's missing.
# EBI drops connections intermittently; if it reports failures, just run again.
bash scripts/01_download.sh

# Step 2 — Trimmomatic + cutadapt
./docker/run.sh bash scripts/02_trim.sh

# Step 3 — DADA2 ASVs (serial by default; expect 1-3 h under emulation)
./docker/run.sh Rscript scripts/03_dada2.R

# Step 4 — recover the run -> (patient, day) mapping
./docker/run.sh Rscript scripts/04_match_samples.R
```

Each step is independently re-runnable; step 1 skips files whose MD5 already
matches.

## Checkpoints

| After | Check | Expect |
|---|---|---|
| 1 | `results/01_download_status.tsv` | 53 rows all `ok`; the run summary should print `runs failed : 0` |
| 2 | `results/02_cutadapt_summary.tsv` | **final median length 400–490 bp** — step 2 now fails with a warning if reads are over-trimmed |
| 3 | `results/03_read_tracking.tsv` | ASV length distribution peaked near 480–500 bp; non-chimeric fraction roughly 55–90% (matches the QIIME2 run's 54–92%) |
| 4 | `results/04_run_to_patient_map.tsv` | the deliverable — read the quality gate at the top of the console output first |

## Interpreting step 4

Read the output top to bottom; it is ordered deliberately.

**1. Reproduction quality gate.** Compares our richness distribution to the
published one. If the median ratio falls outside 0.7–1.4 the script says so
loudly. A weak fingerprint produces a confident-looking mapping that is
nonetheless wrong, so fix the pipeline before believing anything below it.

**2. Convention sweep.** The paper never states whether Shannon is ln/log2/log10
or whether Simpson is `1-D`, `D`, or `1/D`, so all combinations are tried
against both the pre- and post-chimera tables. Watch `n_exact_rich` — the count
of samples where published and reproduced `Richness` are *identical*. That is
the cleanest evidence the pipeline, not the matcher, is doing the work.

**3. Assignment.** One-to-one and global (Hungarian via `clue`), not greedy
nearest-neighbour: 46 published samples compete for 53 runs, each run used at
most once, 7 runs expected to go unassigned. Per match you get `dist`,
`margin` (gap to the runner-up — a large margin means it isn't a near-tie),
and `exact_richness`.

**4. Stability.** The same assignment is recomputed under all 54 variants
(2 tables × 3 log bases × 3 Simpson forms × 3 scoring modes). The three scoring
modes matter most:

| mode | compares | breaks when |
|---|---|---|
| `pooled` | absolute values | pipeline has systematic bias |
| `separate` | values standardised within each source | ordering is wrong |
| `rank` | within-cohort ranks only | ordering is wrong |

`pooled` is the sharpest when the reproduction is faithful, and is what selects
the convention. `rank` is nearly immune to systematic bias. **All three agreeing
is much stronger evidence than any one alone**, so `n_modes_agree == 3` is the
column to trust; it feeds back into the final `confidence` tier.

Treat `high` confidence with `n_modes_agree == 3` and `exact_richness == TRUE`
as settled. Treat `low` confidence as unresolved rather than guessing — leaving
a run unmapped is far cheaper than a wrong clinical join.

## Layout

```
Repro/
  docker/     Dockerfile, build.sh, run.sh
  scripts/    01_download.sh  02_trim.sh  03_dada2.R  04_match_samples.R
  data/       raw/ trimmed/ cutadapt/ filtered/     (gitignored)
  results/    ASV tables, the recovered mapping, plots
  logs/       per-step logs and cutadapt reports
```
