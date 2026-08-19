# parse_taxonomy.R
# -----------------------------------------------------------------------------
# Turn a QIIME2 taxonomy table (as returned by qiime2R::read_qza()$data) into a
# feature x rank character matrix suitable for phyloseq::tax_table().
#
# Input is expected to have the feature ID in column 1 (usually "Feature.ID")
# and the semicolon-delimited lineage string in column 2 (usually "Taxon",
# e.g. "k__Bacteria; p__Firmicutes; ..."). Rank prefixes (k__, p__, ...) are
# stripped and empty ranks become NA.
#
# Shared across the merging/analysis notebooks -- edit here, not in a .qmd.
# -----------------------------------------------------------------------------

library(dplyr)
library(tidyr)

parse_taxonomy <- function(tax_df) {
  # tax_df expected to have columns: Feature.ID (or similar) and Taxon (string "k__; p__; ...")
  cnames <- colnames(tax_df)
  idcol <- cnames[1]    # usually "Feature.ID"
  taxcol <- cnames[2]   # usually "Taxon"
  tax_df2 <- as.data.frame(tax_df, stringsAsFactors = FALSE)
  colnames(tax_df2)[1:2] <- c("FeatureID","Taxon")
  tax_df2$Taxon <- as.character(tax_df2$Taxon)
  ranks <- c("Kingdom","Phylum","Class","Order","Family","Genus","Species")
  tax_sep <- tidyr::separate(tax_df2, Taxon, into = ranks, sep = ";\\s*", fill = "right", remove = FALSE)
  clean_rank <- function(x) {
    x <- ifelse(is.na(x) | x == "" , NA, x)
    x <- gsub("^[dkpcofgs]__|^__", "", x)   # remove prefixes like 'k__'
    trimws(x)
  }
  tax_mat <- tax_sep %>%
    dplyr::select(all_of(ranks)) %>%
    mutate_all(clean_rank) %>%
    as.matrix()
  rownames(tax_mat) <- tax_sep$FeatureID
  tax_mat
}
