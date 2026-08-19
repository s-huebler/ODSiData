# check_phyloseq.R
# -----------------------------------------------------------------------------
# Sanity-check that the pieces of a phyloseq object line up: that the OTU table's
# features are all present in the tree, and that its samples are all present in
# the metadata. Prints the same counts that were previously pasted inline before
# and after every phyloseq() call.
#
# Orientation-aware: the OTU table is read via taxa_are_rows() rather than
# assuming features are rows, so an object built with taxa_are_rows = FALSE
# reports the same numbers rather than silently transposing features and
# samples.
#
# Works either on a whole phyloseq object:
#     check_phyloseq(ps)
#     check_phyloseq(debiasm_ps)
# or on the loose pieces before they have been assembled:
#     check_phyloseq(otu_mat, tree = tree, meta = meta_df)
#
# Returns (invisibly) a list of the counts and pass/fail logicals, so it can be
# used in a stopifnot() as well as read off the console.
# -----------------------------------------------------------------------------

library(phyloseq)

check_phyloseq <- function(x,
                           tree = NULL,
                           meta = NULL,
                           taxa_are_rows = NULL) {

  # --- Resolve the three pieces ---------------------------------------------
  # A phyloseq object carries all three; anything else is treated as the OTU
  # table and the caller supplies the rest. errorIfNULL = FALSE so an object
  # with no tree or no sample_data is reported on rather than throwing.
  if (methods::is(x, "phyloseq")) {
    otu <- phyloseq::otu_table(x)
    if (is.null(tree)) tree <- phyloseq::phy_tree(x, errorIfNULL = FALSE)
    if (is.null(meta)) meta <- phyloseq::sample_data(x, errorIfNULL = FALSE)
  } else {
    otu <- x
  }

  # --- Orientation -----------------------------------------------------------
  # otu_table objects know their own orientation. A bare matrix does not, so it
  # has to be told; guessing would be the exact silent-transpose bug this
  # function exists to catch.
  if (is.null(taxa_are_rows)) {
    if (methods::is(otu, "otu_table")) {
      taxa_are_rows <- phyloseq::taxa_are_rows(otu)
    } else {
      stop("`x` is not a phyloseq or otu_table object, so the orientation is ",
           "unknown -- pass taxa_are_rows = TRUE or FALSE.", call. = FALSE)
    }
  }

  # This is the whole point of the function: pick the margin by orientation
  # instead of hard-coding rownames/ncol.
  if (taxa_are_rows) {
    feature_names <- rownames(otu)
    sample_ids    <- colnames(otu)
  } else {
    feature_names <- colnames(otu)
    sample_ids    <- rownames(otu)
  }
  n_features <- length(feature_names)
  n_samples  <- length(sample_ids)

  print(sprintf("Taxa are rows: %s", taxa_are_rows))

  out <- list(
    taxa_are_rows = taxa_are_rows,
    n_features    = n_features,
    n_samples     = n_samples
  )

  # --- Features vs tree tips -------------------------------------------------
  if (is.null(tree)) {
    print("No phylogenetic tree present; skipping tip check.")
    out$tree_ok <- NA
  } else {
    tips <- tree$tip.label
    in_tree <- feature_names %in% tips

    print("Matching otu feature names and tree tip labels:")
    print(all(in_tree))
    print(sprintf("OTU features: %d ; tree tips: %d", n_features, length(tips)))
    print(sprintf("Intersection: %d", sum(in_tree)))
    if (!all(in_tree)) {
      print(sprintf("Features missing from tree: %d", sum(!in_tree)))
    }

    out$n_tips              <- length(tips)
    out$n_features_in_tree  <- sum(in_tree)
    out$features_not_in_tree <- feature_names[!in_tree]
    out$tree_ok             <- all(in_tree)
  }

  # --- Samples vs metadata ---------------------------------------------------
  if (is.null(meta)) {
    print("No sample metadata present; skipping sample check.")
    out$meta_ok <- NA
  } else {
    meta_ids <- rownames(meta)
    in_meta <- sample_ids %in% meta_ids

    print("Matching otu sample names and metadata rownames:")
    print(all(in_meta))
    print(sprintf("OTU samples: %d ; meta samples: %d", n_samples, length(meta_ids)))
    print(sprintf("Intersection: %d", sum(in_meta)))
    if (!all(in_meta)) {
      print(sprintf("Samples missing from metadata: %d", sum(!in_meta)))
    }

    out$n_meta_samples      <- length(meta_ids)
    out$n_samples_in_meta   <- sum(in_meta)
    out$samples_not_in_meta <- sample_ids[!in_meta]
    out$meta_ok             <- all(in_meta)
  }

  # NA (a piece that isn't present) is not a failure -- only a real mismatch is.
  out$ok <- all(c(out$tree_ok, out$meta_ok), na.rm = TRUE)

  invisible(out)
}
