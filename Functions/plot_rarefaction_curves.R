# Load required libraries
library(phyloseq)
library(vegan)
library(ggplot2)
library(dplyr)
library(tidyr)
library(patchwork)

plot_rarefaction_curves <- function(phylo_obj,
                                    step_size = 100, 
                                    xmax = 3000, 
                                    aggregate = TRUE) {
  
  # 1. Define custom color mapping
  study_colors <- c(
    "Artacho"  = "#E69F00",  
    "DAmico"   = "#56B4E9",  
    "Fujimoto" = "#009E73",  
    "Ingham"   = "#F0E442",  
    "Jarosch"  = "#0072B2",  
    "Liu"      = "#D55E00",  
    "Vallet"   = "#CC79A7"
  )
  
  # ==========================================
  # DATA PREP: PLOT 1 (Observed Richness)
  # ==========================================
  otu_matrix <- as(otu_table(phylo_obj), "matrix")
  if (taxa_are_rows(phylo_obj)) {
    otu_matrix <- t(otu_matrix)
  }
  
  rare_data <- rarecurve(otu_matrix, step = step_size, tidy = TRUE)
  colnames(rare_data) <- c("SampleID", "Depth", "Richness")
  
  metadata <- as(sample_data(phylo_obj), "data.frame")
  metadata$SampleID <- rownames(metadata)
  
  plot_data_richness <- left_join(rare_data, metadata, by = "SampleID")
  
  # ==========================================
  # DATA PREP: PLOT 2 (Sample Retention)
  # ==========================================
  sample_totals <- sample_sums(phylo_obj)
  max_depth <- max(sample_totals)
  depth_seq <- seq(1, max_depth, by = step_size)
  
  sample_info <- data.frame(
    SampleID = names(sample_totals),
    TotalReads = sample_totals,
    study = metadata$study[match(names(sample_totals), metadata$SampleID)]
  )
  
  retention_list <- lapply(depth_seq, function(d) {
    sample_info %>%
      filter(TotalReads >= d) %>%
      count(study, name = "SamplesRetained") %>%
      mutate(Depth = d)
  })
  
  plot_data_retention <- bind_rows(retention_list) %>%
    complete(Depth, study, fill = list(SamplesRetained = 0))
  
  # ==========================================
  # BUILD PLOT 1: RICHNESS
  # ==========================================
  if (aggregate) {
    # Calculate average richness per study at each depth
    plot_data_agg <- plot_data_richness %>%
      group_by(study, Depth) %>%
      summarise(Richness = mean(Richness, na.rm = TRUE), .groups = "drop")
    
    p1 <- ggplot(plot_data_agg, aes(x = Depth, y = Richness, group = study)) +
      geom_line(aes(color = study), linewidth = 1.2) + # Thicker line for average
      scale_color_manual(values = study_colors)
  } else {
    # Plot individual samples
    p1 <- ggplot(plot_data_richness, aes(x = Depth, y = Richness, group = SampleID)) +
      geom_line(aes(color = study), alpha = 0.5, linewidth = 0.6) +
      scale_color_manual(values = study_colors)
  }
  
  p1 <- p1 +
    theme_bw() +
    labs(
      x = NULL,
      y = "Observed Richness",
      title = "Alpha Rarefaction"
    ) +
    theme(
      panel.grid.minor = element_blank(),
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank()
    )
  
  # ==========================================
  # BUILD PLOT 2: RETENTION
  # ==========================================
  p2 <- ggplot(plot_data_retention, aes(x = Depth, y = SamplesRetained, group = study)) +
    geom_step(aes(color = study), linewidth = 0.9) +
    scale_color_manual(values = study_colors) +
    theme_bw() +
    labs(
      x = "Sequencing Depth (Reads)",
      y = "Retained Samples",
      color = "Study"
    ) +
    theme(
      panel.grid.minor = element_blank()
    )
  
  # ==========================================
  # APPLY X-AXIS LIMITS
  # ==========================================
  if (!is.null(xmax)) {
    p1 <- p1 + coord_cartesian(xlim = c(0, xmax))
    p2 <- p2 + coord_cartesian(xlim = c(0, xmax))
  }
  
  # ==========================================
  # COMBINE WITH PATCHWORK
  # ==========================================
  combined_plot <- p1 / p2 + plot_layout(guides = "collect") & theme(legend.position = "right")
  
  return(combined_plot)
}
