# -----------------------------------------------------------------------------
# Cohorts
# -----------------------------------------------------------------------------
studies <- c(
  "Artacho2024", 
  "DAmico2019",
  "Fujimoto2024",
  "Ingham2019",
  "Jarosch2023", 
  "Liu2017",  
  "Vallet2023"
)

# -----------------------------------------------------------------------------
# Color scheme
# -----------------------------------------------------------------------------

# One distinct color per study, for tips unique to that study.
# Okabe-Ito colorblind-friendly palette (7 hues, black reserved for "all shared").
study_palette <- c(
  "#E69F00", # orange
  "#56B4E9", # sky blue
  "#009E73", # bluish green
  "#F0E442", # yellow
  "#0072B2", # blue
  "#D55E00", # vermillion
  "#CC79A7"  # reddish purple
)

study_colors <- setNames(study_palette[seq_along(studies)], studies)