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
                                 ...){

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
                        box_label_percs = c(.99, .89), ...)

  new_plot <- beta_pipe(debias_new_ps,
                        rare_depth = NULL,
                        ord_method = ord_method,
                        norm_method = "identity",
                        title_str = title_str_new,
                        box_label_positions = c("l", "l"),
                        box_label_percs = c(.99, .89), ...)

  print(old_plot)
  print(new_plot)

  invisible(list(before = old_plot, after = new_plot))
}
