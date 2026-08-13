#!/usr/bin/env Rscript
# Step 3 — DADA2 ASV inference, Ion Torrent settings, per Jarosch et al. 2023.
#
# Run INSIDE the container:
#   ./docker/run.sh Rscript scripts/03_dada2.R
#
# Reported methods, verbatim:
#   "Amplicon sequence variants (ASV) were retrieved from processed reads in
#    R (4.1.1) using the dada2 (1.16) package. Here, 15 bp were trimmed from
#    5'-ends of each read, and the dada2 command was executed while a minEE
#    value of 5, a HOMOPOLYMER_GAP_PENALTY of -1 and a BAND_SIZE of 32 were
#    applied."
#
# Mapping of those statements onto dada2 API calls:
#   "15 bp trimmed from 5'-ends"      -> filterAndTrim(trimLeft = 15)
#   "minEE value of 5"                -> filterAndTrim(maxEE = 5)
#                                        (dada2 has no minEE; maxEE is the only
#                                         expected-error filter, so this is the
#                                         intended parameter)
#   HOMOPOLYMER_GAP_PENALTY = -1      -> dada(HOMOPOLYMER_GAP_PENALTY = -1)
#   BAND_SIZE = 32                    -> dada(BAND_SIZE = 32)
# The last two are exactly DADA2's documented Ion Torrent recommendation.
#
# NOT reported, and therefore assumed (flagged inline as ASSUMPTION):
#   - truncQ / maxN / minLen in filterAndTrim
#   - pool = FALSE vs TRUE in dada()
#   - whether chimeras were removed at all, and with which method
# Each assumption is a knob to turn if step 4 shows a mismatch.

suppressPackageStartupMessages({
  library(dada2)
})

set.seed(20230101)  # ASSUMPTION: seed not reported; fixed here for reproducibility

# Repro root: /work inside the container, REPRO_DIR or cwd otherwise.
repro <- Sys.getenv("REPRO_DIR", unset = "")
if (!nzchar(repro)) repro <- if (dir.exists("/work/data")) "/work" else getwd()
if (!dir.exists(file.path(repro, "data"))) {
  stop("Cannot locate Repro/data under '", repro,
       "'. Set REPRO_DIR to the Jarosch2023/Repro path.")
}

cut_dir  <- file.path(repro, "data", "cutadapt")
filt_dir <- file.path(repro, "data", "filtered")
res_dir  <- file.path(repro, "results")
log_dir  <- file.path(repro, "logs")
dir.create(filt_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(res_dir,  showWarnings = FALSE, recursive = TRUE)
dir.create(log_dir,  showWarnings = FALSE, recursive = TRUE)

# ---------------------------------------------------------------------------
# Threading.
#
# This image is linux/amd64 running under emulation on Apple Silicon. R's
# multicore backend (mclapply/mcmapply, which dada2 uses when
# multithread = TRUE) forks, and forked workers die unpredictably under
# emulation -- they return no result and dada2 fails with a confusing
#   'names' attribute [53] must be the same length as the vector [44]
# because some jobs silently vanished.
#
# Default is therefore serial. Serial is also fully deterministic, which is
# what we want for a replication. Override at your own risk:
#   NCORES=4 ./docker/run.sh Rscript scripts/03_dada2.R
# ---------------------------------------------------------------------------
ncores <- suppressWarnings(as.integer(Sys.getenv("NCORES", "1")))
if (is.na(ncores) || ncores < 1) ncores <- 1
mt <- if (ncores > 1) ncores else FALSE

cat("dada2 version:", as.character(packageVersion("dada2")), "\n")
cat("R version    :", R.version.string, "\n")
cat("Input dir    :", cut_dir, "\n")
cat("Threads      :", if (isFALSE(mt)) "1 (serial)" else mt, "\n\n")

fns <- sort(list.files(cut_dir, pattern = "\\.fastq(\\.gz)?$", full.names = TRUE))
if (!length(fns)) stop("No FASTQs in ", cut_dir, " -- run scripts/02_trim.sh first.")
samples <- sub("\\.fastq(\\.gz)?$", "", basename(fns))
cat("Samples:", length(samples), "\n\n")

filts <- file.path(filt_dir, paste0(samples, "_filt.fastq.gz"))
names(filts) <- samples

# ---- filterAndTrim ---------------------------------------------------------
cat("== filterAndTrim ==\n")
# One file per call, so a failure names the offending sample instead of
# surfacing as a vector-length mismatch after the fact.
track_filt <- matrix(NA_real_, nrow = length(samples), ncol = 2,
                     dimnames = list(samples, c("reads.in", "reads.out")))
filt_errors <- character(0)

for (i in seq_along(samples)) {
  s <- samples[i]
  res <- tryCatch(
    filterAndTrim(
      fwd        = fns[i],
      filt       = filts[i],
      trimLeft   = 15,      # REPORTED
      maxEE      = 5,       # REPORTED ("minEE value of 5")
      truncQ     = 2,       # ASSUMPTION: dada2 default
      maxN       = 0,       # ASSUMPTION: dada2 default (required by dada())
      minLen     = 50,      # ASSUMPTION: guards against Ion Torrent runt reads
      rm.phix    = FALSE,   # ASSUMPTION: PhiX is an Illumina control, not Ion Torrent
      compress   = TRUE,
      multithread = FALSE,  # already serial at this level
      verbose    = FALSE
    ),
    error = function(e) {
      filt_errors <<- c(filt_errors, paste0(s, ": ", conditionMessage(e)))
      NULL
    }
  )
  if (!is.null(res)) track_filt[i, ] <- as.numeric(res[1, 1:2])
  cat(sprintf("  [%2d/%2d] %-14s in=%s out=%s\n", i, length(samples), s,
              format(track_filt[i, 1], big.mark = ","),
              format(track_filt[i, 2], big.mark = ",")))
}

if (length(filt_errors)) {
  cat("\nfilterAndTrim failed on", length(filt_errors), "sample(s):\n")
  cat(paste0("  ", filt_errors, collapse = "\n"), "\n")
  stop("Fix the inputs above before continuing.")
}
cat("\nTotal reads in :", format(sum(track_filt[, 1]), big.mark = ","), "\n")
cat("Total reads out:", format(sum(track_filt[, 2]), big.mark = ","), "\n")

# Drop samples that lost everything, or learnErrors/dada will error out.
keep  <- track_filt[, "reads.out"] > 0
if (any(!keep)) {
  cat("\nDropping empty samples after filtering:",
      paste(samples[!keep], collapse = ", "), "\n")
}
filts   <- filts[keep]
samples <- samples[keep]

# ---- learn error rates -----------------------------------------------------
cat("\n== learnErrors ==\n")
err <- learnErrors(
  filts,
  multithread             = mt,
  HOMOPOLYMER_GAP_PENALTY = -1,   # REPORTED
  BAND_SIZE               = 32,   # REPORTED
  randomize               = TRUE,
  verbose                 = TRUE
)
saveRDS(err, file.path(res_dir, "errors.rds"))

pdf(file.path(res_dir, "03_error_rates.pdf"), width = 8, height = 7)
print(plotErrors(err, nominalQ = TRUE))
dev.off()

# ---- dereplicate + denoise -------------------------------------------------
cat("\n== derepFastq + dada ==\n")
derep <- derepFastq(filts, verbose = TRUE)
names(derep) <- samples

dd <- dada(
  derep,
  err                     = err,
  multithread             = mt,
  HOMOPOLYMER_GAP_PENALTY = -1,   # REPORTED
  BAND_SIZE               = 32,   # REPORTED
  pool                    = FALSE # ASSUMPTION: dada2 default; try TRUE if mismatched
)

seqtab <- makeSequenceTable(dd)
cat("\nASVs (pre-chimera):", ncol(seqtab), "\n")
cat("Amplicon length distribution:\n")
print(table(nchar(getSequences(seqtab))))
saveRDS(seqtab, file.path(res_dir, "seqtab_prechimera.rds"))

# ---- chimera removal -------------------------------------------------------
# ASSUMPTION: the paper does not mention chimera removal. Both tables are
# written so step 4 can compare either against the published metrics.
cat("\n== removeBimeraDenovo (consensus) ==\n")
seqtab_nc <- removeBimeraDenovo(seqtab, method = "consensus",
                                multithread = mt, verbose = TRUE)
cat("ASVs (post-chimera):", ncol(seqtab_nc), "\n")
cat("Fraction of reads retained:", sum(seqtab_nc) / sum(seqtab), "\n")
saveRDS(seqtab_nc, file.path(res_dir, "seqtab_nochim.rds"))

# ---- read tracking ---------------------------------------------------------
getN <- function(x) sum(getUniques(x))
track <- cbind(
  track_filt[samples, , drop = FALSE],
  denoised   = if (length(samples) == 1) getN(dd) else sapply(dd, getN),
  nonchim    = rowSums(seqtab_nc)[samples]
)
colnames(track)[1:2] <- c("raw_in", "filtered")
write.table(track, file.path(res_dir, "03_read_tracking.tsv"),
            sep = "\t", quote = FALSE, col.names = NA)
cat("\n== read tracking ==\n")
print(track)

# ---- flat ASV table + FASTA ------------------------------------------------
asv_seqs <- colnames(seqtab_nc)
asv_ids  <- paste0("ASV", seq_along(asv_seqs))
writeLines(as.vector(rbind(paste0(">", asv_ids), asv_seqs)),
           file.path(res_dir, "asv_sequences.fasta"))

out <- seqtab_nc
colnames(out) <- asv_ids
write.table(out, file.path(res_dir, "asv_table.tsv"),
            sep = "\t", quote = FALSE, col.names = NA)

cat("\nWrote:\n",
    "  results/seqtab_nochim.rds\n",
    "  results/seqtab_prechimera.rds\n",
    "  results/asv_table.tsv\n",
    "  results/asv_sequences.fasta\n",
    "  results/03_read_tracking.tsv\n",
    "  results/03_error_rates.pdf\n", sep = "")

sessionInfo()
