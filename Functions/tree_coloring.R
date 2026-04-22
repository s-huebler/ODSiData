
library(ggtree)

# Function to get combination of all studies

get_combinations <- function(vec) {
  # We want combinations of size 2 up to the full length of the vector
  n <- length(vec)
  
  # If there are fewer than 2 elements, there are no "combinations" to return
  if (n < 2) return(character(0))
  
  # Iterate through each combination size (k) from 2 to n
  res <- lapply(2:n, function(k) {
    # combn generates a matrix where each column is a unique combination
    combs_matrix <- combn(vec, k)
    
    # Collapse each column into a single string using "_"
    apply(combs_matrix, 2, paste, collapse = "_")
  })
  
  # Flatten the list of vectors into a single character vector
  unlist(c(vec,res))
  
  
}



# Color scheme 

just_colors <- c(
  "#FFFF00",
  "#56B4E9",
  "#76EE00",
  "darkgoldenrod",
  "darkolivegreen",
  "darkslategray4",
  "black"
)

cohort_colors <- just_colors
names(cohort_colors)<- get_combinations(c("Allozithro", "Fujimoto", "Liu"))

colors_cohort <- unlist(lapply(names(cohort_colors),
                               FUN = function(x) gsub("_", " & ", x)))
names(colors_cohort)<- just_colors




# Function to color a tree

asv_mapping_func <- function(phylo_obj,
      save = TRUE,
      save_file_name = "Allo_Liu_ASVs.txt",
      id_col_name = "sample.id",
      cohort_col_name = "study",
      save_path = "/Users/sophiehuebler/Documents/ODSi/ODSiData/Merging/MergedTree/TreeColors",
      custom_color_map = data.frame(
        Cohort = c("Allo", "Fuji", "Liu", "Allo_Liu", "Allo_Fuji", "Fuji_Liu", "Allo_Fuji_Liu"),
        Color = just_colors)
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
  
  # Map overlaps and join with colors
  df_final <- df %>%
    rowwise() %>%
    mutate(
      #  sort alphabetically, and combine with "_"
      Cohort = paste(sort(cohort_cols[c_across(
        all_of(cohort_cols)) == 1]), collapse = "_")) %>%
    ungroup() %>%
    select(ASV_ID, Cohort) %>%
    left_join(custom_color_map, by = "Cohort")
  
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
    

# Function for a colored tree collapsed at whatever level
    
vizualize_collapse <- function(phylo_obj, tax_level,
                               id_col_name = "sample.id",
                               cohort_col_name = "study"){
      
    if(tax_level != "ASV"){
      ps_temp  <- suppressMessages(tax_glom(phylo_obj, taxrank = tax_level))
      
    }else{ps_temp <- phylo_obj}  
      ps_temp <- prune_samples(sample_sums(ps_temp)>0, ps_temp)
      
      
      print(ps_temp)
      
      merge_colors <- suppressMessages(asv_mapping_func(ps_temp,
          save = FALSE,
          save_file_name = "Allo_Liu_Fuji_genus.txt",
          id_col_name = id_col_name,
          cohort_col_name = cohort_col_name,
          save_path = "/Users/sophiehuebler/Documents/ODSi"))
      
      
      print(table(merge_colors$Color))
      if("Allo" %in% merge_colors$Cohort){
        merge_colors$Cohort <- gsub("Allo", "Allozithro", merge_colors$Cohort)
        merge_colors$Cohort <- gsub("Fuji", "Fujimoto", merge_colors$Cohort)
      }
      
      
      
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
        geom_tiplab(aes(label = !!ensym(tax_level), color = Color),
                    offset = 1, size = 2)+
        #scale_color_manual(values = cohort_colors) +
        scale_color_identity(guide = "legend",
                             name = "Cohort",
                             breaks = names(colors_cohort),
                             labels = unname(colors_cohort))+
        ggtitle(paste0(tax_level, " Level"))
     )
     
     plot
      
    }
    
