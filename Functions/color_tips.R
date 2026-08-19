# color_tips.R
# -----------------------------------------------------------------------------
# Tip-coloring for the merged 7-cohort tree.
#
# Coloring logic:
#   * A tip found in EXACTLY ONE study is given that study's individual color
#     (so studies with more/fewer one-off tips are easy to spot).
#   * A tip SHARED by 2+ studies is grayscale, keyed by how many studies share
#     it: lightest gray = shared by 2, black = shared by all 7.
#
# Successor to Functions/tree_coloring.R (which handled only 3 cohorts).
# -----------------------------------------------------------------------------

library(ggtree)
library(dplyr)
library(tidyr)
library(tibble)

# `studies`, `study_colors`, study_key() and study_color() all come from here.
source("~/Documents/ODSi/ODSiData/Functions/study_colors.R")

# Grayscale ramp for shared tips, indexed by the number of studies sharing a tip
# (2 = lightest, length(studies) = black).
n_studies <- length(studies)
shared_levels <- 2:n_studies
shared_gray <- setNames(
  colorRampPalette(c("gray85", "black"))(length(shared_levels)),
  as.character(shared_levels)
)

# Combined color -> label map, used to drive the ggtree legend.
legend_map <- c(
  setNames(names(study_colors), unname(study_colors)),                 # color -> study name
  setNames(paste("Shared by", shared_levels), unname(shared_gray))     # color -> "Shared by n"
)

# -----------------------------------------------------------------------------
# Helper: given the studies present for an ASV, return its color
# -----------------------------------------------------------------------------
tip_color <- function(present_studies) {
  n <- length(present_studies)
  if (n == 0) return(NA_character_)
  # study_color() rather than study_colors[] so a phyloseq object still labelled
  # "Liu2017" resolves to the same hue as one labelled "Liu".
  if (n == 1) return(unname(study_color(present_studies)))
  unname(shared_gray[as.character(min(n, n_studies))])
}

# -----------------------------------------------------------------------------
# Map each ASV to a color and (optionally) export to iTOL format
# -----------------------------------------------------------------------------
asv_mapping_func <- function(phylo_obj,
      save = TRUE,
      save_file_name = "Merged7_ASVs.txt",
      id_col_name = "sample.id",
      cohort_col_name = "study",
      save_path = "/Users/sophiehuebler/Documents/ODSi/ODSiData/Merging/MergedTree/TreeColors"
      ){
  # Extract OTUs
  if(taxa_are_rows(phylo_obj@otu_table)){
    otus <- as.data.frame(t(phylo_obj@otu_table))
    otus[,id_col_name] <- colnames(phylo_obj@otu_table)
  } else {
    otus <- as.data.frame(phylo_obj@otu_table)
    otus[,id_col_name] <- rownames(phylo_obj@otu_table)
  }

  # Extract Metadata
  metas <- as.data.frame(unclass(phylo_obj@sam_data))
  metas[,id_col_name] <- rownames(phylo_obj@sam_data)
  metas <- metas[, c(id_col_name, cohort_col_name)]

  # Pivot and identify presence/absence
  df <- otus %>%
    left_join(metas, by = id_col_name) %>%
    pivot_longer(
      cols = -all_of(c(id_col_name, cohort_col_name)),
      names_to = "ASV_ID",
      values_to = "Count"
    ) %>%
    filter(Count > 0) %>%
    distinct(ASV_ID, !!sym(cohort_col_name)) %>%
    arrange(!!sym(cohort_col_name)) %>%
    mutate(exists = 1) %>%
    pivot_wider(
      names_from = all_of(cohort_col_name),
      values_from = exists,
      values_fill = 0
    )

  cohort_cols <- setdiff(colnames(df), "ASV_ID")

  # Determine, per ASV, which studies are present, how many, and the color
  df_final <- df %>%
    rowwise() %>%
    mutate(
      Cohort   = paste(sort(cohort_cols[c_across(all_of(cohort_cols)) == 1]),
                       collapse = "_"),
      N_Studies = sum(c_across(all_of(cohort_cols)) == 1),
      Color    = tip_color(sort(cohort_cols[c_across(all_of(cohort_cols)) == 1]))
    ) %>%
    ungroup() %>%
    select(ASV_ID, Cohort, N_Studies, Color)

  # Save to iTOL format
  if(save){
    color_mapping <- df_final %>%
      mutate(
        Type = "label",
        Style = "bold"
      )
    itol_data <- paste(color_mapping$ASV_ID, color_mapping$Type,
                       color_mapping$Color, color_mapping$Style, sep = ",")

    writeLines(
      c("TREE_COLORS", "SEPARATOR COMMA", "DATA", itol_data),
      paste0(save_path, "/", save_file_name)
    )
  }

  return(df_final)
}

# -----------------------------------------------------------------------------
# Colored tree, collapsed at whatever taxonomic level
# -----------------------------------------------------------------------------
vizualize_collapse <- function(phylo_obj, tax_level,
                               id_col_name = "sample.id",
                               cohort_col_name = "study",
                               show_labels = FALSE){

    if(tax_level != "ASV"){
      ps_temp  <- suppressMessages(tax_glom(phylo_obj, taxrank = tax_level))
    }else{ps_temp <- phylo_obj}
      ps_temp <- prune_samples(sample_sums(ps_temp)>0, ps_temp)

      print(ps_temp)

      merge_colors <- suppressMessages(asv_mapping_func(ps_temp,
          save = FALSE,
          id_col_name = id_col_name,
          cohort_col_name = cohort_col_name))

      print(table(merge_colors$Color))
      print(table(merge_colors$N_Studies))
      print(table(merge_colors$Cohort))

      tax <- tax_table(ps_temp)%>%
        as.data.frame()%>%
        rownames_to_column("ASV_ID")

      tax$ASV <- tax$ASV_ID

      tax2 <- merge_colors %>%
        left_join(tax %>%
                    select(ASV_ID, !!ensym(tax_level)),
                  by = "ASV_ID")

      print(head(tax2))

     plot <- suppressWarnings( ggtree(phy_tree(ps_temp),
             layout = "circular",
             branch.length = "none") %<+%
        tax2 +
        geom_tippoint( size = 1.6, alpha = 0.9, aes(color = Color))+
        # geom_tiplab(aes(label = !!ensym(tax_level), color = Color),
        #             offset = 1, size = 2)+
        scale_color_identity(guide = "legend",
                             name = "Cohort",
                             breaks = names(legend_map),
                             labels = unname(legend_map))+
        ggtitle(paste0(tax_level, " Level"))
     )
     
     if(show_labels){
       plot <- plot + 
          geom_tiplab(aes(label = !!ensym(tax_level), color = Color),
                      offset = 1, size = 2)
     }

     plot

    }
