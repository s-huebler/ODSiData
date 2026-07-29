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
| Build manifest | CHPC | `lib/make_manifest_paired.sh` |
| Import → demux → **DADA2** → summaries → export FASTA | CHPC | `jobs/02_import_dada2.slurm` |
| **BLAST** human decontam + 16S classification | **local Mac** | `<Study>/Preprocessing.qmd` |
| Filtering, Greengenes2, trees, taxonomy | local Mac | `<Study>/Preprocessing.qmd` |

The DADA2 job exports `rep-seqs.qza` to `dna-sequences.fasta` and copies it plus
`table.qza` / `rep-seqs.qza` / `stats.qza` and the `.qzv` summaries back into
`<Study>/QiimeData/`. That FASTA is exactly the input the BLAST chunk expects.

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
./chpc/submit.sh Artacho2024          # submits fetch array + DADA2 (chained)
squeue -u $USER                       # watch progress; logs in chpc/logs/

# when the DADA2 job finishes it has copied artifacts into Artacho2024/QiimeData/
git add Artacho2024/QiimeData
git commit -m "[Artacho2024] DADA2 table/rep-seqs from CHPC"
git push

# --- back on your Mac ----------------------------------------------------
git pull
# open Artacho2024/Preprocessing.qmd and run the BLAST Analysis section onward
```

## First-time setup on CHPC

1. **Set your allocation.** Edit `chpc/config.sh` and set `CHPC_ACCOUNT` (and
   `CHPC_PARTITION` if not `notchpeak`). Or export them at submit time.
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

## Notes / gotchas

- **Verify DADA2 truncation.** Trim/trunc values come from each paper's methods
  but should be checked against `demux_viz.qzv` (interactive quality plot) before
  you trust the run. For a first pass you can submit `fetch` only, inspect the
  quality plot, set the numbers, then submit `dada2`.
- **Partial submissions:** `./chpc/submit.sh <Study> fetch` or `... dada2`.
- **Re-runs are cheap:** the fetch array skips SRRs whose FASTQs already exist;
  failed downloads are logged to `<scratch>/<Study>/failed_downloads.txt`.
- **Throttle downloads** with `ARRAY_THROTTLE=10 ./chpc/submit.sh ...` if NCBI
  rate-limits.
