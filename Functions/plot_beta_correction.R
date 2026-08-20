# plot_beta_correction.R
# -----------------------------------------------------------------------------
# Take a subset of a phyloseq object, run it through DEBIAS-M, and draw the
# beta-diversity ordination before and after correction so the two can be read
# side by side.
#
#     plot_beta_correction("agvhd == 1", "bray", filtered_ps)
#     plot_beta_correction("timepoint %in% c('pre-conditioning')", "wunifrac",
#                          filtered_ps, rare_depth = 1200)
#
# The PERMANOVA box defaults to the top-left corner of the panel. Move it, or
# take it off the panel entirely, without touching anything else:
#
#     plot_beta_correction("agvhd == 1", "bray", filtered_ps,
#                          label_corner = "br")
#     plot_beta_correction("agvhd == 1", "bray", filtered_ps,
#                          label_as_caption = TRUE)
#
# `filtering_function` is a string evaluated against the sample_data() of
# `phylo_obj`, so any expression over the metadata columns works. Samples whose
# expression evaluates to NA are dropped along with the FALSEs.
#
# Both plots print. The pair is also returned invisibly as
# list(before = , after = ), so they can be saved or combined:
#
#     p <- plot_beta_correction("agvhd == 1", "bray", filtered_ps)
#     p$before + p$after          # patchwork
#
# NOTE: every call runs the full DEBIAS-M round trip on the subset, which means
# a Python fit and a rewrite of the CSVs in Correcting/DebiasM/. Two calls in a
# row leave only the second call's intermediates on disk. That is harmless --
# the manifest guard in debiasm.R keeps each run self-consistent -- but do not
# expect the files in that folder to describe anything but the most recent call.
# -----------------------------------------------------------------------------

library(phyloseq)

if (!exists("beta_pipe")) {
  source("~/Documents/ODSi/ODSiData/Functions/beta_pipe.R")
}
if (!exists("debiasm_correct")) {
  source("~/Documents/ODSi/ODSiData/Functions/debiasm.R")
}

subset_ps_func <- function(phylo_obj,
                           filtering_function){
  
  meta_df <- as(sample_data(phylo_obj), "data.frame")
  keep_samples <- eval(parse(text = filtering_function), envir = meta_df)
  new_ps <- prune_samples(keep_samples, phylo_obj)
  new_ps <- prune_taxa(taxa_sums(new_ps) > 0, new_ps)
  
}

plot_beta_correction <- function(filtering_function,
                                 ord_method,
                                 phylo_obj,
                                 rare_depth = 900,
                                 label_corner = "tl",
                                 label_as_caption = FALSE,
                                 ...){

  # label_corner     which panel corner the PERMANOVA box is pinned to, one of
  #                  "tl" / "tr" / "bl" / "br". Both plots get the same corner
  #                  so the before/after pair stays comparable. Set to NULL to
  #                  fall back to the old data-driven box_label_percs placement,
  #                  which put the box inside the point cloud.
  # label_as_caption TRUE moves the PERMANOVA result off both panels and into
  #                  the caption under each plot.

  # overide_positions (absolute data coordinates) is still forwarded through
  # ..., but beta_pipe() lets an explicit label_corner win over it. Since
  # label_corner now defaults to "tl", a caller who passes only
  # overide_positions would otherwise have it silently ignored -- so stand the
  # default down when the corner was not asked for by name.
  if (!is.null(list(...)$overide_positions) && missing(label_corner)) {
    label_corner <- NULL
  }

  new_ps <- subset_ps_func(phylo_obj, filtering_function)

  debias_new_ps <- debiasm_correct(new_ps)

  title_str_old <- paste(paste0("Beta Diversity (",
                                ifelse(ord_method == "wunifrac",
                                       "Weighted Unifrac",
                                       toupper(ord_method)), ")"),
                         paste0("Rarefied to ", rare_depth),
                         sep = "\n") # Note: \n for newline, not /n

  title_str_new <- paste(paste0("Beta Diversity (",
                                ifelse(ord_method == "wunifrac",
                                       "Weighted Unifrac",
                                       toupper(ord_method)), ")"),
                         "Debias-M Corrected",
                         sep = "\n")

  # Pass ord_method explicitly to beta_pipe
  old_plot <- beta_pipe(new_ps,
                        rare_depth = rare_depth,
                        ord_method = ord_method,
                        norm_method = "rarefy",
                        title_str = title_str_old,
                        box_label_positions = c("l", "l"),
                        box_label_percs = c(.99, .89),
                        label_corner = label_corner,
                        label_as_caption = label_as_caption, ...)

  new_plot <- beta_pipe(debias_new_ps,
                        rare_depth = NULL,
                        ord_method = ord_method,
                        norm_method = "identity",
                        title_str = title_str_new,
                        box_label_positions = c("l", "l"),
                        box_label_percs = c(.99, .89),
                        label_corner = label_corner,
                        label_as_caption = label_as_caption, ...)

  print(old_plot)
  print(new_plot)

  invisible(list(before = old_plot, after = new_plot))
}
