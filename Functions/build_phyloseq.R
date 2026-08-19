# build_phyloseq.R
# -----------------------------------------------------------------------------
# Build a phyloseq object from a set of QIIME2 artifacts, following the same
# steps the "Files" / "Phyloseq" sections of Merging/Merging.qmd used to do
# inline: define the files, read them in, build the OTU table, parse the
# taxonomy, load the sequences, attach the metadata (dropping samples that are
# not in the OTU table), then combine.
#
# Returns the phyloseq object and nothing else.
#
# -----------------------------------------------------------------------------
# Two ways to call it
# -----------------------------------------------------------------------------
# By folder + prefix -- any file whose name matches EXACTLY is picked up:
#
#     ps <- build_phyloseq("Merging/full_cohort", prefix = "merged-")
#
#   looks for  merged-table.qza
#              merged-taxonomy.qza
#              merged-seqs.qza
#              merged-tree.nwk   (preferred)  or  merged-tree.qza
#              merged-metadata.tsv
#
# By explicit path -- anything supplied directly wins over the folder:
#
#     ps <- build_phyloseq("Merging/full_cohort", prefix = "merged-",
#                          meta_tsv = "Merging/merged_metadata.tsv")
#
# The two mix freely: supply the odd one out, let the folder cover the rest.
#
# If both [prefix]tree.nwk and [prefix]tree.qza are in the folder, the .nwk
# wins. Pass tree = ".../tree.qza" to override that.
#
# A component can be skipped deliberately by passing NA, e.g. tree = NA for an
# object with no phylogeny. Omitting the argument entirely is NOT the same
# thing: that means "find it in the folder", and is an error if it isn't there.
# -----------------------------------------------------------------------------

library(phyloseq)
library(qiime2R)
library(Biostrings)
library(ape)
library(readr)

# Exact filenames looked for inside `folder`, after `prefix`.
BUILD_PHYLOSEQ_FILENAMES <- c(
  table    = "table.qza",
  taxonomy = "taxonomy.qza",
  seqs     = "seqs.qza",
  tree_nwk = "tree.nwk",
  tree_qza = "tree.qza",
  metadata = "metadata.tsv"
)

# -----------------------------------------------------------------------------
# Internal: resolve one component to a path
# -----------------------------------------------------------------------------
# Precedence is: explicitly supplied > found in folder > not found (NULL).
# NA means "this component is deliberately absent" and short-circuits both.
.bp_resolve <- function(supplied, folder, prefix, filename, label) {

  if (!is.null(supplied)) {
    if (length(supplied) == 1L && is.na(supplied)) return(NA_character_)
    if (!is.character(supplied) || length(supplied) != 1L) {
      stop("`", label, "` must be a single file path (or NA to skip it).",
           call. = FALSE)
    }
    p <- path.expand(supplied)
    if (!file.exists(p)) {
      stop("`", label, "` was supplied directly but does not exist: ", p,
           call. = FALSE)
    }
    return(p)
  }

  if (is.null(folder)) return(NULL)

  p <- file.path(folder, paste0(prefix, filename))
  if (file.exists(p)) return(p) else return(NULL)
}

# Turn an unresolved component into an error that names what was looked for,
# so a near-miss filename is obvious rather than mysterious.
.bp_require <- function(path, label, arg, folder, prefix, filename) {
  if (!is.null(path)) return(invisible(NULL))
  if (is.null(folder)) {
    stop("No `", arg, "` supplied and no `folder` given to search.", call. = FALSE)
  }
  stop("Could not find the ", label, ".\n",
       "  looked for: ", file.path(folder, paste0(prefix, filename)), "\n",
       "  fix by    : renaming the file, or passing ", arg, " = \"...\" directly",
       ifelse(arg == "tree", " (or tree = NA to build without one)", ""),
       call. = FALSE)
}

# -----------------------------------------------------------------------------
# build_phyloseq()
# -----------------------------------------------------------------------------
build_phyloseq <- function(folder = NULL,
                           prefix = "",
                           table_qza = NULL,
                           taxonomy_qza = NULL,
                           repseqs_qza = NULL,
                           tree = NULL,
                           meta_tsv = NULL,
                           sample_id_col = "sample-id",
                           verbose = TRUE) {

  if (!is.null(folder)) {
    folder <- path.expand(folder)
    if (!dir.exists(folder)) {
      stop("`folder` does not exist: ", folder, call. = FALSE)
    }
  }

  # ===========================================================================
  # 1) Files
  # ===========================================================================
  fn <- BUILD_PHYLOSEQ_FILENAMES

  table_path <- .bp_resolve(table_qza,    folder, prefix, fn[["table"]],    "table_qza")
  tax_path   <- .bp_resolve(taxonomy_qza, folder, prefix, fn[["taxonomy"]], "taxonomy_qza")
  seqs_path  <- .bp_resolve(repseqs_qza,  folder, prefix, fn[["seqs"]],     "repseqs_qza")
  meta_path  <- .bp_resolve(meta_tsv,     folder, prefix, fn[["metadata"]], "meta_tsv")

  # Tree is the one slot with two acceptable extensions. A directly supplied
  # path is taken as-is; otherwise .nwk in the folder beats .qza.
  if (!is.null(tree)) {
    tree_path <- .bp_resolve(tree, folder, prefix, fn[["tree_nwk"]], "tree")
  } else {
    tree_path <- .bp_resolve(NULL, folder, prefix, fn[["tree_nwk"]], "tree")
    if (is.null(tree_path)) {
      tree_path <- .bp_resolve(NULL, folder, prefix, fn[["tree_qza"]], "tree")
    }
  }

  .bp_require(table_path, "feature table",   "table_qza",    folder, prefix, fn[["table"]])
  .bp_require(tax_path,   "taxonomy",        "taxonomy_qza", folder, prefix, fn[["taxonomy"]])
  .bp_require(seqs_path,  "representative sequences", "repseqs_qza", folder, prefix, fn[["seqs"]])
  .bp_require(meta_path,  "sample metadata", "meta_tsv",     folder, prefix, fn[["metadata"]])
  if (is.null(tree_path)) {
    stop("Could not find the tree.\n",
         "  looked for: ", file.path(folder, paste0(prefix, fn[["tree_nwk"]])), "\n",
         "          or: ", file.path(folder, paste0(prefix, fn[["tree_qza"]])), "\n",
         "  fix by    : renaming the file, or passing tree = \"...\" directly ",
         "(or tree = NA to build without one)", call. = FALSE)
  }

  if (verbose) {
    message("Building phyloseq from:")
    for (nm in c("table", "taxonomy", "seqs", "tree", "metadata")) {
      p <- switch(nm, table = table_path, taxonomy = tax_path,
                  seqs = seqs_path, tree = tree_path, metadata = meta_path)
      message(sprintf("  %-9s %s", nm, if (is.na(p)) "<skipped>" else p))
    }
  }

  # ===========================================================================
  # 2) Read
  # ===========================================================================
  qt_orig  <- qiime2R::read_qza(table_path)$data
  tax_q    <- if (is.na(tax_path))  NA else qiime2R::read_qza(tax_path)$data
  rep_seqs <- if (is.na(seqs_path)) NA else qiime2R::read_qza(seqs_path)$data
  meta     <- readr::read_tsv(meta_path, show_col_types = FALSE)

  # A tree can arrive either as an exported Newick file or as a QIIME2 artifact;
  # dispatch on the extension rather than on which argument it came from, so a
  # directly supplied .qza works the same as one found in the folder.
  if (is.na(tree_path)) {
    tree_obj <- NA
  } else if (grepl("\\.qza$", tree_path, ignore.case = TRUE)) {
    tree_obj <- qiime2R::read_qza(tree_path)$data
  } else {
    tree_obj <- ape::read.tree(tree_path)
  }

  # ===========================================================================
  # 3) OTU
  # ===========================================================================
  otu_mat <- otu_table(qt_orig, taxa_are_rows = TRUE)

  # ===========================================================================
  # 4) Taxonomy
  # ===========================================================================
  if (!identical(tax_q, NA)) {
    if (!exists("parse_taxonomy")) {
      source("~/Documents/ODSi/ODSiData/Functions/parse_taxonomy.R")
    }
    tax_mat <- tax_table(parse_taxonomy(tax_q))
  } else {
    tax_mat <- NULL
  }

  # ===========================================================================
  # 5) Seqs
  # ===========================================================================
  if (!identical(rep_seqs, NA)) {
    seqs <- Biostrings::DNAStringSet(rep_seqs)
    names(seqs) <- names(rep_seqs)
  } else {
    seqs <- NULL
  }

  # ===========================================================================
  # 6) Meta
  # ===========================================================================
  if (!sample_id_col %in% names(meta)) {
    stop("Metadata has no `", sample_id_col, "` column. Columns are: ",
         paste(names(meta), collapse = ", "),
         "\nPass sample_id_col = \"...\" if it goes by another name.",
         call. = FALSE)
  }

  meta <- as.data.frame(meta, stringsAsFactors = FALSE)
  excluded <- setdiff(meta[[sample_id_col]], colnames(otu_mat))
  meta_df <- sample_data(meta[!(meta[[sample_id_col]] %in% excluded), , drop = FALSE])
  rownames(meta_df) <- meta_df[[sample_id_col]]

  # ===========================================================================
  # 7) Combining
  # ===========================================================================
  if (verbose) {
    if (!identical(tree_obj, NA)) {
      message(sprintf("OTU features: %d ; tree tips: %d ; intersection: %d",
                      nrow(otu_mat), length(tree_obj$tip.label),
                      sum(rownames(otu_mat) %in% tree_obj$tip.label)))
    }
    message(sprintf("OTU samples: %d ; meta samples: %d ; intersection: %d",
                    ncol(otu_mat), nrow(meta_df),
                    sum(colnames(otu_mat) %in% rownames(meta_df))))
    if (length(excluded) > 0) {
      message(sprintf("Dropped %d metadata row(s) with no sample in the feature table",
                      length(excluded)))
    }
  }

  components <- list(otu_mat, meta_df)
  if (!is.null(tax_mat))           components <- c(components, list(tax_mat))
  if (!identical(tree_obj, NA))    components <- c(components, list(phy_tree(tree_obj)))
  if (!is.null(seqs))              components <- c(components, list(refseq(seqs)))

  ps <- do.call(phyloseq, components)

  if (verbose) print(ps)

  ps
}
