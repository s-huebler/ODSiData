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

cat("dada2 version:", as.character(packageVersion("dada2")), "\n")
cat("R version    :", R.version.string, "\n")
cat("Input dir    :", cut_dir, "\n\n")

fns <- sort(list.files(cut_dir, pattern = "\\.fastq(\\.gz)?$", full.names = TRUE))
if (!length(fns)) stop("No FASTQs in ", cut_dir, " -- run scripts/02_trim.sh first.")
samples <- sub("\\.fastq(\\.gz)?$", "", basename(fns))
cat("Samples:", length(samples), "\n\n")

filts <- file.path(filt_dir, paste0(samples, "_filt.fastq.gz"))
names(filts) <- samples

# ---- filterAndTrim ---------------------------------------------------------
cat("== filterAndTrim ==\n")
track_filt <- filterAndTrim(
  fwd        = fns,
  filt       = filts,
  trimLeft   = 15,      # REPORTED
  maxEE      = 5,       # REPORTED ("minEE value of 5")
  truncQ     = 2,       # ASSUMPTION: dada2 default
  maxN       = 0,       # ASSUMPTION: dada2 default (required by dada())
  minLen     = 50,      # ASSUMPTION: guards against Ion Torrent runt reads
  rm.phix    = FALSE,   # ASSUMPTION: PhiX is an Illumina control, not Ion Torrent
  compress   = TRUE,
  multithread = TRUE,
  verbose    = TRUE
)
rownames(track_filt) <- samples
print(head(track_filt))

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
  multithread             = TRUE,
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
  multithread             = TRUE,
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
                                multithread = TRUE, verbose = TRUE)
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
