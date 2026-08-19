# study_colors.R
# -----------------------------------------------------------------------------
# THE single definition of the per-cohort color scheme. Nothing else in the repo
# should hard-code a study color -- source this file instead.
#
# Keys are the capitalized author surname with no year ("Artacho", "DAmico",
# ...), matching the `study` column emitted by
# Merging/Harmonization/harmonize_gvhd_metadata.R.
#
# Some older artifacts (the CHPC read-count TSVs in Merging/ReadCounts/, iTOL
# exports) still carry the "StudyYYYY" form. Run those through study_key()
# before joining or plotting.
#
# Exports:
#   studies       canonical cohort names, in palette order
#   study_palette the 7 hues, in palette order
#   study_colors  named vector: study -> hex
#   study_key()   normalize a label to its canonical name (drops a trailing year)
#   study_color() look up colors for a vector of labels, tolerating either form
#
# Moved here from Shared_aesthetics/Study_colors.R (2026-08-19); that folder is
# gone. Hex values and their study assignment are unchanged.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Cohorts
# -----------------------------------------------------------------------------
studies <- c(
  "Artacho",
  "DAmico",
  "Fujimoto",
  "Ingham",
  "Jarosch",
  "Liu",
  "Vallet"
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

# -----------------------------------------------------------------------------
# Label normalization
# -----------------------------------------------------------------------------

# Drop a trailing 4-digit publication year so "Liu2017" and "Liu" (or
# "Artacho2024" and "Artacho") resolve to the same cohort. Anything that does
# not land on a known study is an error rather than a silent NA -- a mismatched
# key would otherwise show up as a blank facet strip or a gray point.
study_key <- function(x) {
  key <- sub("[0-9]{4}$", "", as.character(x))
  bad <- setdiff(unique(key[!is.na(key)]), studies)
  if (length(bad) > 0) {
    stop("Unrecognized study label(s): ", paste(bad, collapse = ", "),
         ". Known studies: ", paste(studies, collapse = ", "), call. = FALSE)
  }
  key
}

# Colors for a vector of study labels, in the order supplied. Names on the
# result are the labels as they were passed in, so this can be handed straight
# to scale_color_manual()/scale_fill_manual() even when the data still uses the
# "StudyYYYY" form.
study_color <- function(x) {
  out <- unname(study_colors[study_key(x)])
  setNames(out, as.character(x))
}
