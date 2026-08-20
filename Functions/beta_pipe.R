# beta_pipe.R
# -----------------------------------------------------------------------------
# Beta-diversity pipeline for the merged cohorts: normalize -> distance ->
# PCoA -> PERMANOVA on `study` -> annotated ordination plot with marginal
# densities.
#
# Exports:
#   permanova_label_generate()  helper: builds the "PERMANOVA: F=, p=" label and
#                               picks its x/y coordinates from the ordination.
#   beta_pipe()                 the pipeline itself.
#
# PERMANOVA label placement -- three mutually exclusive modes, checked in this
# order:
#
#   label_as_caption = TRUE   result moves off the panel into the plot caption
#                             (one line, bottom-right, below the legend). The
#                             panel is left completely clear.
#   label_corner = "tl"       label is pinned to a corner of the *panel*
#                             ("tl"/"tr"/"bl"/"br"), independent of the axis
#                             limits. Robust across the fixed +/-0.6 branch and
#                             the auto-scaled CLR/euclidean branch.
#   overide_positions         label centered on absolute data coordinates,
#                             e.g. c(-0.40, 0.52).
#
# With none of the three set, placement falls back to the original data-driven
# box_label_positions/box_label_percs behaviour, which multiplies the min or max
# observed axis coordinate by a fraction. Note that this scales *toward zero*,
# so on an axis whose min is negative a "99%" setting sits just inside the
# leftmost point rather than near the panel edge. Prefer label_corner.
#
# Points are always colored by `study`. They can optionally also be *shaped* by
# any sample_data() column via shape_var (e.g. shape_var = "agvhd" draws aGVHD
# cases as squares and non-cases as circles). Ellipses stay grouped by study
# regardless, so adding a shape never splits the per-cohort ellipses.
#
# Per-study colors come from Functions/study_colors.R. beta_pipe() sources it
# defensively if it is not already in scope.
#
# Shared across the merging/analysis notebooks -- edit here, not in a .qmd.
# -----------------------------------------------------------------------------

library(phyloseq)
library(vegan)
library(ggplot2)
library(ggExtra)

permanova_label_generate <- function(perm_res,
                                     ord_res,
                                     x_position = "l",
                                     y_position = "l",
                                     x_perc = .95,
                                     y_perc = .95){

  # 1. Extract the F and p-value from the adonis2 results
permanova_f <- perm_res$F[1]
permanova_p <- perm_res$`Pr(>F)`[1]

# Create the formatted text label for the box
# and format p-values less than 0.001 as "p < 0.001"
# For this example, let's just make it look like the plot you showed.
# We'll need some logic, as p=0.001 might be rounded from 0.0007,
# while p=0.0001 might be rounded from 0.00006.
# We'll use a rounded number to 3 decimal places as a starting point.
rounded_f <- round(permanova_f, 2)
rounded_p <- round(permanova_p, 3)

# Then we create the text label, adding logic to show < 0.001 if needed.
if (permanova_p < 0.001) {
  p_text <- "< 0.001"
} else {
  p_text <- paste0("=", rounded_p)
}

box_label <- paste0("PERMANOVA:\nF=", rounded_f, ", p", p_text)

# Single-line variant of the same result, for label_as_caption = TRUE. A caption
# is a one-line strip under the plot, so the newline that makes the on-panel box
# compact would just waste vertical space there. Spacing is loosened because the
# caption is set in a lighter, smaller face than the bold box.
if (permanova_p < 0.001) {
  p_text_inline <- "p < 0.001"
} else {
  p_text_inline <- paste0("p = ", rounded_p)
}

box_label_inline <- paste0("PERMANOVA on study: F = ", rounded_f, ", ",
                           p_text_inline, " (999 permutations)")

# We need to decide where to place the box. We will place it based on the
# coordinates in the plot, which means we have to find out what the maximum
# x and y coordinates are. We'll find them from the ordination object.
# Find the range of PCoA 1 and PCoA 2
ord_df <- as.data.frame(ord_res$vectors[, 1:2])

if(x_position == "l"){
  coord_x <- min(ord_df$Axis.1)
}else if(x_position == "u"){
    coord_x <- max(ord_df$Axis.1)
  }

if(y_position == "l"){
    coord_y <- min(ord_df$Axis.2)
  }else if(y_position == "u"){
    coord_y <- max(ord_df$Axis.2)
  }



# Set the corner position of the label relative to the plot.
# We'll use 90% of the max range for each axis.
# Adjust these values based on your specific plot data.
box_x <- coord_x * as.numeric(x_perc)
box_y <- coord_y * as.numeric(y_perc)


return(list("box_label" = box_label,
            "box_label_inline" = box_label_inline,
            "box_x" = box_x,
            "box_y" = box_y))

}

# Corner keyword -> the arguments annotate() needs to pin a label to a panel
# corner. x/y are +/-Inf, which ggplot resolves to the panel edge *after* the
# scales are built, so the placement holds whether the limits are the fixed
# +/-0.6 pair or auto-scaled CLR values. hjust/vjust are multiples of the
# label's own width/height, so nudging them slightly past 0/1 insets the box by
# a constant fraction of itself rather than by a data distance. The two insets
# differ because the box is wide and short: the same fraction of its width is a
# much bigger visual gap than that fraction of its height.
permanova_corner_args <- function(corner, inset_x = 0.06, inset_y = 0.35){

  corner <- tolower(as.character(corner))

  valid <- c("tl", "tr", "bl", "br")
  if (length(corner) != 1 || !corner %in% valid) {
    stop("label_corner must be one of: ", paste(valid, collapse = ", "),
         " (top-left, top-right, bottom-left, bottom-right).")
  }

  left   <- substr(corner, 2, 2) == "l"
  top    <- substr(corner, 1, 1) == "t"

  list(x     = if (left) -Inf else Inf,
       y     = if (top)   Inf else -Inf,
       hjust = if (left) -inset_x else 1 + inset_x,
       vjust = if (top)  1 + inset_y else -inset_y)
}

beta_pipe <- function(phylo_obj,
                      rare_depth = NULL,
                      ord_method,
                      title_str,
                      norm_method = "rarefy",
                      box_label_positions = c("l", "l"),
                      box_label_percs = c(.95,.95),
                      overide_positions = NULL,
                      label_corner = NULL,
                      label_as_caption = FALSE,
                      shape_var = NULL,
                      shape_values = NULL,
                      shape_name = NULL,
                      shape_labels = NULL){

  # label_corner     "tl", "tr", "bl" or "br" -- pin the PERMANOVA box to that
  #                  corner of the panel, independent of the axis limits. NULL
  #                  (the default) keeps the legacy data-driven coordinates.
  # label_as_caption TRUE moves the PERMANOVA result off the panel and into the
  #                  plot caption, leaving the ordination area clear. Overrides
  #                  label_corner and overide_positions.
  # shape_var    name of a sample_data() column used for point shape. NULL (the
  #              default) reproduces the old behaviour: every point is a filled
  #              circle and no shape legend is drawn.
  # shape_values shapes to use, either unnamed in level order or named by level
  #              (e.g. c(No = 16, Yes = 15)). Default: circle, square, triangle,
  #              diamond, star, plus -- and an x for "Unknown".
  # shape_name   legend title for the shape scale. Default: the column name.
  # shape_labels legend labels, either unnamed in level order or named by raw
  #              value (e.g. c(`0` = "No aGVHD", `1` = "aGVHD")). Binary 0/1 and
  #              logical columns default to "No"/"Yes".

  # 1) Normalize

  if (norm_method == "rarefy") {
    if (is.null(rare_depth)) stop("Must provide rare_depth when norm_method is 'rarefy'")

    norm_phylo <- phyloseq::rarefy_even_depth(phylo_obj,
                                              sample.size = rare_depth,
                                              replace = FALSE)

     norm_phylo <- prune_taxa(taxa_sums(norm_phylo)>0,
                             norm_phylo)
    norm_phylo <- prune_samples(sample_sums(norm_phylo)>0,
                                norm_phylo)
  } else if (norm_method == "logCPM") {
    # Calculate log2 Counts Per Million with a pseudocount of 1 to handle zeros
    norm_phylo <- phyloseq::transform_sample_counts(phylo_obj, function(x) {
      log2(((x / sum(x)) * 1e6) + 1)
    })

    norm_phylo <- prune_taxa(taxa_sums(norm_phylo)>0,
                             norm_phylo)
    norm_phylo <- prune_samples(sample_sums(norm_phylo)>0,
                                norm_phylo)

  } else if(norm_method == "identity"){
    norm_phylo <- phylo_obj
    print("No normalization used, make sure that supplied phylo_obj has normalized relative abundance data")
    if(ord_method != "euclidean"){
    norm_phylo <- prune_taxa(taxa_sums(norm_phylo)>0,
                             norm_phylo)
    norm_phylo <- prune_samples(sample_sums(norm_phylo)>0,
                                norm_phylo)
    }

  }else if(norm_method == "clr"){
    # Centered log-ratio (CLR) transform with a naive pseudocount of 1.
    # Extract counts as a samples (rows) x taxa (cols) matrix so we can
    # apply the CLR one sample at a time, then rebuild a phyloseq object
    # that keeps the original sample_data() and tax_table() attached.
    otu <- as(otu_table(phylo_obj), "matrix")
    if (taxa_are_rows(phylo_obj)) {
      otu <- t(otu)   # ensure samples are rows, taxa are columns
    }

    imputed <- otu + 1                                   # naive zero imputation
    clr_mat <- t(apply(imputed, 1,
                       function(r) as.numeric(compositions::clr(r))))
    rownames(clr_mat) <- rownames(imputed)
    colnames(clr_mat) <- colnames(imputed)

    clr_otu <- otu_table(clr_mat, taxa_are_rows = FALSE)
    norm_phylo <- phyloseq(clr_otu,
                           sample_data(phylo_obj),
                           tax_table(phylo_obj))
  } else{
    stop("norm_method must be either 'rarefy' or 'logCPM' or 'identity' or 'clr")
  }

  # 2) Ordination


  if(norm_method == "clr"){
    # CLR data lives in Aitchison (Euclidean) space, so ordination is PCA with
    # Euclidean distance. PCoA on a Euclidean distance matrix is equivalent to
    # PCA and keeps the downstream ord object structure ($vectors / Axis.1 /
    # Axis.2) intact for permanova_label_generate() and plot_ordination().
    if(!missing(ord_method) && !is.null(ord_method) && ord_method != "euclidean"){
      warning("norm_method = 'clr' requires PCA with Euclidean distance; the ",
              "supplied ord_method = '", ord_method, "' is incompatible and is ",
              "being ignored. Using Euclidean distance instead.")
    }
    distance_obj <- phyloseq::distance(norm_phylo, method = "euclidean")
  } else {
    if(ord_method %in% c("bray")){
      distance_obj <- phyloseq::distance(norm_phylo, method = ord_method)
    }
    if(ord_method %in% c("unifrac")){
     distance_obj <-  phyloseq::distance(norm_phylo, method = ord_method,
                         weighted = FALSE)
    }
    if(ord_method %in% c("wunifrac")){
     distance_obj <-  phyloseq::distance(norm_phylo, method = "unifrac",
                         weighted = TRUE)
    }
    if(ord_method %in% c("euclidean")){
     distance_obj <- phyloseq::distance(norm_phylo, method = "euclidean")
    }
  }

    ord_obj <- ordinate(norm_phylo,
                        method = "PCoA",
                        distance = distance_obj)

    perm_res <- adonis2(
      distance_obj ~ study,
      data = data.frame(sample_data(norm_phylo)),
      permutations = 999)

    box <- permanova_label_generate(perm_res, ord_obj,
                                    box_label_positions[1], box_label_positions[2],
                                    as.numeric(box_label_percs[1]), as.numeric(box_label_percs[2]))

     if(!is.null(overide_positions)){
   box$box_x <- overide_positions[1]
   box$box_y <- overide_positions[2]
 }

    #print(box)

  # 2c) PERMANOVA label layer
  # ---------------------------------------------------------------------------
  # Built here so the placement decision is in one place. The layer is drawn
  # with annotate() rather than geom_label(): geom_label() inherits the plot's
  # data, so passing x/y/label as fixed parameters draws one identical label per
  # *sample* -- a few hundred stacked copies, which is what made the box read as
  # unusually heavy and bloated vector output. annotate() builds a one-row layer.
  if (isTRUE(label_as_caption)) {
    if (!is.null(label_corner) || !is.null(overide_positions)) {
      warning("label_as_caption = TRUE overrides label_corner / ",
              "overide_positions; the PERMANOVA result is going in the caption.")
    }
    permanova_layer <- NULL
  } else if (!is.null(label_corner)) {
    if (!is.null(overide_positions)) {
      warning("Both label_corner and overide_positions were supplied; using ",
              "label_corner = '", label_corner, "'.")
    }
    corner <- permanova_corner_args(label_corner)
    permanova_layer <- annotate("label",
                                x = corner$x, y = corner$y,
                                hjust = corner$hjust, vjust = corner$vjust,
                                label = box$box_label,
                                fill = "white", color = "black",
                                fontface = "bold", size = 4,
                                label.size = 0.3)
  } else {
    permanova_layer <- annotate("label",
                                x = box$box_x, y = box$box_y,
                                label = box$box_label,
                                fill = "white", color = "black",
                                fontface = "bold", size = 4,
                                label.size = 0.3)
  }

  # 2b) Optional shape aesthetic
  # ---------------------------------------------------------------------------
  # shape_var names a column in sample_data(). It is coerced to a factor and
  # written to a scratch column ("shape_grp") on the *normalized* object, because
  # plot_ordination() maps aesthetics by column name and we don't want to
  # overwrite the harmonized column itself. Binary 0/1 and logical columns get
  # "No"/"Yes" labels by default (harmonized outcome variables are 1/0 coded);
  # anything else keeps its own levels. NAs become an explicit "Unknown" level so
  # samples missing the variable still plot instead of being silently dropped.
  use_shape <- !is.null(shape_var)
  shape_col_name <- NULL
  shape_vals <- NULL

  if (use_shape) {
    samp_df <- as(sample_data(norm_phylo), "data.frame")

    if (!shape_var %in% colnames(samp_df)) {
      stop("shape_var = '", shape_var, "' is not a column in sample_data(). ",
           "Available columns: ", paste(colnames(samp_df), collapse = ", "))
    }

    raw_shape <- samp_df[[shape_var]]
    raw_chr   <- as.character(raw_shape)
    n_missing <- sum(is.na(raw_shape))
    raw_levels <- sort(unique(raw_chr[!is.na(raw_chr)]))

    if (length(raw_levels) == 0) {
      stop("shape_var = '", shape_var, "' is entirely NA for these samples.")
    }

    if (is.null(shape_labels)) {
      is_binary <- is.logical(raw_shape) || all(raw_levels %in% c("0", "1"))
      if (is_binary) {
        lab <- ifelse(is.na(raw_chr), NA_character_,
                      ifelse(raw_chr %in% c("1", "TRUE"), "Yes", "No"))
        # Both levels are kept even if only one is observed, so "Yes" is always
        # the square; scale_shape_manual() drops the unused key from the legend.
        shape_fac <- factor(lab, levels = c("No", "Yes"))
      } else {
        shape_fac <- factor(raw_chr, levels = raw_levels)
      }
    } else if (!is.null(names(shape_labels))) {
      unmapped <- setdiff(raw_levels, names(shape_labels))
      if (length(unmapped) > 0) {
        stop("shape_labels is missing an entry for: ",
             paste(unmapped, collapse = ", "))
      }
      keep <- names(shape_labels)[names(shape_labels) %in% raw_levels]
      shape_fac <- factor(unname(shape_labels[raw_chr]),
                          levels = unique(unname(shape_labels[keep])))
    } else {
      if (length(shape_labels) != length(raw_levels)) {
        stop("shape_labels has ", length(shape_labels), " entries but '",
             shape_var, "' has ", length(raw_levels), " observed values (",
             paste(raw_levels, collapse = ", "), "). Supply one label per value ",
             "or a named vector.")
      }
      shape_fac <- factor(raw_chr, levels = raw_levels, labels = shape_labels)
    }

    if (n_missing > 0) {
      shape_fac <- factor(ifelse(is.na(shape_fac), "Unknown", as.character(shape_fac)),
                          levels = c(levels(shape_fac), "Unknown"))
    }

    shape_lev <- levels(shape_fac)

    if (is.null(shape_values)) {
      # circle, square, triangle, diamond, star, plus -- solid shapes first so a
      # two-level variable reads as "dots vs squares".
      default_shapes <- c(16, 15, 17, 18, 8, 3)
      if (length(shape_lev) > length(default_shapes)) {
        stop("'", shape_var, "' has ", length(shape_lev), " levels; only ",
             length(default_shapes), " default shapes are defined. Pass ",
             "shape_values explicitly.")
      }
      shape_vals <- default_shapes[seq_along(shape_lev)]
      names(shape_vals) <- shape_lev
      if (n_missing > 0) shape_vals[["Unknown"]] <- 4   # x for missing
    } else if (!is.null(names(shape_values))) {
      unmapped <- setdiff(shape_lev, names(shape_values))
      if (length(unmapped) > 0) {
        stop("shape_values is missing an entry for: ",
             paste(unmapped, collapse = ", "))
      }
      shape_vals <- shape_values[shape_lev]
    } else {
      if (length(shape_values) != length(shape_lev)) {
        stop("shape_values has ", length(shape_values), " entries but the shape ",
             "variable has ", length(shape_lev), " levels (",
             paste(shape_lev, collapse = ", "), ").")
      }
      shape_vals <- shape_values
      names(shape_vals) <- shape_lev
    }

    # Scratch column, uniquified so an existing "shape_grp" is never clobbered.
    shape_col_name <- "shape_grp"
    while (shape_col_name %in% colnames(samp_df)) {
      shape_col_name <- paste0(shape_col_name, "_")
    }
    samp_df[[shape_col_name]] <- shape_fac
    sample_data(norm_phylo) <- sample_data(samp_df)
  }

  # 3) Plot

    # Per-study colors come from the shared palette in Functions/study_colors.R
    # (one Okabe-Ito hue per cohort). It is normally in scope already because
    # color_tips.R (sourced in the Visualizing section) sources it; source
    # defensively so beta_pipe still works if this chunk is run on its own.
    if (!exists("study_color")) {
      source("~/Documents/ODSi/ODSiData/Functions/study_colors.R")
    }

    # study_color() keys on the bare surname ("Artacho", "Liu") and strips a
    # trailing year, so an object still carrying legacy "StudyYYYY" labels maps
    # onto the palette instead of silently dropping to NA. Names on the result
    # are the labels as they appear in the data, which is what
    # scale_color_manual() needs to match the factor levels.
    present_studies <- sort(unique(as.character(sample_data(norm_phylo)$study)))
    cohort_colors <- study_color(present_studies)

    if (use_shape) {
      base_plot <- plot_ordination(norm_phylo,
                                   ord_obj,
                                   color = "study",
                                   shape = shape_col_name)
    } else {
      base_plot <- plot_ordination(norm_phylo,
                                   ord_obj,
                                   color = "study")
    }

    # stat_ellipse() is pinned to group = study: ggplot's default grouping is the
    # interaction of every discrete aesthetic, so without this a shape mapping
    # would silently split each cohort's ellipse into one per shape level.
    base_plot <- base_plot +
      geom_point(size = 2.5, alpha = 0.8) +          # Make points clear but slightly transparent
      stat_ellipse(aes(group = study), type = "t", level = 0.95, linetype = 2) +
      theme_bw() +                                   # Clean background theme
      theme(legend.position = "bottom")+              # Move legend to bottom so it doesn't crowd the margins
      scale_color_manual(name = "Cohort",
                     values = cohort_colors)+
      permanova_layer +
      ggtitle(title_str)

    # With label_as_caption the box is NULL above and the result is set below
    # the legend instead. Left-justified so it reads as a statistical footnote
    # rather than a stray right-aligned credit line.
    if (isTRUE(label_as_caption)) {
      base_plot <- base_plot +
        labs(caption = box$box_label_inline) +
        theme(plot.caption = element_text(hjust = 0, size = 9,
                                          color = "grey20"))
    }

    if (use_shape) {
      base_plot <- base_plot +
        scale_shape_manual(name = if (is.null(shape_name)) shape_var else shape_name,
                           values = shape_vals) +
        # Draw the shape legend keys in black so they read as shapes, not as a
        # second (meaningless) copy of the cohort colors.
        guides(shape = guide_legend(override.aes = list(color = "black",
                                                        alpha = 1)))
    }

  # Fixed axis limits suit the relative-abundance PCoA scale; CLR/PCA lives on a
  # much larger scale, so let ggplot auto-scale the axes in that case.
  if(norm_method != "clr" & !(norm_method == "identity" & ord_method == "euclidean")){
    base_plot <- base_plot +
      xlim(-.6, .6)+
      ylim(-.6, .6)
  }

  # Add the marginal distributions using ggExtra
final_plot <- ggMarginal(base_plot,
                         type = "density",       # Change to "boxplot" or "histogram" if preferred
                         groupColour = TRUE,
                         groupFill = TRUE,
                         alpha = 0.4)            # Transparency for overlapping distributions


final_plot


}
