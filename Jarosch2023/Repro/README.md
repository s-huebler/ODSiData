# Jarosch2023 — native-pipeline replication

Goal: reproduce the alpha diversity values published with Jarosch et al. 2023
(*Cell Rep Med* 4:101125, PRJEB60178) using the authors' own toolchain rather
than QIIME2, and quantify how close we get.

Target values live in `../Metadata/jarosch_alpha_diversity.tsv`
(53 runs; `Richness`, `Shannon`, `Simpson`, `depth`).

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
   `LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:100`. This is the single
   biggest lever on the `depth` column — vary it first.
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

## Running the pipeline

```bash
cd ~/Documents/ODSi/ODSiData/Jarosch2023/Repro

# Step 1 — download 53 runs from ENA (host, not container; needs ~5-15 GB)
# Safe to re-run: verified files are skipped, so it retries only what's missing.
# EBI drops connections intermittently; if it reports failures, just run again.
bash scripts/01_download.sh

# Step 2 — Trimmomatic + cutadapt
./docker/run.sh bash scripts/02_trim.sh

# Step 3 — DADA2 ASVs
./docker/run.sh Rscript scripts/03_dada2.R

# Step 4 — alpha diversity comparison against the published table
./docker/run.sh Rscript scripts/04_compare_alpha.R
```

Each step is independently re-runnable; step 1 skips files whose MD5 already
matches.

## Checkpoints

| After | Check | Expect |
|---|---|---|
| 1 | `results/01_download_status.tsv` | 53 rows all `ok`; the run summary should print `runs failed : 0` |
| 2 | `results/02_cutadapt_summary.tsv` | forward primer found in a large majority of reads; modest loss at each stage |
| 3 | `results/03_read_tracking.tsv` | amplicon length mode near 480–500 bp; non-chimeric fraction roughly 55–90% (matches the QIIME2 run's 54–92%) |
| 4 | `results/04_alpha_comparison_grid.tsv` | `depth` correlation is the headline number — read it before anything else |

## Interpreting step 4

`depth` is the diagnostic that isolates the trimming assumptions, since it does
not depend on any diversity convention. Read the results in this order:

- **`depth` r high, `mean_diff` near zero** → trimming matches; any remaining
  Shannon/Simpson gap is a convention or denoising difference.
- **`depth` r high, `mean_diff` large** → the pipeline shape is right but
  stringency differs. Loosen or tighten `TRIMMOMATIC_ARGS` in step 2.
- **`depth` r low** → something structural is wrong (wrong runs, primer
  orientation, or reads being discarded wholesale). Check
  `results/02_cutadapt_summary.tsv` before touching DADA2.

An exact match is unlikely: the paper omits enough parameters that some drift
is guaranteed. A defensible outcome for the dissertation is high rank
correlation (Spearman > 0.9) on all three metrics, with the residual
discrepancy attributed to specific documented gaps.

## Layout

```
Repro/
  docker/     Dockerfile, build.sh, run.sh
  scripts/    01_download.sh  02_trim.sh  03_dada2.R  04_compare_alpha.R
  data/       raw/ trimmed/ cutadapt/ filtered/     (gitignored)
  results/    ASV tables, comparison grids, plots
  logs/       per-step logs and cutadapt reports
```
