#!/usr/bin/env Rscript
# Step 4 — recover the run -> (patient, day) mapping by alpha-diversity
# fingerprint.
#
# Run INSIDE the container:
#   ./docker/run.sh Rscript scripts/04_match_samples.R
#
# ---------------------------------------------------------------------------
# THE PROBLEM
#
# Jarosch et al. deposited 53 sequencing runs in ENA under anonymous library
# aliases (AAX11, R000000616, ...) and separately published alpha diversity for
# 46 stool samples keyed by Patient + day after aHSCT. They never published the
# link between the two. Without it the sequencing data cannot be joined to any
# clinical covariate, which makes the study unusable for the meta-analysis.
#
# THE APPROACH
#
# Reproduce the authors' own pipeline closely enough that our alpha diversity
# values reproduce theirs, then use the (Richness, Shannon, Simpson) triple as
# a fingerprint to identify which run is which sample.
#
# This works because the published values are highly informative: Richness is
# an exact integer, and Shannon/Simpson are given to ~7 decimal places. All 46
# published triples are mutually distinct. A faithful reproduction should
# therefore produce near-zero distances for the true pairing and clearly larger
# ones for every alternative.
#
# Assignment is one-to-one and global (Hungarian algorithm), not greedy
# nearest-neighbour: 46 published samples compete for 53 runs, and each run can
# serve at most one sample. 7 runs are expected to go unassigned.
#
# HOW TO READ THE OUTPUT
#
# The reproduction quality gate comes first. If our richness distribution does
# not overlap the published one, the fingerprint is not informative and the
# assignment below is not trustworthy no matter how confident it looks. Fix the
# pipeline before believing any mapping.
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(vegan)
})

repro <- Sys.getenv("REPRO_DIR", unset = "")
if (!nzchar(repro)) repro <- if (dir.exists("/work/results")) "/work" else getwd()
res_dir <- file.path(repro, "results")

find_first <- function(paths, what) {
  hit <- Filter(file.exists, paths)
  if (!length(hit)) stop(what, " not found. Looked in:\n  ",
                         paste(paths, collapse = "\n  "),
                         "\nIf running in Docker, use ./docker/run.sh so /study is mounted.")
  hit[1]
}

# --------------------------------------------------------------------------
# Published fingerprints
# --------------------------------------------------------------------------
pub_path <- Sys.getenv("PUB_ALPHA", unset = "")
if (!nzchar(pub_path)) {
  pub_path <- find_first(c(
    "/study/Metadata/Original_alpha.tsv",
    file.path(repro, "..", "Metadata", "Original_alpha.tsv")
  ), "Published alpha table (Original_alpha.tsv)")
}
cat("Published table:", pub_path, "\n")

pub <- read.delim(pub_path, stringsAsFactors = FALSE, check.names = FALSE)
pub <- pub[stats::complete.cases(pub[, c("Richness", "Shannon", "Simpson")]), ]

# Neither Patient nor Patient+day is unique:
#   - several patients have multiple timepoints
#   - two patients (56 d154, 60 d14) have TWO DISTINCT BIOPSIES on the same day,
#     one from the scRNAseq cohort and one from ChipCytometry, with clearly
#     different diversity. These are separate stool samples and must each be
#     matched to their own run -- not deduplicated.
# So label rows with the biopsy ID, pulled from the clinical table where
# available. The (Richness, Shannon) pair is unique across all 46 rows, which
# makes that join safe.
pub$biopsy <- NA_character_
clin_path <- Filter(file.exists, c(
  "/study/Metadata/Raw_metadata/meta_clinical.csv",
  file.path(repro, "..", "Metadata", "Raw_metadata", "meta_clinical.csv")
))
if (length(clin_path)) {
  clin <- read.csv(clin_path[1], stringsAsFactors = FALSE, check.names = FALSE)
  key_p <- paste(pub$Patient,  pub$day,                round(pub$Shannon, 5))
  key_c <- paste(clin$Patient, clin$`d after aHSCT`,   round(as.numeric(clin$Shannon), 5))
  pub$biopsy <- clin$Biopsy[match(key_p, key_c)]
  cat("Biopsy IDs resolved from clinical table:",
      sum(!is.na(pub$biopsy)), "/", nrow(pub), "\n")
}

pub$sample_id <- ifelse(is.na(pub$biopsy),
                        paste0(pub$Patient, " | d", pub$day),
                        paste0(pub$Patient, " | d", pub$day, " | ", pub$biopsy))

# Last-resort disambiguation so the assignment can never silently drop a sample.
if (any(duplicated(pub$sample_id))) {
  dup <- pub$sample_id %in% pub$sample_id[duplicated(pub$sample_id)]
  pub$sample_id[dup] <- paste0(pub$sample_id[dup], " #",
                               stats::ave(seq_len(sum(dup)), pub$sample_id[dup],
                                          FUN = seq_along))
  cat("NOTE: appended replicate suffixes to",
      sum(dup), "rows that shared a label.\n")
}
stopifnot(!any(duplicated(pub$sample_id)))

cat("Published samples: ", nrow(pub), " across ",
    length(unique(pub$Patient)), " patients\n\n", sep = "")

# --------------------------------------------------------------------------
# Our fingerprints, under a given convention
# --------------------------------------------------------------------------
alpha_of <- function(mat, shannon_base = exp(1), simpson_form = "gini") {
  counts <- as.matrix(mat)
  D <- vegan::diversity(counts, index = "simpson")   # 1 - sum(p^2)
  data.frame(
    Run      = rownames(counts),
    Richness = rowSums(counts > 0),
    Shannon  = vegan::diversity(counts, index = "shannon", base = shannon_base),
    Simpson  = switch(simpson_form,
                      gini    = D,
                      classic = 1 - D,
                      inverse = vegan::diversity(counts, index = "invsimpson")),
    depth    = rowSums(counts),
    row.names = NULL, stringsAsFactors = FALSE
  )
}

tables <- list()
for (nm in c("nochim", "prechimera")) {
  p <- file.path(res_dir, paste0("seqtab_", sub("nochim", "nochim", nm), ".rds"))
  p <- file.path(res_dir, if (nm == "nochim") "seqtab_nochim.rds" else "seqtab_prechimera.rds")
  if (file.exists(p)) tables[[nm]] <- readRDS(p)
}
if (!length(tables)) stop("No seqtab RDS in ", res_dir, " -- run scripts/03_dada2.R first.")

# --------------------------------------------------------------------------
# Optimal one-to-one assignment.
#
# Distances are computed on robust z-scores (median / MAD, pooled over both
# tables) so Richness (range ~5-342) does not swamp Simpson (range 0-1).
# --------------------------------------------------------------------------
have_clue <- requireNamespace("clue", quietly = TRUE)
if (!have_clue) {
  cat("NOTE: package 'clue' unavailable -- falling back to greedy matching.\n",
      "      Rebuild the image to get the optimal Hungarian assignment.\n\n", sep = "")
}

metrics <- c("Richness", "Shannon", "Simpson")

# Three scoring modes, because they fail in different directions.
# Simulated on these published values (46 samples + 7 decoy runs):
#
#   systematic richness bias   pooled-z   separate-z   rank
#     none (faithful repro)      98-100%      73%       85%
#     ours = 0.75 x theirs          28%       73%       85%
#     ours = 0.45 x theirs          10%       72%       83%
#
# pooled-z compares absolute values and is the sharpest instrument when the
# reproduction is genuinely faithful -- which is the whole point of steps 1-3.
# But it collapses under systematic bias. separate-z (standardise each source
# independently) and rank (compare within-cohort ranks) are invariant to a
# monotone shift, so they degrade gracefully. Agreement between all three is
# much stronger evidence than any one of them alone.
robust_scale <- function(v) {
  s <- stats::mad(v, na.rm = TRUE)
  if (!is.finite(s) || s == 0) s <- stats::sd(v, na.rm = TRUE)
  if (!is.finite(s) || s == 0) s <- 1
  s
}

build_cost <- function(obs, mode = c("pooled", "separate", "rank")) {
  mode <- match.arg(mode)
  cost <- matrix(0, nrow = nrow(pub), ncol = nrow(obs),
                 dimnames = list(pub$sample_id, obs$Run))
  for (m in metrics) {
    p <- pub[[m]]; o <- obs[[m]]
    if (mode == "pooled") {
      v <- c(p, o); cen <- stats::median(v, na.rm = TRUE); sc <- robust_scale(v)
      zp <- (p - cen) / sc; zo <- (o - cen) / sc
    } else if (mode == "separate") {
      zp <- (p - stats::median(p, na.rm = TRUE)) / robust_scale(p)
      zo <- (o - stats::median(o, na.rm = TRUE)) / robust_scale(o)
    } else {
      zp <- (rank(p, na.last = "keep") - 1) / (sum(!is.na(p)) - 1)
      zo <- (rank(o, na.last = "keep") - 1) / (sum(!is.na(o)) - 1)
    }
    cost <- cost + outer(zp, zo, function(a, b) (a - b)^2)
  }
  sqrt(cost)
}

assign_optimal <- function(cost) {
  if (have_clue) {
    # solve_LSAP needs ncol >= nrow; we have 53 runs vs 46 samples.
    idx <- clue::solve_LSAP(cost, maximum = FALSE)
    data.frame(sample_id = rownames(cost),
               Run = colnames(cost)[as.integer(idx)],
               dist = cost[cbind(seq_len(nrow(cost)), as.integer(idx))],
               stringsAsFactors = FALSE)
  } else {
    # Greedy: repeatedly take the globally smallest remaining cost.
    cc <- cost; out <- list()
    while (any(is.finite(cc))) {
      k <- which.min(cc); i <- ((k - 1) %% nrow(cc)) + 1; j <- ((k - 1) %/% nrow(cc)) + 1
      out[[length(out) + 1]] <- data.frame(sample_id = rownames(cost)[i],
                                           Run = colnames(cost)[j],
                                           dist = cc[i, j], stringsAsFactors = FALSE)
      cc[i, ] <- Inf; cc[, j] <- Inf
      if (length(out) == nrow(cost)) break
    }
    do.call(rbind, out)
  }
}

# --------------------------------------------------------------------------
# Sweep conventions; score each by total assignment cost.
# A faithful reproduction under the right convention should stand out.
# --------------------------------------------------------------------------
grid <- expand.grid(tab = names(tables),
                    base = c("ln", "log2", "log10"),
                    simpson = c("gini", "classic", "inverse"),
                    mode = c("pooled", "separate", "rank"),
                    stringsAsFactors = FALSE)
base_val <- c(ln = exp(1), log2 = 2, log10 = 10)

sweep <- list(); fits <- list(); obs_store <- list()
for (i in seq_len(nrow(grid))) {
  g <- grid[i, ]
  label <- paste(g$tab, g$base, g$simpson, g$mode, sep = "|")
  key   <- paste(g$tab, g$base, g$simpson, sep = "|")
  if (is.null(obs_store[[key]]))
    obs_store[[key]] <- alpha_of(tables[[g$tab]], base_val[[g$base]], g$simpson)
  obs  <- obs_store[[key]]
  cost <- build_cost(obs, g$mode)
  a    <- assign_optimal(cost)
  fits[[label]] <- list(cost = cost, assign = a, obs_key = key, mode = g$mode)
  sweep[[label]] <- data.frame(
    variant      = label,
    obs_key      = key,
    mode         = g$mode,
    total_cost   = sum(a$dist),
    median_dist  = stats::median(a$dist),
    n_exact_rich = sum(pub$Richness[match(a$sample_id, pub$sample_id)] ==
                         obs$Richness[match(a$Run, obs$Run)]),
    stringsAsFactors = FALSE
  )
}
sw_all <- do.call(rbind, sweep); rownames(sw_all) <- NULL

# Costs are only comparable WITHIN a scoring mode, so the convention (table,
# log base, Simpson form) is selected using pooled-z -- the mode that is most
# sensitive to getting the pipeline right. The other modes are used below only
# as independent cross-checks.
sw <- sw_all[sw_all$mode == "pooled", ]
sw <- sw[order(sw$total_cost), ]

# --------------------------------------------------------------------------
# REPRODUCTION QUALITY GATE
# --------------------------------------------------------------------------
best <- sw$variant[1]
obs  <- obs_store[[sw$obs_key[1]]]

cat("=================================================================\n")
cat(" REPRODUCTION QUALITY — is the fingerprint informative at all?\n")
cat("=================================================================\n")
qq <- function(x) stats::quantile(x, c(0, .25, .5, .75, 1), na.rm = TRUE)
cmp <- rbind(published = qq(pub$Richness), reproduced = qq(obs$Richness))
print(round(cmp, 1))
ratio <- stats::median(obs$Richness) / stats::median(pub$Richness)
cat(sprintf("\n  median richness ratio (ours / theirs): %.2f\n", ratio))
if (ratio < 0.7 || ratio > 1.4) {
  cat("\n  *** WARNING: richness distributions do not overlap well. ***\n")
  cat("  The fingerprint is weak and the mapping below is NOT trustworthy.\n")
  cat("  Revisit the pipeline (trimming, chimera removal, pool=) first.\n")
} else {
  cat("  OK: distributions are comparable; fingerprint is usable.\n")
}

cat("\n=================================================================\n")
cat(" CONVENTION SWEEP — pooled-z scoring (lower total_cost = better)\n")
cat("=================================================================\n")
print(head(sw[, c("variant", "total_cost", "median_dist", "n_exact_rich")], 6),
      row.names = FALSE, digits = 4)
cat("\nSelected variant:", best, "\n")
cat("n_exact_rich = published and reproduced Richness identical. A faithful\n")
cat("reproduction should push this number high; it is the cleanest evidence\n")
cat("that the pipeline, not the matcher, is doing the work.\n")

# --------------------------------------------------------------------------
# CONFIDENCE for the chosen assignment
#
# margin = distance to this run's next-best alternative, minus the assigned
# distance. A large margin means the assignment is not close to a tie.
# --------------------------------------------------------------------------
cost <- fits[[best]]$cost
a    <- fits[[best]]$assign

a$pub_row <- match(a$sample_id, pub$sample_id)
a$obs_row <- match(a$Run, obs$Run)
for (m in metrics) {
  a[[paste0(m, "_pub")]] <- pub[[m]][a$pub_row]
  a[[paste0(m, "_obs")]] <- obs[[m]][a$obs_row]
}
a$Patient <- pub$Patient[a$pub_row]
a$day     <- pub$day[a$pub_row]
a$biopsy  <- pub$biopsy[a$pub_row]
a$depth   <- obs$depth[a$obs_row]
a$richness_diff <- a$Richness_obs - a$Richness_pub

a$runner_up_dist <- vapply(seq_len(nrow(a)), function(i) {
  r <- cost[a$pub_row[i], ]
  sort(r)[2]
}, numeric(1))
a$margin <- a$runner_up_dist - a$dist

a$confidence <- with(a, ifelse(
  dist < 0.05 & margin > 0.10, "high",
  ifelse(dist < 0.25 & margin > 0.05, "medium", "low")))
a$exact_richness <- a$richness_diff == 0

a <- a[order(a$dist), ]
keep_cols <- c("sample_id", "Patient", "day", "biopsy", "Run", "dist", "margin",
               "confidence", "exact_richness",
               "Richness_pub", "Richness_obs", "richness_diff",
               "Shannon_pub", "Shannon_obs", "Simpson_pub", "Simpson_obs",
               "depth")

cat("\n=================================================================\n")
cat(" ASSIGNMENT\n")
cat("=================================================================\n")
print(table(confidence = a$confidence))
cat("\n  exact richness agreement:", sum(a$exact_richness), "/", nrow(a), "\n")
cat("  median distance         :", round(stats::median(a$dist), 4), "\n")
cat("\nBest 15 matches:\n")
print(head(a[, c("sample_id", "Run", "dist", "margin", "confidence",
                 "Richness_pub", "Richness_obs")], 15),
      row.names = FALSE, digits = 4)
cat("\nWorst 10 matches:\n")
print(tail(a[, c("sample_id", "Run", "dist", "margin", "confidence",
                 "Richness_pub", "Richness_obs")], 10),
      row.names = FALSE, digits = 4)

unassigned <- setdiff(obs$Run, a$Run)
cat("\nRuns with no published counterpart (expected 7):",
    length(unassigned), "\n  ", paste(unassigned, collapse = ", "), "\n")

# --------------------------------------------------------------------------
# STABILITY — does the same run win under other conventions/tables?
# An assignment that survives every variant is far more believable than one
# that depends on choosing log2 over ln.
# --------------------------------------------------------------------------
votes <- vapply(names(fits), function(k) {
  aa <- fits[[k]]$assign
  aa$Run[match(a$sample_id, aa$sample_id)]
}, character(nrow(a)))

a$n_variants_agree <- rowSums(votes == a$Run, na.rm = TRUE)
a$stability <- a$n_variants_agree / length(fits)

# Agreement of the three scoring modes at the selected convention is the most
# meaningful cross-check: those three make genuinely different assumptions.
mode_cols <- vapply(c("pooled", "separate", "rank"), function(md) {
  k <- paste(sw$obs_key[1], md, sep = "|")
  if (is.null(fits[[k]])) return(rep(NA_character_, nrow(a)))
  fits[[k]]$assign$Run[match(a$sample_id, fits[[k]]$assign$sample_id)]
}, character(nrow(a)))
a$n_modes_agree <- rowSums(mode_cols == a$Run, na.rm = TRUE)

cat("\n=================================================================\n")
cat(" STABILITY ACROSS", length(fits), "VARIANTS (table x base x Simpson x scoring)\n")
cat("=================================================================\n")
print(table(`variants agreeing` = a$n_variants_agree))
cat("\n  unanimous across all variants:",
    sum(a$n_variants_agree == length(fits)), "/", nrow(a), "\n")
cat("\n  agreement of the 3 scoring modes at the selected convention:\n")
print(table(`modes agreeing (of 3)` = a$n_modes_agree))
cat("\n  All three modes agreeing is strong evidence: pooled-z compares\n")
cat("  absolute values, rank compares only ordering, and they are affected\n")
cat("  by systematic pipeline bias in opposite ways.\n")

# Promote/demote confidence using cross-mode agreement.
a$confidence[a$n_modes_agree == 3 & a$confidence == "medium"] <- "high"
a$confidence[a$n_modes_agree <= 1] <- "low"

cat("\n  final confidence tally (after cross-mode adjustment):\n")
print(table(confidence = a$confidence))

out <- a[, c(keep_cols, "stability", "n_variants_agree", "n_modes_agree")]
write.table(out, file.path(res_dir, "04_run_to_patient_map.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)
write.table(sw_all, file.path(res_dir, "04_convention_sweep.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)
write.table(obs, file.path(res_dir, "04_our_alpha.tsv"),
            sep = "\t", quote = FALSE, row.names = FALSE)

# --------------------------------------------------------------------------
# Plots
# --------------------------------------------------------------------------
pdf(file.path(res_dir, "04_matching.pdf"), width = 10, height = 8)
op <- par(mfrow = c(2, 2), mar = c(4, 4, 3, 1))
for (m in metrics) {
  plot(a[[paste0(m, "_pub")]], a[[paste0(m, "_obs")]],
       xlab = paste("published", m), ylab = paste("reproduced", m),
       main = sprintf("%s (r = %.3f)", m,
                      cor(a[[paste0(m, "_pub")]], a[[paste0(m, "_obs")]],
                          use = "complete.obs")),
       pch = 19, col = ifelse(a$confidence == "high", "#0066CC", "#CC000066"))
  abline(0, 1, col = "red", lty = 2)
}
hist(a$dist, breaks = 20, col = "grey80",
     main = "Assignment distance", xlab = "distance (robust z units)")
par(op); dev.off()

cat("\nWrote:\n",
    "  results/04_run_to_patient_map.tsv   <- the deliverable\n",
    "  results/04_convention_sweep.tsv\n",
    "  results/04_our_alpha.tsv\n",
    "  results/04_matching.pdf\n", sep = "")
