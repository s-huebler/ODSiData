# Jarosch 2023: second reproduction attempt (2026-11-01)

This folder sits beside the earlier attempt in `Repro/`; nothing there was changed. The goal was the same: reproduce the 16S pipeline closely enough that per-run alpha diversity (Richness, Simpson, Shannon) matches Table S1. The matching triple would then identify which ENA run (PRJEB60178) belongs to which biopsy.

## Bottom line

**No run-to-biopsy mapping can be trusted yet.**
- None of the pipeline variants below reproduces the published values.
- The reproduced richness is systematically lower: median 16–41 against 61.5 published.
- No variant matches more than about 2 published richness values exactly.
- Two independent pipelines whose run-level Shannon values correlate at r = 0.91 agree on only 4 of 46 assignments.

So any assignment produced from these numbers is not identifiable, and should not be joined to clinical data. The `*_match.tsv` files are kept as evidence only.

## What was found

1. **The ENA runs contain two amplicons.**
   - Every run starts with the Ion Torrent barcode-adapter remnant `GAT`, then one of two primers.
   - **V1–V3:** 27F-type primer, printed in the reads as `AGAGTTTGATCGTGGCTCAG`; reads of about 490 bp ending near 519R.
   - **V3–V4:** 341F `CCTACGGGNGGCWGCAG`; reads of about 420 bp ending at the 805R site `GGATTAGATACCC`. These are 25–65% of each run.
   - The paper describes only V1–V3. The earlier attempt kept both amplicons, because cutadapt ran without `--discard-untrimmed`.
2. **ENA sample metadata adds collection year, not identity.** `results/ena_sample_dates.tsv` lists the collection date of each of the 53 runs, read through the browser: 15 in 2020, 33 in 2021, 5 in 2022, and 8 with a full date. Aliases are lab IDs (`R0000…`, `AAX11`…), and no patient or day attribute is deposited.
3. **dada2 version does not matter.** On three samples with the same filtered reads and error model, dada2 1.30 and 1.16 give identical ASVs and counts. learnErrors itself was not compared.

## Variants run

All variants used dada2 1.16.0 at commit 8bedfb47, the paper's version and the same commit the MCP wraps, with the paper's settings: trimLeft = 15, maxEE = 5, HOMOPOLYMER_GAP_PENALTY = −1, BAND_SIZE = 32. Chimeras were removed with removeBimeraDenovo consensus ("nochim"); "pre" means before chimera removal.

| Variant | Reads entering dada2 | pool | Median richness (IQR) | Median Shannon |
| --- | --- | --- | --- | --- |
| Earlier attempt (`Repro/`) | both amplicons, Trimmomatic SLIDINGWINDOW:20:15 | FALSE | 32 (21–52) | 2.30 |
| A | 27F only (cutadapt `--discard-untrimmed`), no Trimmomatic | FALSE | 16 (12–32); pre 22 | 1.76 |
| B | both amplicons (27F or 341F stripped), no Trimmomatic | FALSE | 35 (23–58); pre 41 | 2.25 |
| C | as A | "pseudo" (per-sample pass, then priors from ASVs in ≥2 samples, exactly dada2 1.16's pseudo-pooling) | 21 (14–35); pre 24 | 1.76 |
| D (8 runs only) | Trimmomatic `LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 MINLEN:36`, then 27F | FALSE | lower than A on the same runs | — |
| **Published Table S1** (46 distinct stool samples) | | | **61.5 (38–97)** | **2.13** |

The resumable per-sample run (`dada_resume.R`, pass 1) reproduces `dada(..., pool = FALSE)` exactly: identical tables for variant A.

## Not tried (candidates)

- **`pool = TRUE`.** It typically recovers far more rare ASVs than pseudo-pooling, but it needs all 1.4–2.6 M reads in one call. That exceeds this workspace's memory (about 6 GB shared) and its 2-hour job limit.
- **Other quality filtering.** The paper gives "minEE 5"; maxEE = 5 was assumed. Variations in truncQ, maxN and minLen, and running without maxEE, were not tried.
- **Richness computed on a different table.** For example: before dada2, on taxonomically collapsed features, or after a different chimera method.
- **The most reliable route: ask the authors.** Ask for the alias-to-sample key or the alpha-diversity script. The lead contact is Dirk H. Busch; the 16S work was done by Andreas Hiergeist and André Gessner (Regensburg).

## Files

- `scripts/`
  - `cut27f.sh`, `cutboth.sh`: cutadapt 3.5 primer demultiplexing (27F only, or both amplicons).
  - `dada.R`: one-shot dada2 run.
  - `dada_resume.R` + `loop.sh`: resumable per-sample run with optional pseudo-pooling, surviving the 2-hour job limit.
  - `match.R`: Hungarian assignment of runs to the 46 published triples, with distance and margin.
  - `match2.R`: Shannon/Simpson-only cross-pipeline agreement check.
  - `variantD_subset.sh`: the Trimmomatic test.
- `results/`
  - `variant_summary.tsv`: the table above.
  - `table_s1.csv`: Table S1 as transcribed in the paper skill, with decimal commas.
  - `ena_sample_dates.tsv`: run, sample, alias, collection date, read count.
  - For each variant: `*_alpha.tsv` (per-run Richness, Shannon, Simpson, depth) and `*_match.tsv` (assignment, **not validated**).
  - Sequence tables (`*.rds`) for variants A, B and C.
  - `D_trimmomatic_subset_richness.txt`.

Software: cutadapt 3.5 (Python 3.9), Trimmomatic 0.39 (bioconda), and dada2 1.16.0 compiled from the v1.16 tag on R 4.3.3. The MCP uses the same dada2 commit on R 4.5.3. vegan computed alpha diversity: Shannon with natural log, Simpson as 1 − Σp². Cloud workspace, Linux x86_64.
