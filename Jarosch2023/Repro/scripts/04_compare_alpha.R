#!/usr/bin/env Rscript
# Step 4 — compute alpha diversity from our ASV table and compare it against
# the values published with Jarosch et al. 2023.
#
# Run INSIDE the container:
#   ./docker/run.sh Rscript scripts/04_compare_alpha.R
#
# Target file: ../Metadata/jarosch_alpha_diversity.tsv
#   columns: Run, Sample_name, Richness, Shannon, Simpson, depth
#
# The published table does not state how Shannon and Simpson were computed, so
# this script evaluates the plausible conventions and reports which fits best:
#   Shannon: natural log vs log2 vs log10
#   Simpson: Gini-Simpson (1 - D) vs D vs inverse (1/D)
# It also compares pre- vs post-chimera tables, since chimera removal is not
# mentioned in the methods.
#
# `depth` is the most diagnostic column: if our per-sample read counts track
# theirs, the upstream trimming assumptions in step 2 are close. If depth is
# systematically off, fix that before chasing Shannon/Simpson.

suppressPackageStartupMessages({
  library(vegan)
})

repro <- Sys.getenv("REPRO_DIR", unset = "")
if (!nzchar(repro)) repro <- if (dir.exists("/work/results")) "/work" else getwd()
res_dir <- file.path(repro, "results")

pub_path <- file.path(repro, "..", "Metadata", "jarosch_alpha_diversity.tsv")
if (!file.exists(pub_path)) stop("Published alpha table not found at ", pub_path)
pub <- read.delim(pub_path, stringsAsFactors = FALSE, check.names = FALSE)
cat("Published rows:", nrow(pub), "\n")

# --------------------------------------------------------------------------
# alpha diversity under a given convention
# --------------------------------------------------------------------------
alpha_of <- function(mat, shannon_base = exp(1), simpson_form = "gini") {
  counts <- as.matrix(mat)
  rich <- rowSums(counts > 0)
  sh   <- vegan::diversity(counts, index = "shannon", base = shannon_base)
  D    <- vegan::diversity(counts, index = "simpson")          # this is 1 - sum(p^2)
  si   <- switch(simpson_form,
                 gini    = D,                                   # 1 - sum(p^2)
                 classic = 1 - D,                               # sum(p^2)
                 inverse = vegan::diversity(counts, index = "invsimpson"),
                 stop("bad simpson_form"))
  data.frame(Run = rownames(counts), Richness = rich, Shannon = sh,
             Simpson = si, depth = rowSums(counts),
             row.names = NULL, stringsAsFactors = FALSE)
}

# --------------------------------------------------------------------------
# Sample names -> ENA run accessions
# Our FASTQ basenames come from ENA, so they should already be ERR*. Strip any
# suffix cutadapt/dada2 may have left behind.
# --------------------------------------------------------------------------
normalize_run <- function(x) {
  x <- sub("_filt$", "", x)
  x <- sub("\\.fastq(\\.gz)?$", "", x)
  x <- sub("_1$", "", x)
  x
}

compare_one <- function(obs, label) {
  obs$Run <- normalize_run(obs$Run)
  m <- merge(pub, obs, by = "Run", suffixes = c("_pub", "_obs"))
  if (!nrow(m)) {
    cat("\n[", label, "] no runs matched between tables.\n", sep = "")
    cat("  published Run examples:", paste(head(pub$Run, 3), collapse = ", "), "\n")
    cat("  observed  Run examples:", paste(head(obs$Run, 3), collapse = ", "), "\n")
    return(NULL)
  }
  stats <- do.call(rbind, lapply(c("Richness", "Shannon", "Simpson", "depth"), function(v) {
    p <- m[[paste0(v, "_pub")]]; o <- m[[paste0(v, "_obs")]]
    ok <- is.finite(p) & is.finite(o)
    data.frame(
      variant     = label,
      metric      = v,
      n           = sum(ok),
      pearson_r   = if (sum(ok) > 2) cor(p[ok], o[ok], method = "pearson")  else NA_real_,
      spearman_r  = if (sum(ok) > 2) cor(p[ok], o[ok], method = "spearman") else NA_real_,
      mean_pub    = mean(p[ok]),
      mean_obs    = mean(o[ok]),
      mean_diff   = mean(o[ok] - p[ok]),
      median_absl = median(abs(o[ok] - p[ok])),
      pct_within_1pct = 100 * mean(abs(o[ok] - p[ok]) <= 0.01 * abs(p[ok])),
      stringsAsFactors = FALSE
    )
  }))
  list(stats = stats, merged = m)
}

# --------------------------------------------------------------------------
# Run the grid
# --------------------------------------------------------------------------
tables <- list()
p_nc <- file.path(res_dir, "seqtab_nochim.rds")
p_pc <- file.path(res_dir, "seqtab_prechimera.rds")
if (file.exists(p_nc)) tables[["nochim"]]     <- readRDS(p_nc)
if (file.exists(p_pc)) tables[["prechimera"]] <- readRDS(p_pc)
if (!length(tables)) stop("No seqtab RDS in ", res_dir, " -- run scripts/03_dada2.R first.")

grid <- expand.grid(
  tab     = names(tables),
  base    = c("ln", "log2", "log10"),
  simpson = c("gini", "classic", "inverse"),
  stringsAsFactors = FALSE
)
base_val <- c(ln = exp(1), log2 = 2, log10 = 10)

all_stats <- list(); merged_store <- list()
for (i in seq_len(nrow(grid))) {
  g <- grid[i, ]
  label <- paste(g$tab, g$base, g$simpson, sep = "|")
  obs <- alpha_of(tables[[g$tab]], base_val[[g$base]], g$simpson)
  r <- compare_one(obs, label)
  if (!is.null(r)) { all_stats[[label]] <- r$stats; merged_store[[label]] <- r$merged }
}
if (!length(all_stats)) stop("No variant produced overlapping runs -- check sample naming.")

stats <- do.call(rbind, all_stats)
rownames(stats) <- NULL
write.table(stats, file.path(res_dir, "04_alpha_comparison_grid.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)

# --------------------------------------------------------------------------
# Report
# --------------------------------------------------------------------------
cat("\n================ DEPTH (convention-independent) ================\n")
d <- stats[stats$metric == "depth", ]
print(unique(d[, c("variant", "n", "pearson_r", "mean_pub", "mean_obs", "mean_diff")]), row.names = FALSE)
cat("\nIf pearson_r for depth is high but mean_diff is large, the pipeline shape\n",
    "matches and only the trimming stringency differs. If r is low, revisit\n",
    "scripts/02_trim.sh (Trimmomatic settings are inferred, not reported).\n", sep = "")

for (met in c("Richness", "Shannon", "Simpson")) {
  cat("\n================", met, "- best-fitting conventions ================\n")
  s <- stats[stats$metric == met, ]
  s <- s[order(-s$pct_within_1pct, s$median_absl), ]
  print(head(s[, c("variant", "n", "pearson_r", "spearman_r",
                   "mean_pub", "mean_obs", "median_absl", "pct_within_1pct")], 5),
        row.names = FALSE)
}

# Write per-sample deltas for the single best overall variant.
score <- sapply(names(merged_store), function(k) {
  s <- stats[stats$variant == k & stats$metric %in% c("Richness", "Shannon", "Simpson"), ]
  mean(s$pct_within_1pct, na.rm = TRUE)
})
best <- names(which.max(score))
cat("\n\nBest overall variant:", best,
    sprintf("(mean %% within 1%%: %.1f)\n", max(score, na.rm = TRUE)))

bm <- merged_store[[best]]
for (v in c("Richness", "Shannon", "Simpson", "depth")) {
  bm[[paste0(v, "_diff")]] <- bm[[paste0(v, "_obs")]] - bm[[paste0(v, "_pub")]]
}
write.table(bm, file.path(res_dir, "04_alpha_per_sample_best.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)

cat("\nPer-sample table -> results/04_alpha_per_sample_best.tsv\n")
cat("Full grid        -> results/04_alpha_comparison_grid.tsv\n")

pdf(file.path(res_dir, "04_alpha_scatter.pdf"), width = 9, height = 9)
op <- par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
for (v in c("Richness", "Shannon", "Simpson", "depth")) {
  p <- bm[[paste0(v, "_pub")]]; o <- bm[[paste0(v, "_obs")]]
  plot(p, o, xlab = paste("published", v), ylab = paste("reproduced", v),
       main = paste0(v, "  (r = ", round(cor(p, o, use = "complete.obs"), 3), ")"),
       pch = 19, col = "#00000099")
  abline(0, 1, col = "red", lty = 2)
}
par(op); dev.off()
cat("Scatter plots    -> results/04_alpha_scatter.pdf\n")
