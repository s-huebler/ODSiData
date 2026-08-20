# color_tips_alt.R
# -----------------------------------------------------------------------------
# Alternate tip annotation for the merged 7-cohort tree.
#
# Instead of encoding "how many studies share this tip" in a single tip color
# (see Functions/color_tips.R), each tip gets a RING of dots outside the tree:
# one dot per study the ASV/taxon appears in, in that study's color. Counting
# dots on a tip gives the sharing level at a glance, and the hues say *which*
# cohorts.
#
#   dot_layout = "packed"  dots start immediately outside the tip and run
#                          contiguously -- easiest for counting.
#   dot_layout = "aligned" every study owns a fixed ring (slot = its position
#                          in `studies`), so a ring gap means "absent here" --
#                          easiest for reading presence per cohort.
#
# All dots are anchored at the OUTERMOST tip x, not each tip's own x, so they
# form clean concentric rings even though `branch.length = "none"` leaves tips
# at different cladogram depths.
# -----------------------------------------------------------------------------

library(phyloseq)
library(ggtree)
library(dplyr)
library(tidyr)
library(tibble)
library(ggplot2)

# `studies`, `study_colors`, study_key() and study_color() all come from here.
source("~/Documents/ODSi/ODSiData/Functions/study_colors.R")

# -----------------------------------------------------------------------------
# Helper: long table of one row per (ASV, study it occurs in), with dot slot
# -----------------------------------------------------------------------------
# NOTE: the cohort column is renamed to "Study" in base R *before* the dplyr
# chain starts. Doing it with `rename(Study = !!sym(cohort_col_name))` breaks
# the moment anything on the search path masks dplyr::rename (S4Vectors and
# plyr both export one), because a non-tidyeval rename() sees `!!sym(x)` as
# double negation and errors with "invalid argument type".
asv_dot_mapping_func <- function(phylo_obj,
                                 id_col_name = "sample.id",
                                 cohort_col_name = "study",
                                 dot_layout = c("packed", "aligned")) {

  dot_layout <- match.arg(dot_layout)

  # --- Extract OTUs (samples as rows) ----------------------------------------
  if (taxa_are_rows(phylo_obj@otu_table)) {
    otus <- as.data.frame(t(phylo_obj@otu_table))
    otus[[id_col_name]] <- colnames(phylo_obj@otu_table)
  } else {
    otus <- as.data.frame(phylo_obj@otu_table)
    otus[[id_col_name]] <- rownames(phylo_obj@otu_table)
  }

  # --- Extract metadata, and normalize the cohort column name/values ---------
  metas <- as.data.frame(unclass(phylo_obj@sam_data))
  metas[[id_col_name]] <- rownames(phylo_obj@sam_data)

  if (!cohort_col_name %in% colnames(metas)) {
    stop("Column '", cohort_col_name, "' not found in sample_data(). Available: ",
         paste(colnames(metas), collapse = ", "), call. = FALSE)
  }

  metas <- metas[, c(id_col_name, cohort_col_name), drop = FALSE]
  colnames(metas)[colnames(metas) == cohort_col_name] <- "Study"
  # "Liu2017" and "Liu" collapse to the same cohort / same hue.
  metas$Study <- study_key(metas$Study)

  # --- Presence/absence, one row per (ASV, Study) ----------------------------
  df_long <- otus %>%
    dplyr::left_join(metas, by = id_col_name) %>%
    tidyr::pivot_longer(
      cols = -dplyr::all_of(c(id_col_name, "Study")),
      names_to  = "ASV_ID",
      values_to = "Count"
    ) %>%
    dplyr::filter(Count > 0) %>%
    dplyr::distinct(ASV_ID, Study)

  # Fix the study order once, globally, so dot order is identical on every tip.
  present <- studies[studies %in% unique(df_long$Study)]
  df_long$Study <- factor(df_long$Study, levels = present)

  df_long <- df_long %>%
    dplyr::arrange(ASV_ID, Study)

  # --- Dot slot + color ------------------------------------------------------
  if (dot_layout == "aligned") {
    # Slot = the study's fixed position, so every cohort keeps its own ring.
    df_long$dot_pos <- as.integer(df_long$Study)
  } else {
    # Slot = 1, 2, 3 ... outward from the tip, no gaps.
    df_long <- df_long %>%
      dplyr::group_by(ASV_ID) %>%
      dplyr::mutate(dot_pos = dplyr::row_number()) %>%
      dplyr::ungroup()
  }

  df_long$Color <- unname(study_color(as.character(df_long$Study)))

  # Handy for downstream filtering / sanity checks.
  df_long <- df_long %>%
    dplyr::group_by(ASV_ID) %>%
    dplyr::mutate(N_Studies = dplyr::n()) %>%
    dplyr::ungroup()

  df_long
}

# -----------------------------------------------------------------------------
# Main visualization
# -----------------------------------------------------------------------------
# base_dot_offset  gap between the outermost tip (or the end of the tip labels)
#                  and the first dot ring. NULL = estimate it.
# dot_spacing      gap between consecutive dot rings.
# dot_size         point size for the study dots.
vizualize_collapse_dots <- function(phylo_obj, tax_level,
                                    id_col_name = "sample.id",
                                    cohort_col_name = "study",
                                    show_labels = FALSE,
                                    dot_layout = c("packed", "aligned"),
                                    base_dot_offset = NULL,
                                    dot_spacing = 0.8,
                                    dot_size = 1.6,
                                    label_size = 2) {

  dot_layout <- match.arg(dot_layout)

  # 1. Glom and prune -------------------------------------------------------
  if (tax_level != "ASV") {
    ps_temp <- suppressMessages(tax_glom(phylo_obj, taxrank = tax_level))
  } else {
    ps_temp <- phylo_obj
  }
  ps_temp <- prune_samples(sample_sums(ps_temp) > 0, ps_temp)

  print(ps_temp)

  # 2. Long dot data --------------------------------------------------------
  dot_data <- suppressMessages(
    asv_dot_mapping_func(ps_temp,
                         id_col_name     = id_col_name,
                         cohort_col_name = cohort_col_name,
                         dot_layout      = dot_layout)
  )

  print(table(dot_data$Study))
  print(table(dplyr::distinct(dot_data, ASV_ID, N_Studies)$N_Studies))

  # 3. Taxonomy -------------------------------------------------------------
  tax <- tax_table(ps_temp) %>%
    as.data.frame() %>%
    rownames_to_column("ASV_ID")

  # 4. Base tree ------------------------------------------------------------
  plot <- suppressWarnings(
    ggtree(phy_tree(ps_temp), layout = "circular", branch.length = "none") %<+% tax
  )

  plot <- plot + geom_tippoint(size = dot_size, alpha = 0.9, color = "gray50")

  # 5. Tip coordinates ------------------------------------------------------
  tip_coords <- plot$data %>%
    dplyr::filter(isTip) %>%
    dplyr::select(ASV_ID = label, x, y)

  max_tip_x <- max(tip_coords$x, na.rm = TRUE)

  # 6. Labels + offset ------------------------------------------------------
  # Rough width of the longest label in tree x-units; the 0.5 factor is a
  # heuristic that holds up well enough at size 2-3. Override if it collides.
  if (show_labels) {
    lab_vals   <- as.character(tax[[tax_level]])
    max_lab_ch <- max(nchar(lab_vals[!is.na(lab_vals)]), 0)
    label_pad  <- 1 + max_lab_ch * label_size * 0.5
  } else {
    label_pad <- 1
  }

  if (is.null(base_dot_offset)) base_dot_offset <- label_pad

  if (show_labels) {
    plot <- plot +
      geom_tiplab(aes(label = .data[[tax_level]]),
                  align = TRUE, linetype = "dotted", linesize = 0.2,
                  offset = 0.5, size = label_size, color = "black")
  }

  # 7. Absolute dot positions (anchored at the outermost tip -> clean rings) --
  dot_plot_data <- dot_data %>%
    dplyr::inner_join(tip_coords, by = "ASV_ID") %>%
    dplyr::mutate(x_dot = max_tip_x + base_dot_offset + dot_pos * dot_spacing)

  legend_studies <- studies[studies %in% unique(as.character(dot_data$Study))]

  # 8. Draw ------------------------------------------------------------------
  plot <- plot +
    geom_point(data = dot_plot_data,
               aes(x = x_dot, y = y, color = Color),
               size = dot_size, alpha = 0.9,
               inherit.aes = FALSE) +
    scale_color_identity(guide  = "legend",
                         name   = "Cohort",
                         breaks = unname(study_colors[legend_studies]),
                         labels = legend_studies) +
    # Keep the outermost ring inside the panel.
    expand_limits(x = max(dot_plot_data$x_dot, na.rm = TRUE) + dot_spacing) +
    ggtitle(paste0(tax_level, " Level - Study Presence"))

  plot
}
