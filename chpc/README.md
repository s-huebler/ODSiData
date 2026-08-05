# CHPC preprocessing workflow

Runs the 16S preprocessing pipeline — everything from `Preprocessing.qmd` **up
to (not including) the BLAST Analysis section** — on the University of Utah CHPC
via SLURM. The heavy, long-running steps (SRA download of hundreds of runs, and
DADA2 denoising) run on compute nodes; BLAST decontamination stays local because
it needs your `~/blast_databases` and rBLAST.

CHPC is native x86 Linux, so **no Rosetta** here (that's only for QIIME2 on the
Mac). QIIME2 is loaded via `module load` on CHPC.

## What runs where

| Stage | Where | Script |
|-------|-------|--------|
| Fetch SRA runs (`prefetch` + `fasterq-dump`) | CHPC (job array) | `jobs/01_fetch.slurm` |
| Build manifest + import + demux summary | CHPC | `jobs/02_import.slurm` |
| *(inspect `demux_viz.qzv`)* | local | — |
| **Trim** primers with cutadapt → demux_trimmed summary | CHPC | `jobs/03_trim_paired.slurm` |
| *(inspect `demux_trimmed_viz.qzv`, set trunc lengths)* | local | — |
| **Denoise** (DADA2/Deblur) → summaries → export FASTA | CHPC | `jobs/04_dada2_paired.slurm` |
| **BLAST** human decontam + 16S classification | **local Mac** | `<Study>/Preprocessing.qmd` |
| **QC gate** — GG2 classify-consensus-vsearch, drop unconfident ASVs | CHPC | `jobs/05_qc.slurm` |
| **Map** ASVs onto the GG2 backbone (non-v4-16s) | CHPC | `jobs/06_gg2_map.slurm` |
| Filtering, trees, downstream taxonomy | local Mac | `<Study>/Preprocessing.qmd` |

The stages after import are **layout-aware** — the study file's `LAYOUT`
(`paired`/`single`) and `DENOISER` (`deblur`/`pyro`/`dada2-single`) pick the
matching jobs, so you always call the generic `trim` and `denoise` stages:

| Layout | Import | Trim | Denoise |
|--------|--------|------|---------|
| `paired` | `02_import.slurm` | `03_trim_paired.slurm` | `04_dada2_paired.slurm` |
| `single` + `deblur` | `02_import_single.slurm` | `03_trim_single.slurm` | `04_deblur.slurm` |
| `single` + `pyro` | `02_import_single.slurm` | `03_trim_single.slurm` | `04_dada2_pyro.slurm` |
| `single` + `dada2-single` | `02_import_single.slurm` | `03_trim_single.slurm` | `04_dada2_single.slurm` |

Import, trim, and denoise are split on purpose. `02_import` stops at
`demux_viz.qzv` so you can read the quality plots. **Trim** (cutadapt) then
strips primers by sequence into `demux_trimmed.qza` and writes a fresh
`demux_trimmed_viz.qzv` so you can choose `--p-trunc-len` on the primer-free
reads. If no primers are set in the study file the trim stage is a no-op and
denoise falls back to the raw `demux.qza`. The **denoise** job auto-detects
`demux_trimmed.qza` (prefers it, else raw demux), exports `rep-seqs.qza` to
`dna-sequences.fasta`, and copies it plus `table.qza` / `rep-seqs.qza` /
`stats.qza` and the `.qzv` summaries back into `<Study>/QiimeData/`. That FASTA
is exactly the input the BLAST chunk expects.

## The loop (develop local → push → pull → submit → retrieve)

```
# --- on your Mac ---------------------------------------------------------
# 1. edit params for the study, commit, push
git add chpc/ Artacho2024/RawData/run_accessions.txt
git commit -m "[Artacho2024] add CHPC preprocessing config"
git push

# --- on CHPC -------------------------------------------------------------
ssh <uid>@notchpeak.chpc.utah.edu
cd ~/Documents/ODSi/ODSiData          # your checkout
git pull
./chpc/submit.sh Artacho2024          # fetch array -> import (chained), then STOPS
squeue -u $USER                       # watch progress; logs in chpc/logs/

# import copies demux_viz.qzv into Artacho2024/QiimeData/. Inspect it (view.qiime2.org
# or 'qiime tools view').
./chpc/submit.sh Artacho2024 trim     # cutadapt primer removal (skip if no primers set)

# trim copies demux_trimmed_viz.qzv into Artacho2024/QiimeData/. Inspect it, then set
# TRUNC_LEN_F/TRUNC_LEN_R in chpc/studies/Artacho2024.sh.
./chpc/submit.sh Artacho2024 denoise  # denoise with your chosen trunc lengths

# when DADA2 finishes it has copied artifacts into Artacho2024/QiimeData/
git add Artacho2024/QiimeData chpc/studies/Artacho2024.sh
git commit -m "[Artacho2024] DADA2 table/rep-seqs from CHPC"
git push

# --- back on your Mac ----------------------------------------------------
git pull
# open Artacho2024/Preprocessing.qmd and run the BLAST Analysis section onward

# --- back on CHPC: Greengenes2 mapping (runs AFTER the local BLAST step) --
./chpc/submit.sh Artacho2024 qc       # GG2 classify gate; inspect Mapped/qc-*_viz.qzv
./chpc/submit.sh Artacho2024 map      # map the survivors onto the GG2 backbone
```

## First-time setup on CHPC

1. **Set your allocation.** `chpc/config.sh` defaults to `CHPC_ACCOUNT=qiaox` on
   `CHPC_PARTITION=lonepeak-shared` via `CHPC_CLUSTER=lonepeak` — a shared,
   generous-walltime partition that usually has free nodes. Override any of the
   three at submit time; see "Partitions, clusters & queue waits" below.
2. **Modules** are already set in `config.sh`:
   `sra-toolkit/3.1.1` for downloads, and `anaconda3/2023.03` + `qiime2/2023.5`
   for QIIME2 (anaconda must load first). If those version tags ever change on
   CHPC, run `module spider qiime2` / `module spider sra` and update the
   `load_*_env` functions. Note CHPC runs QIIME2 **2023.5** vs **2025.4** on the
   Mac — artifacts read forward fine, but keep versions noted in the .qmd.
3. Scratch: large files go to `/scratch/general/vast/$USER/ODSiData/<Study>/`
   (override with `SCRATCH_BASE`). Scratch is auto-scrubbed after ~60 days.

## Adding a new study

```
cp chpc/studies/_template.sh chpc/studies/Liu2017.sh
# edit STUDY, DADA2 trim/trunc (verify vs demux_viz.qzv), threads, metadata
./chpc/submit.sh Liu2017
```

## Partitions, clusters & queue waits

These jobs use a few cores + tens of GB — a fraction of a node — so they run on
**shared** partitions, not whole-node ones. Requesting a whole-node partition
makes Slurm wait for an *entire* free node, the main cause of long queue waits
(see CHPC's [slurm-priority-scores](https://www.chpc.utah.edu/documentation/software/slurm-priority-scores.php)).

**Each cluster runs its own Slurm controller,** so a partition is only valid on
its own cluster — submitting a notchpeak/lonepeak partition from a kingspeak
login context fails with `invalid partition specified`. `submit.sh` handles this
through three env vars (defaults in `config.sh`, overridable at submit time):

| Var | Default | Meaning |
|-----|---------|---------|
| `CHPC_CLUSTER` | `lonepeak` | scheduler to submit to (`sbatch --clusters=`); `""` = your login cluster |
| `CHPC_ACCOUNT` | `qiaox` | allocation account (`-A`) — must be paired to the partition |
| `CHPC_PARTITION` | `lonepeak-shared` | partition (`-p`) |

Pair account and partition exactly as `myallocation` lists them. Note sourcing
`config.sh` in your shell *exports* these — a stale export then overrides the
defaults, so `unset CHPC_ACCOUNT CHPC_PARTITION CHPC_CLUSTER` (or open a fresh
shell) if a change isn't taking effect.

**Find a live partition** (up, with idle nodes) across every cluster at once:

```
sinfo -M all -s | grep -iE 'PARTITION|shared|guest|freecycle'
```

Look for `AVAIL=up` and a nonzero **I** (idle) count in the `NODES(A/I/O/T)`
column — that partition will take a job now.

**Fallbacks when the shared partitions are drained/full** (e.g. `kingspeak-shared`
and `lonepeak-shared` both drain). Guest/freecycle partitions are shared with lots
of capacity but **preemptable** — a job can be killed if the node owner reclaims,
so prefer them for short stages (qc/map/import/trim, or denoise on small studies),
not long runs:

```
# free short partition — <=8h, max 2 running jobs:
CHPC_CLUSTER=notchpeak CHPC_ACCOUNT=notchpeak-shared-short CHPC_PARTITION=notchpeak-shared-short ./chpc/submit.sh <Study> <stage>

# guest shared — preemptable, high capacity, no job cap:
CHPC_CLUSTER=notchpeak CHPC_ACCOUNT=owner-guest CHPC_PARTITION=notchpeak-shared-guest ./chpc/submit.sh <Study> <stage>

# freecycle shared — preemptable, no allocation charge:
CHPC_CLUSTER=notchpeak CHPC_ACCOUNT=guo CHPC_PARTITION=notchpeak-shared-freecycle ./chpc/submit.sh <Study> <stage>
```

**Why a bad partition rejects instead of queuing:** if a partition is *up but
full*, Slurm accepts the job and parks it as pending (`PD`, reason
`Resources`/`Priority`). If the partition is `drain`/`inactive`, or you exceed a
hard limit (walltime over the partition max, the job-count cap, a wrong
account/partition pair), sbatch **rejects at submit** and the job never enters
the queue. So `Required partition not available (inactive or drain)` means that
partition is administratively down — switch to a live one from the picker above.

**Monitor across clusters.** Plain `squeue -u $USER` only sees your login
cluster, so a job on another scheduler looks invisible. Add `-M`:

```
squeue -M all -u $USER            # your jobs on every cluster, grouped
scancel -M notchpeak <jobid>      # cancel a job that's off your login cluster
sacct  -M notchpeak -j <jobid>    # accounting / exit status for it
```

**Right-size per stage** in the study file (`IMPORT_MEM`, `DENOISE_MEM`,
`QC_MEM`, `MAP_MEM`, and the matching `*_TIME` / `*_THREADS`) so you request only
what each stage needs — over-asking memory or walltime inflates your queue wait.

## Notes / gotchas

- **Verify DADA2 truncation.** Trim/trunc values come from each paper's methods
  but should be checked against the quality plot before you trust the run — use
  `demux_trimmed_viz.qzv` (post-primer, from the trim stage) if primers were set,
  else `demux_viz.qzv`. For a first pass you can submit `fetch`/`import` only,
  inspect the plot, run `trim`, re-inspect, set the numbers, then submit `denoise`.
- **Partial submissions:** `./chpc/submit.sh <Study> {fetch|import|trim|denoise|qc|map}`.
  The `trim` and `denoise` stages route by the study file's `LAYOUT`/`DENOISER`;
  `qc`/`map` are the Greengenes2 mapping stages that run after the local BLAST step.
- **Re-runs are cheap:** the fetch array skips SRRs whose FASTQs already exist;
  failed downloads are logged to `<scratch>/<Study>/failed_downloads.txt`.
- **Throttle downloads** with `ARRAY_THROTTLE=10 ./chpc/submit.sh ...` if NCBI
  rate-limits.
