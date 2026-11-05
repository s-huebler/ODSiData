# Resumable dada2 1.16 single-end pipeline (per-sample; optional pseudo-pooling pass 2 with priors from pass 1,
# exactly as dada(pool="pseudo") does internally: priors = ASVs present in >= 2 samples of pass 1).
# usage: Rscript dada_resume.R <indir> <outdir> <lib> <mode: per|pseudo> [budget_minutes]
a <- commandArgs(TRUE); indir <- a[1]; out <- a[2]; lib <- a[3]; mode <- a[4]
budget <- if (length(a) >= 5) as.numeric(a[5]) else 100
.libPaths(c(lib, .libPaths())); suppressPackageStartupMessages(library(dada2))
t0 <- Sys.time(); left <- function() budget - as.numeric(difftime(Sys.time(), t0, units="mins"))
dir.create(file.path(out,"filt"), FALSE, TRUE); dir.create(file.path(out,"dd1"), FALSE); dir.create(file.path(out,"dd2"), FALSE)
fns <- sort(list.files(indir, "fastq.gz$", full.names=TRUE)); s <- sub(".fastq.gz","",basename(fns))
filt <- file.path(out,"filt",basename(fns))
todo <- !file.exists(filt)
if (any(todo) && !file.exists(file.path(out,"filt.rds"))) {
  r <- filterAndTrim(fns, filt, trimLeft=15, maxEE=5, multithread=FALSE); saveRDS(r, file.path(out,"filt.rds")) }
keep <- file.exists(filt); filt <- filt[keep]; s <- s[keep]
if (!file.exists(file.path(out,"err.rds"))) {
  set.seed(100); err <- learnErrors(filt, multithread=2, HOMOPOLYMER_GAP_PENALTY=-1, BAND_SIZE=32)
  saveRDS(err, file.path(out,"err.rds")) }
err <- readRDS(file.path(out,"err.rds"))
run_pass <- function(dir, priors=character(0)) {
  for (i in seq_along(s)) { f <- file.path(out, dir, paste0(s[i], ".rds")); if (file.exists(f)) next
    if (left() < 8) { cat("BUDGET_EXHAUSTED\n"); quit(status=3) }
    d <- dada(derepFastq(filt[i]), err=err, multithread=2, HOMOPOLYMER_GAP_PENALTY=-1, BAND_SIZE=32, priors=priors, verbose=FALSE)
    saveRDS(d, f); cat(dir, s[i], format(Sys.time()), "\n") } }
table_of <- function(dir) { dd <- lapply(s, function(x) readRDS(file.path(out,dir,paste0(x,".rds")))); names(dd) <- s; makeSequenceTable(dd) }
run_pass("dd1")
st1 <- table_of("dd1"); saveRDS(st1, file.path(out,"seqtab_pass1.rds"))
st <- st1
if (mode == "pseudo") {
  pr <- colnames(st1)[colSums(st1>0) >= 2]; cat("pseudo priors:", length(pr), "\n")
  run_pass("dd2", pr); st <- table_of("dd2"); saveRDS(st, file.path(out,"seqtab_pseudo.rds")) }
nc <- removeBimeraDenovo(st, method="consensus", multithread=FALSE)
saveRDS(st, file.path(out,"seqtab.rds")); saveRDS(nc, file.path(out,"seqtab_nochim.rds"))
cat("DONE ASVs", ncol(st), "nochim", ncol(nc), "\n")
