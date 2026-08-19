filter_by_prevalence <- function(x, phylo_obj=ps){
  prevalence_threshold <- x * nsamples(phylo_obj)
  
  # Filter the taxa
  filtered_ps <- filter_taxa(phylo_obj, function(x) sum(x > 0) >= prevalence_threshold, prune = TRUE)
  filtered_ps <- prune_samples(sample_sums(filtered_ps) > 0, filtered_ps)
  
  filtered_ps
  
}