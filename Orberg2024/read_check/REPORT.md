# Orberg2024 raw-read diagnostic (read-only)

Generated 2026-10-14 on a CHPC login node. I sampled the first 2,000 reads per run and used only the Python standard library. Nothing in the repo was changed, nothing was submitted, and no files were moved.
Scripts in this directory: `step0_classify.py`, `step12_reads.py`, `step2b_populations.py`, `step2c_trunc.py`.
Raw outputs: `step2_results.json`, `step2b_populations.txt`, `step2c_trunc.txt`.
Primer search method: semi-global edit distance ≤2 (substitutions **and** indels), IUPAC-aware.

## Step 0 — fetch inventory
- `RawData/run_accessions.txt`: 570 accessions. All 570 are present on disk as uncompressed `ERRxxxxxxxx.fastq` files (20 GB total). None are zero-byte and none are duplicated.
- `failed_downloads.txt` does **not exist**, so the fetch logged no failures.
- Classes from `meta_samples.csv`: **MO16S 269, SJ16S 54 (16S total 323), MOITS 247**. These match the expected counts exactly, with no unclassified names.
- 16S-only list: `read_check/run_accessions_16S.txt` (323 lines). The per-run class map is in `run_class.tsv`.
- ⚠️ `02_import_single.slurm` → `make_manifest_single.sh` globs **every** FASTQ in `$WORK_BASE/Orberg2024/RawData`, so the 247 ITS runs would be imported as-is. They must be excluded first (see the end of this report).

Runs sampled (spaced evenly through the sorted sample names): MO16S_023/068/113/157/202/247, SJ16S_007/022/036/051, MOITS_062/186.

## Step 2 — per-run results (a, b, c–f)
| run | sample | len min/2%/25%/med/75%/98%/max | %N | Q chars (Phred) | mean Q 1-25 / 26-100 / 101-200 / 201-300 / 301+ | % reads all 25-bp windows ≥Q20 |
|---|---|---|---|---|---|---|
| ERR10966608 | MO16S_023 | 115/140/447/493/498/502/517 | 0.0 | `"`–`M` (Q1–Q44) | 28.4 / 28.6 / 27.9 / 27.9 / 26.3 | 47 |
| ERR10966653 | MO16S_068 | 115/143/420/497/507/512/522 | 0.0 | `"`–`M` (Q1–Q44) | 28.1 / 28.2 / 27.6 / 26.7 / 25.4 | 30 |
| ERR10966698 | MO16S_113 | 114/132/422/492/499/526/536 | 0.0 | `"`–`M` (Q1–Q44) | 27.4 / 28.7 / 27.6 / 28.0 / 26.2 | 38 |
| ERR10966742 | MO16S_157 | 115/130/364/449/498/500/542 | 0.0 | `#`–`M` (Q2–Q44) | 27.9 / 28.7 / 28.2 / 28.4 / 27.4 | 51 |
| ERR10966787 | MO16S_202 | 116/172/418/488/503/531/558 | 0.0 | `"`–`M` (Q1–Q44) | 29.6 / 29.2 / 28.1 / 27.7 / 24.1 | 17 |
| ERR10966832 | MO16S_247 | 120/151/417/498/507/514/552 | 0.0 | `"`–`M` (Q1–Q44) | 29.8 / 29.3 / 27.8 / 26.8 / 23.8 | 18 |
| ERR11577485 | SJ16S_007 | 140/154/308/466/530/536/557 | 0.0 | `"`–`M` (Q1–Q44) | 28.5 / 28.3 / 27.4 / 26.4 / 26.6 | 37 |
| ERR11577493 | SJ16S_022 | 138/159/465/490/549/551/569 | 0.0 | `"`–`M` (Q1–Q44) | 28.1 / 27.5 / 27.5 / 27.7 / 27.6 | 45 |
| ERR11577518 | SJ16S_036 | 138/151/372/469/526/560/564 | 0.0 | `"`–`M` (Q1–Q44) | 27.7 / 28.2 / 28.9 / 28.4 / 26.5 | 36 |
| ERR11577519 | SJ16S_051 | 138/156/285/463/467/533/542 | 0.0 | `"`–`M` (Q1–Q44) | 26.4 / 28.7 / 27.9 / 27.4 / 26.9 | 41 |
| ERR10966916 | MOITS_062 | 116/128/203/401/585/594/602 | 0.0 | `"`–`M` (Q1–Q44) | 29.9 / 28.6 / 25.4 / 27.0 / 24.0 | 16 |
| ERR10967040 | MOITS_186 | 177/190/353/354/354/444/595 | 0.0 | `"`–`M` (Q1–Q44) | 30.1 / 27.5 / 25.7 / 29.1 / 27.7 | 57 |

| run | sample | 27F % | 27F offset (top) | prefix before 27F (top) | 534Rrc % (median pos) | 534R at start % | 27F-rc % | A-adaptor % | P1 % | P1-rc % | starts CTCAG % | starts GAT % |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ERR10966608 | MO16S_023 | 0.0 | – | – | 0.05 (481.0) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.05 |
| ERR10966653 | MO16S_068 | 0.0 | – | – | 0.0 (–) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 69.35 |
| ERR10966698 | MO16S_113 | 0.0 | – | – | 0.0 (–) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 56.25 |
| ERR10966742 | MO16S_157 | 0.0 | – | – | 0.0 (–) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| ERR10966787 | MO16S_202 | 0.0 | – | – | 0.0 (–) | 0.0 | 0.0 | 0.0 | 0.0 | 0.4 | 0.0 | 58.1 |
| ERR10966832 | MO16S_247 | 0.0 | – | – | 0.05 (490.0) | 0.0 | 0.0 | 0.0 | 0.0 | 0.3 | 0.0 | 81.2 |
| ERR11577485 | SJ16S_007 | 67.0 | 3:1331, 4:4, 2:3 | GAT:1328, GT:2 | 26.55 (174.0) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.4 |
| ERR11577493 | SJ16S_022 | 66.75 | 3:1317, 2:14, 4:2 | GAT:1316, GT:14 | 29.9 (179.0) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 98.9 |
| ERR11577518 | SJ16S_036 | 70.75 | 3:1352, 2:60, 1:2 | GAT:1351, GT:60 | 26.0 (178.0) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 96.5 |
| ERR11577519 | SJ16S_051 | 32.45 | 3:648, 4:1 | GAT:648, GATG:1 | 56.85 (174.0) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 99.8 |
| ERR10966916 | MOITS_062 | 0.0 | – | – | 0.0 (–) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| ERR10967040 | MOITS_186 | 0.0 | – | – | 0.0 (–) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |

### g. Top 10 25-nt read prefixes per run

**ERR10966608 MO16S_023**
```
 1212  GACGAACGCTGGCGGCGTGCCTAAT
  625  AACGAACGCTGGCGGCAGGCTTAAC
   15  AACGAACGCTGCGGCAGGCTTAACA
   14  ACGAACGCTGGCGGCGTGCCTAATA
   11  GACGACGCTGGCGGCGTGCCTAATA
    9  ATTGAACGCTGGCGGCAGGCCTAAC
    6  GACGAACGCTGGCGGCGTGCCTATA
    6  GACGAACGCTGGCGCGTGCCTAATA
    5  AACGAACGCTGGCGCAGGCTTAACA
    3  GACGAACGGCTGGCGGCGTGCCTAA
```
**ERR10966653 MO16S_068**
```
  853  GATGAACGCTAGCTACAGGCTTAAC
  242  GACGAACGCTGGCGGCGTGCCTAAT
  129  GATGAACGCTAGCGGCAGGCCTAAC
  111  GATGAACGCTGGCGGCGTGCTTAAC
   97  GATGAACGCTGGCGGCGTGCCTAAC
   92  AACGAACGCTGGCGGCAGGCTTAAC
   47  GATGAACGCTAGCGACAGGCTTAAC
   41  GATGAACGCTAGCGGCAGGCTTAAC
   32  TATGAACGCTAGCTACAGGCTTAAC
   31  GAGAACGCTAGCTACAGGCTTAACA
```
**ERR10966698 MO16S_113**
```
  730  GATGAACGCTGGCGGCGTGCTTAAC
  297  GACGAACGCTGGCGGCGTGCCTAAT
  211  GATGAACGCTGGCGGCGTGCCTAAC
  176  ATTGAACGCTGGCGGCAGGCCTAAC
  121  AACGAACGCTGGCGGCAGGCTTAAC
  119  GACGAACGCTGGCGGCGCGCCTAAC
   43  GACGAACGCTGGCGCGCGCCTAACA
   40  GACGAACGCTGGCGGCGTGCCTAAC
   34  GATGAACGCTGGCGCGTGCTTAACA
   30  GATGAACGCTGGCGGCATGCCTAAT
```
**ERR10966742 MO16S_157**
```
  923  AACGAACGCTGGCGGCAGGCTTAAC
  912  GACGAACGCTGGCGGCGTGCCTAAT
   34  AACGAACGCTGCGGCAGGCTTAACA
   12  ACGAACGCTGGCGGCGTGCCTAATA
   12  ATTGAACGCTGGCGGCATGCCTTAC
   10  AACGAACGCTGGCGCAGGCTTAACA
    8  GACGACGCTGGCGGCGTGCCTAATA
    6  ATTGAACGCTGGCGGCAGGCCTAAC
    5  GACGAACGCTGGCGGCAGGCTTAAC
    4  GACGAACGCTGGCGCGTGCCTAATA
```
**ERR10966787 MO16S_202**
```
  713  GATGAACGCTGGCGGCGTGCTTAAC
  411  GACGAACGCTGGCGGCGTGCTTAAC
  169  ATTGAACGCTGGCGGCAGGCCTAAC
  166  GATGAACGCTGACAGAATGCTTAAC
  151  GATGAACGCTGGCGGCGTGCCTAAT
   89  GACGAACGCTGGCGGCGTGCCTAAT
   74  GATGAACGCTGGCGGCATGCCTAAT
   71  AACGAACGCTGGCGGCAGGCTTAAC
   21  GACGAACGCTGGCGGCGTGCCTAAC
   10  AGTGAACGCTGGCGGCGTGCCTAAT
```
**ERR10966832 MO16S_247**
```
  875  GATGAACGCTAGCTACAGGCTTAAC
  333  GATGAACGCTGGCGGCGTGCTTAAC
  251  GATGAACGCTGGCGGCGTGCCTAAC
  193  GACGAACGCTGGCGGCGTGCCTAAC
   67  GACGAACGCTGGCGGCGCGCCTAAC
   35  GATGAACGCTAGCGACAGGCCTAAC
   30  GACGAACGCTGGCGGCGTGCTTAAC
   19  GATGAACGCTAGCGACAGGCTTAAC
   17  GATGAACGCTGGCGGCGTGCTTAAT
   15  AACGAACGCTGGCGGCAGGCTTAAC
```
**ERR11577485 SJ16S_007**
```
 1179  GATAGAGTTTGATCGTGGCTCAGGA
  325  GATCCTACGGGGGGCAGCAGTGAGG
  120  GATCCTACGGGGGGCACCAGTGAGG
   77  GATAGAGTTTGATCGTGGCTCAGAT
   45  GATCCTACGGGGGGCAGCAGTGGGG
   19  GATCCTACGGGGGGCACCGAGTGAG
   18  GATCCTACGGGGGGCACCAGTGGGG
   15  GATAGAGGTTTGATCGTGGCTCAGG
   13  GATAGAGTTTGATCGTGGCTCAGAA
   12  GATCCTACGGGGGGGCAGCAGTGAG
```
**ERR11577493 SJ16S_022**
```
 1105  GATAGAGTTTGATCGTGGCTCAGGA
  317  GATCCTACGGGGGGCAGCAGTAGGG
  190  GATCCTACGGGGGGCACCAGTAGGG
  128  GATAGAGTTTGATCGTGGCTCAGAA
   46  GATCCTACGGGGGGCAGCAGTGGGG
   26  GATCCTACGGGGGGCACCAGTGGGG
   14  GATCCTACGGGGGCAGCAGTAGGGA
   11  GTAGAGTTTGATCGTGGCTCAGGAC
    9  GATAGAGTTTTGATCGTGGCTCAGG
    9  GATAGAGTTTGATCGTGGCTCAGAT
```
**ERR11577518 SJ16S_036**
```
  865  GATAGAGTTTGATCGTGGCTCAGAT
  378  GATAGAGTTTGATCGTGGCTCAGGA
  224  GATCCTACGGGGGGCAGCAGTGGGG
  139  GATCCTACGGGGGGCACCAGTGGGG
   89  GATCCTACGGGGGGCAGCAGTAGGG
   58  GATCCTACGGGGGGCACCAGTAGGG
   46  GTAGAGTTTGATCGTGGCTCAGATT
   25  GATAGAGTTTGATCGTGGCTCAGAA
   15  GATAGAGGTTTGATCGTGGCTCAGA
    9  GTAGAGTTTGATCGTGGCTCAGGAC
```
**ERR11577519 SJ16S_051**
```
  667  GATCCTACGGGGGGCAGCAGTGAGG
  536  GATAGAGTTTGATCGTGGCTCAGGA
  293  GATCCTACGGGGGGCACCAGTGAGG
   96  GATCCTACGGGGGGCAGCAGTAGGG
   59  GATCCTACGGGGGGCACCAGTAGGG
   42  GATCCTACGGGGGGGCAGCAGTGAG
   32  GATCCTACGGGGGGGCACCAGTGAG
   18  GATCCTACGGGGGGCAGCAGTGGGG
   17  GATAGATTTGATCGTGGCTCAGGAT
   17  GATAGAGTTTGATCGTGGCTCAGAT
```
**ERR10966916 MOITS_062**
```
 1723  CCGCCCGTCGCTAGTACCGATTGAA
   94  CCGCCCGTCGCTCCTACCGATTGAA
   54  CCGCCCGTCGCTACTACCGATTGAA
    9  CCGCCCGTCACACCACGAGAGTCGG
    8  CGCCCGTCGCTAGTACCGATTGAAT
    6  CCGCCCATCGCTAGTACCGATTGAA
    6  CCGCCCGTCGCTAGTACCGATTGGA
    5  CCGCCCGTCGCTAGTACCGGTTGAA
    5  CCGCCCGTCGCTTAGTACCGATTGA
    4  CCGCCCGTCGTAGTACCGATTGAAT
```
**ERR10967040 MOITS_186**
```
 1670  CCACTGGAGTCCGGGCAGACCGTCA
   70  CCGCCCGTCGCTACTACCGATTGAA
   69  CCGCCCGTCACACCACGAGAGTCGG
   36  CCGCCCGTCGCTAGTACCGATTGAA
   19  CCGCCCGTCGCTCCTACCGATTGAA
   17  CCGCCCGTCGCTCCTACCGATTTTG
   10  CCGCCCGTCACACCATGGGAGTGGA
    9  CCACTGGAGTCCGGGCAGACCGTCG
    8  CCACTGGGGTCCGGGCAGACCGTCA
    8  CCACTCGGAGTCCGGGCAGACCGTC
```

## Read-population breakdown (step2b) — the key finding

| cohort | how reads start | how reads end |
|---|---|---|
| **MO16S** (all 6 runs) | **100% start immediately after 27F**, at E. coli pos ~28 (`GACGAACGCT…`, `AACGAACGCT…`, `ATTGAACGCT…`, `GATGAACGCT…`). There is no primer, no `GAT` and no barcode. | Full-length reads end in a fixed motif `…GTGCCAGCAGCC(C)CGGTCAGG` (the dominant 3′ 20-mer in every run) |
| **SJ16S** V1-V3 (32–71% of reads) | `GAT` + 27F at offset 3 (99.5–99.9% of hits have `GAT` immediately before the primer). The barcode itself is gone. | Same `…GCCAGCAGCCCCGGTCAGG` motif |
| **SJ16S** second amplicon (29–68%) | `GAT` + `CCTACGGGGGGCA(G/C)CAG…`, which fits **Pro341F `CCTACGGGNBGCASCAG`** | `…ATTAGATACCCCCGTAGTCGG`, which fits the **Pro805R rc `GGATTAGATACCCBNGTAGTC`**. This is a **V3-V4 amplicon**, ~465–470 nt. |

Notes:
- The leading `GATGAACGCT…` in MO reads is **biological**, not a barcode adaptor. It is the post-27F sequence of Bacteroides and Bifidobacterium. Its frequency tracks composition (0% in MO16S_023/157 and 56–81% in the others), and no 27F follows it.
- The 534R-rc hits in SJ (26–57% of reads, at position ~174–180) are **not** amplicon ends. They are the conserved 515–534 region inside V3-V4 reads, and those reads continue on (`…GGTAAT|ACGGAGGATCCGAGC…`).
- The SJ V1-V3 reads' 27F differs from the published primer at position 12. In 4,474/4,493 hits that base is **G**, but the primer has M = A/C (`GATCGTGG` vs `GATCMTGG`). That mismatch is why 27F hits were mostly at edit distance 1.

## Verdicts

**1. Are barcodes/adaptors still present? — Mixed, and MO and SJ differ.**
- MO16S: **no.** Barcode, `GAT` barcode adaptor and 27F are all gone. A-adaptor, P1, P1-rc and `CTCAG` are each ≤0.4% in every run.
- SJ16S: the **barcode is gone but the 3-nt `GAT` barcode adaptor is still on** in ~97–99% of reads. There is no A or P1 adaptor, and no `CTCAG` key/adaptor remnant.
- Both cohorts have 3′ P1 already removed. Reads end cleanly at the amplicon end, consistent with Torrent Suite adaptor trimming.

**2. Is 27F present, and where? Is 534R rc present? — MO: absent. SJ: present at offset 3 in the V1-V3 subset only.**
- MO16S: 0.0% 27F in all 6 runs (already trimmed).
- SJ16S: 27F appears in 67.0 / 66.8 / 70.8 / 32.5% of reads, at offset 3 (after `GAT`). The rest of each SJ run is the V3-V4 amplicon.
- The **exact 534R rc (`GCCAGCAGCCGCGGTAAT`) is essentially absent at the 3′ ends** (≤0.05% in MO).
- Instead, full-length V1-V3 reads end in `GCCAGCAGCC` + `CCGGTCAGG`. That shares the first 10 nt of the 534R rc and then diverges. It is consistent across cohorts and taxa, so it looks systematic (the primer as synthesized or deposited) rather than sequencing error.
- cutadapt at error 0.1 would **not** strip this tail with the published 534R rc. That doesn't matter if the truncation length is ≤ ~400 (see point 5).

**3. Are the primers right? — Mostly, with three corrections.**
- (a) 27F position 12 is G in the data. Use `AGAGTTTGATCNTGGCTCAG`; with N, cutadapt doesn't spend one of its two allowed errors on this base.
- (b) The 3′ end does not match 534R rc. Don't rely on `REV_PRIMER_RC` to remove it.
- (c) **The SJ runs contain a second, V3-V4 amplicon (Pro341F/Pro805R-like) that the paper's methods don't describe.** It must be excluded from a V1-V3 analysis. The 27F `--p-discard-untrimmed` gate does this automatically: none of these reads contain 27F.
- The ITS control behaves as expected: 27F is 0.0% in both MOITS runs, which start with ITS1-region sequence (`CCGCCCGTCG…`, `CCACTGGAGT…`).

**4. Were the reads already trimmed by the authors?**
- **Primer trimming:** yes for MO (5′ only). No for SJ.
- **Quality trimming: no.** The reads do not look Trimmomatic SLIDINGWINDOW 25:20 trimmed in either cohort.
  - Only 17–51% of reads have every 25-bp window at mean Q≥20.
  - The median Q of the last 10 bases is ~18–23.
  - Q1/Q2 bases are present.
  - The variable lengths come from amplicon-length differences between taxa (tight per-taxon length modes, e.g. 498 / 449 / 508) plus Ion read-end attrition. They are not a clean quality trim.
- **Likely history:** both cohorts are Torrent Suite output, demultiplexed with 3′ adaptors removed. MO was then 5′ trimmed (barcode adaptor + 27F); SJ was deposited without that step. The MO accessions (ERR1096…) and SJ accessions (ERR1157…) were also deposited at different times.

**5. Recommended settings — this cannot be one uniform study config.**
- MO needs **no** forward-primer trim. With `FWD_PRIMER` set, `--p-discard-untrimmed` would **discard ~100% of MO reads**.
- SJ **needs** the 27F trim, both to strip `GAT`+primer and to drop the V3-V4 reads.
- After their respective handling, both cohorts start at the same coordinate (base after 27F), so their ASVs at a common truncation length are directly comparable and mergeable.

Simulated DADA2 pyro filter (`trunc-q 2` → length ≥ T → `max-ee 2`). Pooled over the sampled runs, as % of **all** reads; the SJ denominator includes the V3-V4 reads that cutadapt drops:

| T | MO len≥T | MO +maxEE2 | SJ len≥T | SJ +maxEE2 |
|---|---|---|---|---|
| 150 | 96.2 | 86.8 | 56.3 | 49.7 |
| 200 | 91.7 | 77.9 | 53.0 | 43.3 |
| 250 | 88.8 | 71.7 | 50.6 | 39.4 |
| 275 | 87.3 | 68.1 | 49.1 | 36.7 |
| 300 | 85.5 | 64.6 | 47.4 | 34.5 |
| 350 | 82.1 | 57.0 | 45.4 | 30.9 |
| 400 | 75.9 | 47.1 | 41.9 | 26.5 |
| 450 | 60.0 | 29.2 | 35.9 | 20.5 |

**Provisional PYRO_TRUNC_LEN: 250, range 200–300.**
- At 250, MO loses ~11% of reads to length and ~28% overall. SJ V1-V3 keeps ~78% of its 27F reads (39.4 of 50.6).
- Every value ≤400 stays clear of the odd 3′ tail; amplicon ends sit at ~430–510 nt post-primer.
- Above 350, EE losses climb steeply.
- Use the **same** value for MO and SJ so the ASVs share coordinates.
- Confirm against `demux_viz.qzv` / `demux_trimmed_viz.qzv`. These numbers come from each run's first 2,000 reads only.

### Option A (recommended) — split into two pipeline units
One unit is MO16S (269 runs, no primer trim); the other is SJ16S (54 runs, 27F trim). Run both with identical denoise params and merge downstream.
This is a structural decision for you: it means a second study name or an accession-filtered RawData. It also affects `run_accessions.txt`, the CHPC sparse-checkout list and Merging.

MO16S block:
```bash
LAYOUT="single"
DENOISER="pyro"
# MO16S deposit is already 5'-trimmed (barcode + GAT + 27F gone; reads start at E. coli ~28).
# Leave both empty: 03_trim_single skips, denoise uses demux.qza. A FWD_PRIMER here would
# discard ~100% of reads via --p-discard-untrimmed.
FWD_PRIMER=""
REV_PRIMER_RC=""                 # 3' end is …GCCAGCAGCCCCGGTCAGG, not 534R-rc; truncation removes it anyway
PYRO_TRUNC_LEN=250               # provisional (200–300); keep identical to the SJ unit
PYRO_TRIM_LEFT=0
PYRO_MAX_EE=2.0
PYRO_TRUNC_Q=2
PYRO_CHIMERA="consensus"
PYRO_THREADS=16
```

SJ16S block:
```bash
LAYOUT="single"
DENOISER="pyro"
# SJ16S deposit keeps the 3-nt 'GAT' barcode adaptor + 27F (offset 3) and ALSO contains a V3-V4
# (Pro341F/Pro805R-like) amplicon in ~30-68% of reads. Anchoring on 27F with discard-untrimmed
# strips GAT+primer AND drops the V3-V4 reads. Position 12 is G in the data, so use N, not M.
FWD_PRIMER="AGAGTTTGATCNTGGCTCAG"
REV_PRIMER_RC=""                 # published 534R-rc doesn't match the observed 3' tail; trunc handles it
CUTADAPT_OVERLAP=15              # require (nearly) the whole primer, no 3-nt partial 5' matches
PYRO_TRUNC_LEN=250               # identical to the MO unit
PYRO_TRIM_LEFT=0
PYRO_MAX_EE=2.0
PYRO_TRUNC_Q=2
PYRO_CHIMERA="consensus"
PYRO_THREADS=16
```
No positional 5′ trim is needed before cutadapt. In SJ, `GAT` sits in front of the primer and `--p-front` removes everything up to and including it.

### Option B — single unit (not recommended)
Using the SJ block for all 323 runs throws away MO. Using the MO block for all runs leaves `GAT`+27F (23 nt) on SJ V1-V3 reads and lets SJ V3-V4 reads into the V1-V3 table.
The only single-unit route is to pre-trim the SJ FASTQs outside QIIME before import: keep reads with `^GAT`+27F, strip through the primer, and drop the rest. Then use the MO block for everything.

### Before importing (either option)
`$WORK_BASE/Orberg2024/RawData` currently holds the 247 ITS FASTQs too, and the single-end manifest picks up every FASTQ in that directory. The ITS runs (and, for option A, the other cohort) need to be out of the import directory, or the manifest step needs filtering against `run_accessions_16S.txt`. I made no changes here.

### Caveats
- These are the first 2,000 reads per run, at the head of each file. Head-of-file reads can be slightly shorter or lower quality than the run average.
- SJ16S_051 has an unusually high V3-V4 share (68%), so SJ read yield per sample will vary a lot.
- The 3′ `CCGGTCAGG` motif is unexplained. I'd confirm against the paper's supplementary primer table if it ever matters, i.e. only if you truncate past ~420.
