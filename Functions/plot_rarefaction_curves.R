# Load required libraries
library(phyloseq)
library(vegan)
library(ggplot2)
library(dplyr)
library(tidyr)
library(patchwork)

# Per-cohort colors: single definition, do not re-declare study_colors here.
source("~/Documents/ODSi/ODSiData/Functions/study_colors.R")

# -----------------------------------------------------------------------------
# Alpha rarefaction curves, aggregated the way QIIME2 `diversity
# alpha-rarefaction` does it.
#
# WHY NOT rarecurve():  vegan::rarecurve(x, step = s) builds each sample's
# depth sequence as seq(1, tot[i], by = s) and then APPENDS that sample's exact
# library size if it is not already on the grid. Samples therefore share the
# grid 1, 1+s, 1+2s, ... plus one off-grid terminal point unique to each
# sample. Aggregating on raw Depth then produces groups of size 1 at every
# terminal point -- max()/mean() of a singleton collapses to that one sample's
# value and the next grid row recovers, which renders as a one-row-wide spike.
# Studies with small libraries (Ingham, Jarosch) sawtooth worst, because nearly
# every depth in range is somebody's terminal point.
#
# Instead this builds ONE common depth grid, drops samples that cannot support
# a given depth, and calls vegan::rarefy() directly. That mirrors QIIME2:
#   - depths from linspace(min_depth, max_depth, n_steps)   [QIIME default 10]
#   - a sample with fewer reads than the depth is EXCLUDED, not carried at its
#     own observed richness
#   - the plotted line is a central statistic (median) across the retained
#     samples, with the inter-quartile band shown so dropout is visible
#
# Difference that remains: QIIME subsamples `iterations` times and takes the
# median across iterations, whereas vegan::rarefy() returns Hurlbert's
# closed-form expected richness. The analytic version is deterministic and
# smoother within a sample; no iteration argument is needed here.
#
# Arguments
#   phylo_obj  phyloseq object; sample_data must carry a `study` column
#   xmax       deepest depth to evaluate/plot (capped at the largest library)
#   n_steps    number of evenly spaced depths (QIIME's --p-steps)
#   min_depth  shallowest depth (QIIME's --p-min-depth)
#   aggregate  name of a summary function applied across samples within a
#              study at each depth ("median", "mean", "max", ...).
#              NULL plots one line per sample instead.
#   ribbon     length-2 quantile probs for the band around the aggregate line,
#              or NULL to suppress it. Always describes the sample
#              distribution, independent of which `aggregate` line is drawn.
#   step_size  legacy argument. If supplied, the grid is built by this step
#              instead of by n_steps. Safe now that the grid is shared.
#
# Returns a patchwork object. The underlying tables are attached as
# attr(p, "rarefaction_data") = list(curves, agg, retention) so a suspicious
# wiggle can be checked against n_samples without re-running the whole thing.
# -----------------------------------------------------------------------------
plot_rarefaction_curves <- function(phylo_obj,
                                    xmax      = 3000,
                                    n_steps   = 10,
                                    min_depth = 1,
                                    aggregate = "median",
                                    ribbon    = c(0.25, 0.75),
                                    step_size = NULL) {

  if (!is.null(ribbon) && length(ribbon) != 2) {
    stop("`ribbon` must be a length-2 vector of quantile probabilities, or NULL.",
         call. = FALSE)
  }

  # Map the study labels this object actually carries onto the shared palette.
  # study_color() tolerates either "Liu" or "Liu2017", so the scales below
  # cover every level present rather than dropping one to gray.
  cohort_colors <- study_color(
    sort(unique(as.character(sample_data(phylo_obj)$study)))
  )

  otu_matrix <- as(otu_table(phylo_obj), "matrix")
  if (taxa_are_rows(phylo_obj)) {
    otu_matrix <- t(otu_matrix)
  }

  metadata <- as(sample_data(phylo_obj), "data.frame")
  metadata$SampleID <- rownames(metadata)

  sample_totals <- rowSums(otu_matrix)

  # ==========================================
  # COMMON DEPTH GRID
  # ==========================================
  # Cap at the largest library present: grid points beyond it retain zero
  # samples and would draw a line to nowhere.
  grid_max <- min(xmax, max(sample_totals))
  if (grid_max < min_depth) {
    stop("No sample reaches min_depth (", min_depth, "). Deepest library is ",
         max(sample_totals), ".", call. = FALSE)
  }

  depth_grid <- if (!is.null(step_size)) {
    unique(c(seq(min_depth, grid_max, by = step_size), grid_max))
  } else {
    unique(round(seq(min_depth, grid_max, length.out = n_steps)))
  }

  # ==========================================
  # DATA PREP: PLOT 1 (Observed Richness)
  # ==========================================
  # GOTCHA: vegan::rarefy(x, sample = d) does NOT drop samples whose total is
  # below d. It warns and silently returns their OBSERVED (unrarefied)
  # richness -- a value measured at that sample's own shallower depth, plotted
  # as if it were the value at d. Those samples then persist in the curve at
  # depths they cannot support, and the aggregate pools numbers computed at
  # different depths. Verified: at depth 1500 on a ragged test cohort, only
  # 13/45 samples qualify, and the unmasked call returns exactly
  # rowSums(x > 0) for the other 32. The `keep` mask is load-bearing.
  rare_data <- bind_rows(lapply(depth_grid, function(d) {
    keep <- sample_totals >= d
    if (!any(keep)) return(NULL)
    data.frame(
      SampleID = rownames(otu_matrix)[keep],
      Depth    = d,
      Richness = as.numeric(rarefy(otu_matrix[keep, , drop = FALSE], sample = d)),
      stringsAsFactors = FALSE
    )
  }))

  plot_data_richness <- left_join(rare_data, metadata, by = "SampleID")

  # ==========================================
  # DATA PREP: PLOT 2 (Sample Retention)
  # ==========================================
  # Evaluated on a finer grid than the richness curve so the step function is
  # drawn faithfully; points are overlaid at the richness depths so the number
  # of samples behind each aggregated point can be read directly.
  fine_step <- max(1L, as.integer(round(grid_max / 200)))
  retention_grid <- unique(c(seq(min_depth, grid_max, by = fine_step), grid_max))

  sample_info <- data.frame(
    SampleID   = names(sample_totals),
    TotalReads = sample_totals,
    study      = metadata$study[match(names(sample_totals), metadata$SampleID)],
    stringsAsFactors = FALSE
  )

  retention_at <- function(depths) {
    bind_rows(lapply(depths, function(d) {
      sample_info %>%
        filter(TotalReads >= d) %>%
        count(study, name = "SamplesRetained") %>%
        mutate(Depth = d)
    })) %>%
      complete(Depth, study, fill = list(SamplesRetained = 0))
  }

  plot_data_retention <- retention_at(retention_grid)
  retention_marks     <- retention_at(depth_grid)

  # ==========================================
  # BUILD PLOT 1: RICHNESS
  # ==========================================
  plot_data_agg <- NULL

  if (!is.null(aggregate)) {
    agg_func <- match.fun(aggregate)
    rib      <- if (is.null(ribbon)) c(0.25, 0.75) else ribbon

    # GOTCHA (same family as the transmute() shadowing rule in CLAUDE.md):
    # summarise() evaluates sequentially, so a column named `Richness` computed
    # first would shadow the source column for every expression after it. The
    # aggregate is therefore built last under a distinct name and renamed.
    plot_data_agg <- plot_data_richness %>%
      group_by(study, Depth) %>%
      summarise(
        lower     = quantile(Richness, rib[1], na.rm = TRUE),
        upper     = quantile(Richness, rib[2], na.rm = TRUE),
        agg_value = agg_func(Richness, na.rm = TRUE),
        n_samples = dplyr::n(),
        .groups   = "drop"
      ) %>%
      dplyr::rename(Richness = agg_value)

    p1 <- ggplot(plot_data_agg, aes(x = Depth, y = Richness, group = study))

    if (!is.null(ribbon)) {
      p1 <- p1 +
        geom_ribbon(aes(ymin = lower, ymax = upper, fill = study),
                    alpha = 0.18, color = NA) +
        scale_fill_manual(values = cohort_colors) +
        guides(fill = "none")
    }

    p1 <- p1 +
      geom_line(aes(color = study), linewidth = 1.2) +
      geom_point(aes(color = study), size = 1.4) +
      scale_color_manual(values = cohort_colors)

    subtitle <- sprintf(
      "%s across samples at %d depths%s; samples below a depth are excluded",
      aggregate, length(depth_grid),
      if (is.null(ribbon)) "" else
        sprintf(" (band = %g-%g quantiles)", ribbon[1], ribbon[2])
    )
  } else {
    # Plot individual samples, still on the common grid.
    p1 <- ggplot(plot_data_richness,
                 aes(x = Depth, y = Richness, group = SampleID)) +
      geom_line(aes(color = study), alpha = 0.5, linewidth = 0.6) +
      scale_color_manual(values = cohort_colors)

    subtitle <- sprintf("one line per sample at %d depths", length(depth_grid))
  }

  p1 <- p1 +
    theme_bw() +
    labs(
      x = NULL,
      y = "Observed Richness",
      title = "Alpha Rarefaction",
      subtitle = subtitle
    ) +
    theme(
      panel.grid.minor = element_blank(),
      axis.text.x = element_blank(),
      axis.ticks.x = element_blank(),
      plot.subtitle = element_text(size = 8, color = "grey30")
    )

  # ==========================================
  # BUILD PLOT 2: RETENTION
  # ==========================================
  p2 <- ggplot(plot_data_retention,
               aes(x = Depth, y = SamplesRetained, group = study)) +
    geom_step(aes(color = study), linewidth = 0.9) +
    geom_point(data = retention_marks, aes(color = study), size = 1.4) +
    scale_color_manual(values = cohort_colors) +
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

  attr(combined_plot, "rarefaction_data") <- list(
    curves     = plot_data_richness,
    agg        = plot_data_agg,
    retention  = plot_data_retention,
    depth_grid = depth_grid
  )

  return(combined_plot)
}
