# debiasm.R
# -----------------------------------------------------------------------------
# R side of the DEBIAS-M round trip: export a phyloseq object to the CSVs the
# Python script expects, run that script in its conda env, and read the
# corrected table back into a phyloseq object.
#
#   ps_corrected <- debiasm_correct(filtered_ps)
#
# is the whole workflow. The three steps are also exported separately so the
# Python step can be run by hand (or on CHPC) when debugging:
#
#   export_for_debiasm(filtered_ps)
#   # ... run run_debiasm.py however you like ...
#   ps_corrected <- import_debiasm(filtered_ps)
#
# -----------------------------------------------------------------------------
# Why a subprocess and not reticulate: DEBIAS-M pulls in torch, and loading that
# into the same process as phyloseq/Bioconductor is a fragile combination that
# fails in ways that are hard to read. The interchange here is CSV either way,
# so an in-process Python buys nothing. Keeping the boundary at a subprocess
# means a Python failure surfaces as a non-zero exit status and a traceback
# rather than a segfault in the R session.
#
# Why `conda run` and not `conda activate`: `conda activate` is a shell
# function, not an executable, so system()/system2() cannot call it -- it fails
# with "CommandNotFoundError: Your shell has not been properly configured".
# `conda run -n <env> <cmd>` is the non-interactive equivalent and is what this
# file uses.
#
# Staleness guard: export_for_debiasm() records an md5 of the counts CSV it
# writes; run_debiasm.py records the md5 of the counts CSV it actually read;
# import_debiasm() refuses to build a phyloseq object unless the two agree. That
# catches the failure mode where the prevalence filter changes, the export
# re-runs, and the Python step does not -- which otherwise silently produces a
# corrected table built from counts that no longer exist.
# -----------------------------------------------------------------------------

library(phyloseq)

DEBIASM_DIR <- path.expand("~/Documents/ODSi/ODSiData/Correcting/DebiasM")

# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------

# Key=value manifest. Deliberately not JSON so this file has no package
# dependency beyond phyloseq itself.
.write_manifest <- function(path, values) {
  writeLines(paste0(names(values), "=", unname(unlist(values))), path)
}

.read_manifest <- function(path) {
  if (!file.exists(path)) return(NULL)
  lines <- readLines(path, warn = FALSE)
  lines <- lines[nzchar(trimws(lines))]
  parts <- regmatches(lines, regexpr("=", lines), invert = TRUE)
  setNames(vapply(parts, function(p) p[2], character(1)),
           vapply(parts, function(p) p[1], character(1)))
}

.md5 <- function(path) unname(tools::md5sum(path))

# RStudio and R.app launched from Finder do not inherit the login shell's PATH,
# so Sys.which("conda") is routinely empty on macOS even when conda works fine
# in Terminal. Probe the documented install locations before giving up.
find_conda <- function(conda = NULL) {
  if (!is.null(conda)) {
    if (file.exists(conda)) return(conda)
    stop("No conda executable at: ", conda, call. = FALSE)
  }
  candidates <- c(
    Sys.getenv("CONDA_EXE"),
    unname(Sys.which("conda")),
    path.expand("~/miniconda3/bin/conda"),   # documented arm64 default
    path.expand("~/anaconda3/bin/conda"),
    path.expand("~/miniforge3/bin/conda"),
    "/opt/homebrew/bin/conda",
    "/usr/local/bin/conda"
  )
  candidates <- candidates[nzchar(candidates)]
  hit <- candidates[file.exists(candidates)]
  if (length(hit) == 0) {
    stop("Could not find a conda executable. Pass conda = \"/full/path/to/conda\", ",
         "or run the Python step by hand.", call. = FALSE)
  }
  hit[1]
}

# -----------------------------------------------------------------------------
# 1) Export
# -----------------------------------------------------------------------------
# Filtering logic is unchanged from the inline chunk it replaces: keep taxa that
# are non-zero in at least one sample of at least two studies, then drop samples
# left with zero total counts.
export_for_debiasm <- function(phylo_obj,
                               dir = DEBIASM_DIR,
                               outcome_col = "agvhd",
                               sample_id_col = "sample.id",
                               study_col = "study") {

  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)

  ## Taxa rows x sample cols (the orientation ComBat-seq and DEBIAS-M expect)
  count_matrix <- as(otu_table(phylo_obj), "matrix")
  if (!taxa_are_rows(phylo_obj)) {
    count_matrix <- t(count_matrix)
  }

  count_meta <- data.frame(sample_data(phylo_obj))
  count_meta <- count_meta[colnames(count_matrix), , drop = FALSE]

  missing_cols <- setdiff(c(sample_id_col, study_col, outcome_col), names(count_meta))
  if (length(missing_cols) > 0) {
    stop("sample_data() is missing column(s): ", paste(missing_cols, collapse = ", "),
         call. = FALSE)
  }

  batch_var <- droplevels(factor(count_meta[[study_col]]))

  ## 1) Taxa non-zero in at least one sample of at least two studies
  shared_taxa <- rowSums(sapply(levels(batch_var), function(b) {
    rowSums(count_matrix[, batch_var == b, drop = FALSE]) > 0
  })) >= 2

  ## 2) Filter to shared taxa
  shared_count_matrix <- count_matrix[shared_taxa, , drop = FALSE]

  ## 3) Drop samples with zero total counts after filtering
  sample_keep <- colSums(shared_count_matrix) > 0
  shared_count_matrix <- shared_count_matrix[, sample_keep, drop = FALSE]

  ## 4) Transpose to samples x taxa and write counts CSV
  counts_path <- file.path(dir, "debiasm-counts.csv")
  counts_df <- as.data.frame(t(shared_count_matrix))
  counts_df <- cbind(sampleid = rownames(counts_df), counts_df)
  write.csv(counts_df, counts_path, row.names = FALSE)

  ## 5) Metadata aligned to the filtered sample order
  meta_path <- file.path(dir, "debiasm-meta.csv")
  debiasm_meta <- count_meta[sample_keep, , drop = FALSE]
  debiasm_meta <- debiasm_meta[, c(sample_id_col, study_col, outcome_col)]
  names(debiasm_meta) <- c("sampleid", "study", "agvhd")
  write.csv(debiasm_meta, meta_path, row.names = FALSE)

  ## 6) Manifest -- the hash the import step will check against
  counts_md5 <- .md5(counts_path)
  .write_manifest(
    file.path(dir, "debiasm-export.txt"),
    list(counts_md5  = counts_md5,
         meta_md5    = .md5(meta_path),
         n_samples   = ncol(shared_count_matrix),
         n_taxa      = nrow(shared_count_matrix),
         exported_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"))
  )

  message(sprintf("Exported %d samples x %d taxa to %s",
                  ncol(shared_count_matrix), nrow(shared_count_matrix), dir))
  message(sprintf("Dropped %d taxa (not shared by 2+ studies) and %d samples (zero counts after filtering)",
                  sum(!shared_taxa), sum(!sample_keep)))

  invisible(list(dir = dir,
                 counts_path = counts_path,
                 meta_path = meta_path,
                 counts_md5 = counts_md5,
                 n_samples = ncol(shared_count_matrix),
                 n_taxa = nrow(shared_count_matrix)))
}

# -----------------------------------------------------------------------------
# 2) Run the Python step
# -----------------------------------------------------------------------------
run_debiasm_python <- function(dir = DEBIASM_DIR,
                               env = "debiasm",
                               script = file.path(dir, "run_debiasm.py"),
                               conda = NULL,
                               echo = TRUE) {

  if (!file.exists(script)) {
    stop("No Python script at: ", script, call. = FALSE)
  }
  if (!file.exists(file.path(dir, "debiasm-counts.csv"))) {
    stop("No debiasm-counts.csv in ", dir,
         " -- run export_for_debiasm() first.", call. = FALSE)
  }

  conda_bin <- find_conda(conda)

  # Output is captured rather than streamed (no --no-capture-output) so that a
  # failure can be reported with the traceback attached.
  args <- c("run", "-n", env, "python", script, dir)
  if (echo) message("Running: ", conda_bin, " ", paste(args, collapse = " "))

  output <- suppressWarnings(
    system2(conda_bin, args, stdout = TRUE, stderr = TRUE)
  )
  status <- attr(output, "status")
  if (is.null(status)) status <- 0L

  if (echo && length(output) > 0) message(paste(output, collapse = "\n"))

  if (status != 0L) {
    stop("run_debiasm.py failed (exit status ", status, ") in conda env '", env,
         "'.\n", paste(output, collapse = "\n"), call. = FALSE)
  }

  invisible(list(status = status, output = output))
}

# -----------------------------------------------------------------------------
# 3) Import
# -----------------------------------------------------------------------------
# phylo_obj must be the SAME object that was exported -- the corrected table is
# pruned back onto it by sample and taxa name.
import_debiasm <- function(phylo_obj,
                           dir = DEBIASM_DIR,
                           check_manifest = TRUE,
                           check = TRUE) {

  corrected_path <- file.path(dir, "debiasm-corrected.csv")
  if (!file.exists(corrected_path)) {
    stop("No debiasm-corrected.csv in ", dir,
         " -- run the Python step first.", call. = FALSE)
  }

  # --- Staleness guard -------------------------------------------------------
  if (check_manifest) {
    counts_path <- file.path(dir, "debiasm-counts.csv")
    run_manifest <- .read_manifest(file.path(dir, "debiasm-run.txt"))
    if (is.null(run_manifest) || is.na(run_manifest["counts_md5"])) {
      warning("No debiasm-run.txt found, so the corrected table cannot be tied ",
              "to the counts that produced it. Re-run run_debiasm.py to write one, ",
              "or pass check_manifest = FALSE.", call. = FALSE)
    } else if (!file.exists(counts_path)) {
      warning("debiasm-counts.csv is missing; skipping the staleness check.",
              call. = FALSE)
    } else if (!identical(unname(run_manifest["counts_md5"]), .md5(counts_path))) {
      stop("debiasm-corrected.csv is stale: it was produced from a different ",
           "debiasm-counts.csv than the one currently on disk.\n",
           "  counts now : ", .md5(counts_path), "\n",
           "  used by run: ", unname(run_manifest["counts_md5"]), "\n",
           "Re-run run_debiasm_python() (or debiasm_correct()) before importing.",
           call. = FALSE)
    }
  }

  corrected_df <- read.csv(corrected_path, row.names = 1, check.names = FALSE)

  # corrected_df is samples x taxa; prune the object to the retained samples and
  # taxa before swapping the otu_table
  retained_samples <- rownames(corrected_df)
  retained_taxa    <- colnames(corrected_df)

  debiasm_ps <- prune_samples(sample_names(phylo_obj) %in% retained_samples, phylo_obj)
  debiasm_ps <- prune_taxa(taxa_names(debiasm_ps) %in% retained_taxa, debiasm_ps)

  # Align the corrected matrix to the object's current sample and taxa order,
  # then transpose to taxa x samples for otu_table assignment
  corrected_mat <- as.matrix(corrected_df[sample_names(debiasm_ps),
                                          taxa_names(debiasm_ps)])
  stopifnot(identical(colnames(corrected_mat), taxa_names(debiasm_ps)))
  stopifnot(identical(rownames(corrected_mat), sample_names(debiasm_ps)))

  otu_table(debiasm_ps) <- otu_table(t(corrected_mat), taxa_are_rows = TRUE)

  if (check) {
    if (!exists("check_phyloseq")) {
      source("~/Documents/ODSi/ODSiData/Functions/check_phyloseq.R")
    }
    check_phyloseq(debiasm_ps)
  }

  debiasm_ps
}

# -----------------------------------------------------------------------------
# The whole round trip
# -----------------------------------------------------------------------------
debiasm_correct <- function(phylo_obj,
                            dir = DEBIASM_DIR,
                            env = "debiasm",
                            conda = NULL,
                            ...) {
  export_for_debiasm(phylo_obj, dir = dir, ...)
  run_debiasm_python(dir = dir, env = env, conda = conda)
  import_debiasm(phylo_obj, dir = dir)
}
