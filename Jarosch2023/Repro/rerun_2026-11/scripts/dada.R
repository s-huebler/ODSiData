args <- commandArgs(TRUE); indir <- args[1]; outdir <- args[2]; lib <- args[3]
pool <- if (length(args) >= 4) args[4] else "FALSE"
if (nzchar(lib) && lib != "system") .libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dada2)); cat("dada2", as.character(packageVersion("dada2")), "\n")
set.seed(100)
dir.create(outdir, showWarnings=FALSE, recursive=TRUE)
fns <- sort(list.files(indir, "fastq.gz$", full.names=TRUE)); s <- sub(".fastq.gz","",basename(fns))
filt <- file.path(outdir, "filt", basename(fns))
out <- filterAndTrim(fns, filt, trimLeft=15, maxEE=5, multithread=FALSE)
keep <- file.exists(filt); filt <- filt[keep]; s <- s[keep]
err <- learnErrors(filt, multithread=2, HOMOPOLYMER_GAP_PENALTY=-1, BAND_SIZE=32)
pl <- switch(pool, "TRUE"=TRUE, "pseudo"="pseudo", FALSE)
dd <- dada(filt, err=err, multithread=2, HOMOPOLYMER_GAP_PENALTY=-1, BAND_SIZE=32, pool=pl)
st <- makeSequenceTable(dd); rownames(st) <- s
saveRDS(out, file.path(outdir,"filt.rds")); saveRDS(st, file.path(outdir,"seqtab.rds"))
nc <- removeBimeraDenovo(st, method="consensus", multithread=FALSE); saveRDS(nc, file.path(outdir,"seqtab_nochim.rds"))
cat("ASVs", ncol(st), "nochim", ncol(nc), "\n")
