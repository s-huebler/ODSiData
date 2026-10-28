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
# exports) still carry the "StudyYYYY" form, and two study folders are not
# spelled like their canonical label (see study_aliases). Run those through
# study_key() before joining or plotting.
#
# Exports:
#   studies       canonical cohort names, in palette order
#   study_palette the hues, in `studies` order
#   study_colors  named vector: study -> hex
#   study_aliases folder/CHPC name -> canonical label, where the two differ
#   study_key()   normalize a label to its canonical name (drops a trailing
#                 year, then resolves aliases)
#   study_color() look up colors for a vector of labels, tolerating either form
#
# Moved here from Shared_aesthetics/Study_colors.R (2026-08-19); that folder is
# gone. Hex values and their study assignment are unchanged.
#
# 2026-10-28: added Orberg and Spindelboeck. The 7 original hues are unchanged.
# Colors are now assigned by name rather than by position, so a cohort that
# sorts into the middle of `studies` cannot shift anyone else's color.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Cohorts and colors
# -----------------------------------------------------------------------------
# One distinct color per study. The first 7 are the Okabe-Ito colorblind-safe
# hues (black reserved for "shared by all"). Okabe-Ito has no 8th non-black hue,
# so later cohorts take hues from Paul Tol's "muted" scheme, chosen to sit away
# from the Okabe-Ito set. Tol indigo "#332288" is held back for OrbergSJ.
#
# `studies` (alphabetical) is the facet / legend / dot-ring order. A new cohort
# is one line here; nothing else needs to change.
study_colors <- c(
  Artacho      = "#E69F00", # orange          (Okabe-Ito)
  DAmico       = "#56B4E9", # sky blue        (Okabe-Ito)
  Fujimoto     = "#009E73", # bluish green    (Okabe-Ito)
  Ingham       = "#F0E442", # yellow          (Okabe-Ito)
  Jarosch      = "#0072B2", # blue            (Okabe-Ito)
  Liu          = "#D55E00", # vermillion      (Okabe-Ito)
  Orberg       = "#882255", # wine            (Tol muted)
  Spindelboeck = "#999933", # olive           (Tol muted)
  Vallet       = "#CC79A7"  # reddish purple  (Okabe-Ito)
)

studies       <- names(study_colors)
study_palette <- unname(study_colors)

# Folder / CHPC names that do not reduce to the canonical label by dropping the
# year. Spindelboek2021 misspells the first author (Spindelboeck); OrbergMO2024
# is the MO cohort of Orberg et al. 2024, labelled "Orberg".
study_aliases <- c(
  Spindelboek = "Spindelboeck",
  OrbergMO    = "Orberg"
)

# -----------------------------------------------------------------------------
# Label normalization
# -----------------------------------------------------------------------------

# Drop a trailing 4-digit publication year so "Liu2017" and "Liu" (or
# "Artacho2024" and "Artacho") resolve to the same cohort, then map folder
# spellings through study_aliases ("Spindelboek2021" -> "Spindelboeck",
# "OrbergMO2024" -> "Orberg"). Anything that does
# not land on a known study is an error rather than a silent NA -- a mismatched
# key would otherwise show up as a blank facet strip or a gray point.
study_key <- function(x) {
  key <- sub("[0-9]{4}$", "", as.character(x))
  aliased <- !is.na(key) & key %in% names(study_aliases)
  key[aliased] <- unname(study_aliases[key[aliased]])
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
