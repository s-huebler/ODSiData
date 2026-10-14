# agglomerate_rank.R
# From Sophie Huebler
# Created 12 Oct 2026
# -----------------------------------------------------------------------------
# Collapse a phyloseq object to a taxonomic rank, with readable and unique
# taxon names, so that differential abundance results at different ranks can
# be joined back together along each ASV's lineage.
#
#   ps_genus <- agglomerate_rank(ps, "Genus")
#   taxa_names(ps_genus)   # "Blautia", "Lachnospiraceae (unassigned Genus)", ...
#
#   lin <- lineage_labels(ps, c("Genus", "Class"))
#   # one row per ASV: feature, Genus, Class  (labels match taxa_names above)
#
# Why not phyloseq::tax_glom():
#   * tax_glom() names each collapsed taxon after an arbitrary member ASV hash,
#     so results at genus level cannot be read or matched to lineages.
#   * tax_glom(NA.rm = TRUE), the default, silently DROPS every ASV that is
#     unassigned at the target rank, which removes a large share of reads at
#     Genus and most of them at Species.
#   * tax_glom() is slow on large tables; rowsum() is a single pass.
#
# Unassigned taxa are kept and pooled under their deepest assigned ancestor,
# e.g. "Lachnospiraceae (unassigned Genus)". lineage_labels() and the tax_table
# of the result carry an `assigned` flag column so these can be filtered out of
# results or figures without changing the totals that were modeled.
#
# Labels are the plain name at the rank. If one name occurs under two different
# lineages (homonyms, which happen in GTDB-style Greengenes2 names), the parent
# name is appended in brackets, e.g. "Clostridium [Clostridiaceae]".
#
# Empty strings are treated as NA (parse_taxonomy() turns a bare "s__" into "").
# The phylogenetic tree is not carried over (it describes ASVs, not groups).
# -----------------------------------------------------------------------------

library(phyloseq)

.clean_tax <- function(tax) {
  tax <- as.matrix(tax)
  tax[!is.na(tax) & trimws(tax) == ""] <- NA
  tax
}

.deepest_assigned <- function(sub) {
  if (ncol(sub) == 0) return(rep(NA_character_, nrow(sub)))
  apply(sub, 1, function(r) {
    i <- which(!is.na(r))
    if (length(i)) r[[max(i)]] else NA_character_
  })
}

# Core: label every feature at `rank`. Works on a plain taxonomy matrix so it
# can be tested without phyloseq. Returns a data.frame with one row per feature.
rank_labels <- function(tax, rank, ranks = colnames(tax)) {
  tax <- .clean_tax(tax)
  k <- match(rank, ranks)
  if (is.na(k)) stop("rank '", rank, "' not in: ", paste(ranks, collapse = ", "))

  sub      <- tax[, ranks[seq_len(k)], drop = FALSE]
  key      <- apply(sub, 1, function(r) paste(ifelse(is.na(r), "NA", r), collapse = ";"))
  assigned <- !is.na(sub[, k])
  deepest  <- .deepest_assigned(sub)

  lab <- ifelse(assigned, sub[, k],
           ifelse(is.na(deepest), paste0("Unassigned ", rank),
                  paste0(deepest, " (unassigned ", rank, ")")))

  # Disambiguate names that map to more than one lineage
  n_lineages <- tapply(key, lab, function(x) length(unique(x)))
  amb <- lab %in% names(n_lineages)[n_lineages > 1]
  if (any(amb)) {
    # parent of the name actually shown (rank k if assigned, else the deepest
    # assigned ancestor), i.e. the deepest assigned rank above that name
    shown_idx <- apply(sub, 1, function(r) {
      i <- which(!is.na(r)); if (length(i)) max(i) else 0L
    })
    parent <- vapply(which(amb), function(j) {
      i <- which(!is.na(sub[j, seq_len(max(shown_idx[j] - 1, 0))]))
      if (length(i)) sub[j, max(i)] else "NA"
    }, character(1))
    lab[amb] <- paste0(lab[amb], " [", parent, "]")
  }
  # Last resort: still ambiguous, append the full lineage key
  n_lineages <- tapply(key, lab, function(x) length(unique(x)))
  amb <- lab %in% names(n_lineages)[n_lineages > 1]
  if (any(amb)) lab[amb] <- paste0(lab[amb], " {", key[amb], "}")

  data.frame(feature  = rownames(tax),
             key      = unname(key),
             label    = unname(lab),
             assigned = unname(assigned),
             stringsAsFactors = FALSE)
}

# Collapse a phyloseq object to `rank`. Returns a phyloseq object whose
# taxa_names are the labels from rank_labels().
agglomerate_rank <- function(ps, rank) {
  ranks <- rank_names(ps)
  tax   <- .clean_tax(as(tax_table(ps), "matrix"))
  lab   <- rank_labels(tax, rank, ranks)

  otu <- as(otu_table(ps), "matrix")
  if (!taxa_are_rows(ps)) otu <- t(otu)
  grp <- lab$label[match(rownames(otu), lab$feature)]
  agg <- rowsum(otu, group = grp, reorder = FALSE)

  # One taxonomy row per group: lineage down to `rank`, NA below it
  k     <- match(rank, ranks)
  first <- match(rownames(agg), lab$label)
  newtax <- tax[lab$feature[first], ranks, drop = FALSE]
  if (k < length(ranks)) newtax[, ranks[(k + 1):length(ranks)]] <- NA
  newtax <- cbind(newtax, assigned = as.character(lab$assigned[first]))
  rownames(newtax) <- rownames(agg)

  phyloseq(otu_table(agg, taxa_are_rows = TRUE),
           tax_table(newtax),
           sample_data(ps))
}

# ASV -> label at each requested rank, for joining per-rank results along
# lineages. Labels are identical to taxa_names(agglomerate_rank(ps, rank)).
lineage_labels <- function(ps, ranks_out) {
  ranks <- rank_names(ps)
  tax   <- as(tax_table(ps), "matrix")
  out   <- data.frame(feature = rownames(tax), stringsAsFactors = FALSE)
  for (r in ranks_out) out[[r]] <- rank_labels(tax, r, ranks)$label
  out
}
