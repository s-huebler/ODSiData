# persistence_tree.R
# From Sophie Huebler
# Created 12 Oct 2026
# -----------------------------------------------------------------------------
# Draw differential abundance results from several taxonomic ranks on one
# taxonomy tree (root -> phylum -> ... -> genus -> species -> ASV), so that an
# effect that persists up a lineage shows as a run of highlighted nodes joined
# by highlighted edges.
#
#   td <- persistence_tree_data(lineage, results_all,
#                               ranks = c("Phylum", "Class", "Order", "Family",
#                                         "Genus", "Species", "ASV"))
#   plot_persistence_tree(td)
#
# Inputs are deliberately generic so the same tool works for any DA method:
#   lineage  one row per leaf; a column per rank holding the taxon label of that
#            leaf at that rank (lineage_labels() from agglomerate_rank.R, plus a
#            leaf column, by default "ASV" = the feature ID).
#   results  long table, one row per tested taxon: rank, feature (label),
#            effect, and a logical significance column.
#
# Edges are marked "persistent" when parent and child are both significant with
# the same sign. Unassigned placeholder groups ("X (unassigned Genus)") are
# skipped by default, so an ASV with no genus call hangs straight off its
# family; their results are still in `results`, just not drawn.
#
# check_monophyly() tests whether each taxon is a clade of the phylogeny, which
# is what makes collapsing to a rank equivalent to collapsing a clade.
#
# Uses ggraph/tidygraph rather than ggtree so the phyloseq/tidytree "phylo"
# class clash is not triggered.
# -----------------------------------------------------------------------------

library(dplyr)
library(tidyr)
library(ggplot2)
library(tidygraph)
library(ggraph)

.is_unassigned <- function(x) grepl(" \\(unassigned [A-Za-z]+\\)$|^Unassigned ", x)

persistence_tree_data <- function(lineage, results,
                                  ranks,
                                  leaf_col          = "ASV",
                                  leaf_from         = "feature",
                                  effect_col        = "coef",
                                  sig_col           = "sig",
                                  skip_unassigned   = TRUE,
                                  keep              = c("sig_lineages", "all")) {
  keep <- match.arg(keep)
  lineage <- as.data.frame(lineage)
  if (!leaf_col %in% names(lineage)) lineage[[leaf_col]] <- lineage[[leaf_from]]
  stopifnot(all(ranks %in% names(lineage)), tail(ranks, 1) == leaf_col)

  res <- results %>%
    transmute(rank   = as.character(rank),
              label  = as.character(feature),
              effect = .data[[effect_col]],
              sig    = coalesce(as.logical(.data[[sig_col]]), FALSE))

  # Long lineage: one row per leaf x rank, in root-to-leaf order
  long <- lineage %>%
    dplyr::select(all_of(ranks)) %>%
    mutate(.leaf = .data[[leaf_col]]) %>%
    pivot_longer(all_of(ranks), names_to = "rank", values_to = "label") %>%
    mutate(rank_idx = match(rank, ranks)) %>%
    filter(!is.na(label))
  if (skip_unassigned) long <- filter(long, !.is_unassigned(label))

  long <- long %>%
    left_join(res, by = c("rank", "label")) %>%
    mutate(sig = coalesce(sig, FALSE),
           id  = paste(rank, label, sep = "::"))

  if (keep == "sig_lineages") {
    keep_leaves <- long %>% group_by(.leaf) %>% summarise(any_sig = any(sig)) %>%
      filter(any_sig) %>% pull(.leaf)
    if (!length(keep_leaves)) stop("No significant taxa on any lineage; use keep = 'all'")
    long <- filter(long, .leaf %in% keep_leaves)
  }

  # Edges: consecutive drawn nodes along each lineage, root first
  edges <- long %>%
    arrange(.leaf, rank_idx) %>%
    group_by(.leaf) %>%
    mutate(from = lag(id, default = "root")) %>%
    ungroup() %>%
    distinct(from, to = id)

  nodes <- long %>%
    distinct(id, rank, rank_idx, label, effect, sig) %>%
    bind_rows(tibble(id = "root", rank = "root", rank_idx = 0L,
                     label = "root", effect = NA_real_, sig = FALSE)) %>%
    mutate(height    = length(ranks) - rank_idx,
           direction = case_when(sig & effect > 0 ~ "Higher in aGVHD",
                                 sig & effect < 0 ~ "Lower in aGVHD",
                                 is.na(effect)    ~ "Not tested",
                                 TRUE             ~ "Not significant"))

  if (anyDuplicated(nodes$id)) stop("A taxon label maps to two lineages: ",
                                    paste(unique(nodes$id[duplicated(nodes$id)]), collapse = ", "))

  # Persistent edge: both ends significant, same sign
  edges <- edges %>%
    left_join(dplyr::select(nodes, from = id, f_sig = sig, f_eff = effect), by = "from") %>%
    left_join(dplyr::select(nodes, to   = id, t_sig = sig, t_eff = effect), by = "to") %>%
    mutate(persistent = f_sig & t_sig & sign(f_eff) == sign(t_eff),
           persistent = coalesce(persistent, FALSE)) %>%
    dplyr::select(from, to, persistent)

  list(graph = tbl_graph(nodes = nodes, edges = edges, node_key = "id"),
       ranks = ranks, leaf_col = leaf_col)
}

plot_persistence_tree <- function(td,
                                  circular     = FALSE,
                                  label_ranks  = setdiff(td$ranks, td$leaf_col),
                                  label_size   = 3,
                                  colors       = c("Higher in aGVHD" = "#b2182b",
                                                   "Lower in aGVHD"  = "#2166ac",
                                                   "Not significant" = "grey70",
                                                   "Not tested"      = "grey90")) {
  ranks <- td$ranks

  # Rectangular: lay out the dendrogram, then turn it on its side by hand
  # (coord_flip breaks the repelled labels). Root on the left, leaves right.
  lay <- create_layout(td$graph, layout = "dendrogram", circular = circular,
                       height = height)
  if (!circular) {
    leaf_pos <- lay$x
    lay$x <- lay$rank_idx
    lay$y <- -leaf_pos
  }

  p <- ggraph(lay) +
    geom_edge_elbow(aes(edge_colour = persistent, edge_width = persistent),
                    flipped = !circular, show.legend = FALSE) +
    scale_edge_colour_manual(values = c(`FALSE` = "grey80", `TRUE` = "grey20")) +
    scale_edge_width_manual(values = c(`FALSE` = 0.3, `TRUE` = 1.1)) +
    geom_node_point(aes(filter = rank != "root", fill = direction,
                        size = sig), shape = 21, stroke = 0.3) +
    scale_fill_manual(values = colors, name = NULL, drop = FALSE) +
    scale_size_manual(values = c(`FALSE` = 1.2, `TRUE` = 3.5), guide = "none") +
    geom_node_text(aes(filter = sig & rank %in% label_ranks, label = label),
                   repel = TRUE, size = label_size, max.overlaps = Inf,
                   min.segment.length = 0, segment.colour = "grey60")

  if (!circular) {
    p <- p +
      scale_x_continuous(breaks = seq_along(ranks), labels = ranks,
                         expand = expansion(mult = 0.05)) +
      theme_minimal() +
      theme(panel.grid = element_blank(), axis.title = element_blank(),
            axis.text.y = element_blank(), legend.position = "bottom")
  } else {
    p <- p + coord_fixed() + theme_void() + theme(legend.position = "bottom")
  }
  p
}

# Is each taxon a clade of the phylogeny? Returns one row per rank x taxon.
# Single-leaf taxa are trivially monophyletic and reported as such.
check_monophyly <- function(tree, lineage, ranks, leaf_col = "feature") {
  if (!ape::is.rooted(tree)) warning("Tree is unrooted; monophyly is not well defined")
  lineage <- as.data.frame(lineage)
  lineage <- lineage[lineage[[leaf_col]] %in% tree$tip.label, , drop = FALSE]
  bind_rows(lapply(ranks, function(r) {
    grp <- split(lineage[[leaf_col]], lineage[[r]])
    tibble(rank         = r,
           label        = names(grp),
           n_leaves     = lengths(grp),
           unassigned   = .is_unassigned(names(grp)),
           monophyletic = vapply(grp, function(tips)
             length(tips) == 1 || ape::is.monophyletic(tree, tips), logical(1)))
  }))
}
