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
            "box_x" = box_x,
            "box_y" = box_y))

}

beta_pipe <- function(phylo_obj,
                      rare_depth = NULL,
                      ord_method,
                      title_str,
                      norm_method = "rarefy",
                      box_label_positions = c("l", "l"),
                      box_label_percs = c(.95,.95),
                      overide_positions = NULL){

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

    base_plot <- plot_ordination(norm_phylo,
                             ord_obj,
                             color = "study") +
      geom_point(size = 2.5, alpha = 0.8) +          # Make points clear but slightly transparent
      stat_ellipse(type = "t", level = 0.95, linetype = 2) +
      theme_bw() +                                   # Clean background theme
      theme(legend.position = "bottom")+              # Move legend to bottom so it doesn't crowd the margins
      scale_color_manual(name = "Cohort",
                     values = cohort_colors)+
      geom_label(x = box$box_x, y = box$box_y, label = box$box_label,
             fill = "white", color = "black", fontface = "bold", size = 4) +
      ggtitle(title_str)

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
