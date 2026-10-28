# Harmonize metadata from six GVHD studies into one sample-level data frame.
#
# Design principles:
#   * sample-id is copied exactly and must be globally unique.
#   * person is a study-prefixed anonymized identifier generated from a saved
#     crosswalk (for example, Liu_01). Original patient codes are not retained
#     in the harmonized metadata.
#   * sex uses: male, female.
#   * binary outcomes use: 1 (event occurred), 0 (did not occur); NA means
#     unknown or not applicable.
#   * dates use ISO YYYY-MM-DD after to_schema() converts them to character.
#   * time variables are days relative to transplant day 0.
#   * timepoint is a coarse ordered phase label for the sample; see
#     harmonize_timepoint() for the shared day-based rules and the per-study
#     overrides documented in each harmonize_* function.
#   * overall aGVHD is not treated as organ GVHD unless the source identifies
#     that organ's involvement.
#   * every time-to-event outcome gets the same triple: <outcome> (1/0),
#     <outcome>_day_rel_transplant, and a severity column where the source
#     supports one. The outcomes are agvhd (overall acute), gut_gvhd,
#     skin_gvhd, liver_gvhd, cgvhd (chronic), death and relapse.
#   * event day columns are masked by their own event: a day is retained only
#     when that outcome equals 1, so censoring or diagnosis times are never
#     mistaken for event times.

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(purrr)
  library(readr)
  library(stringr)
  library(tibble)
})

target_cols <- c(
  "sample-id",
  "study",
  "person",
  "timepoint",
  "sex",
  "age",
  "disease",
  "nutrition",
  "transplant_type",
  "transplant_date",
  "sample_date",
  "sample_day_rel_transplant",
  # Conditioning. The preparative regimen given before graft infusion, captured
  # on four axes: intensity (MAC/RIC/NMA), drug combination (sorted token
  # string), TBI flag, and serotherapy flag.
  "conditioning_intensity",
  "conditioning_regimen",
  "conditioning_tbi",
  "conditioning_serotherapy",
  # GVHD prophylaxis. gvhd_prophylaxis is the partner-agent category (the
  # axis most likely to act on the gut microbiome); gvhd_prophylaxis_cni is
  # the calcineurin inhibitor backbone identity.
  "gvhd_prophylaxis",
  "gvhd_prophylaxis_cni",
  # Overall acute GVHD. agvhd_grade is the composite Glucksberg/IBMTR grade.
  "agvhd",
  "agvhd_grade",
  "agvhd_day_rel_transplant",
  # Organ-specific acute GVHD. The _stage columns hold an organ stage where the
  # source reports one, and the overall aGVHD grade where it does not; see
  # gvhd_stage_note in the decision log.
  "gut_gvhd",
  "gut_gvhd_stage",
  "gut_gvhd_day_rel_transplant",
  "skin_gvhd",
  "skin_gvhd_stage",
  "skin_gvhd_day_rel_transplant",
  "liver_gvhd",
  "liver_gvhd_stage",
  "liver_gvhd_day_rel_transplant",
  # Chronic GVHD. cgvhd_stage is 1 mild / 2 moderate / 3 severe.
  "cgvhd",
  "cgvhd_stage",
  "cgvhd_day_rel_transplant",
  # Engraftment landmarks. anc_engraftment = ANC >= 500/uL sustained;
  # platelet_engraftment = platelets >= 20,000/uL untransfused.
  "anc_engraftment",
  "anc_engraftment_day_rel_transplant",
  "platelet_engraftment",
  "platelet_engraftment_day_rel_transplant",
  "death",
  "death_date",
  "cause_of_death",
  "death_day_rel_transplant",
  "relapse",
  "relapse_day_rel_transplant",
  # End of observation window. Serves as the censoring time for subjects who
  # never experience a given event. Not masked by an event (unlike the outcome
  # day columns above) because every subject has an end-observation time.
  "end_observation_reason",
  "end_observation_day_rel_transplant",
  # Secondary post-transplant complications. Binary event flags, no
  # time-to-event columns. Heavy NA expected — most are single-study.
  "myelosuppression",
  "mucositis",
  "bloodstream_infection",
  "bronchiolitis_obliterans"
)

# Every column that must contain only "1", "0" or NA.
binary_outcome_cols <- c(
  "conditioning_tbi", "conditioning_serotherapy",
  "agvhd", "gut_gvhd", "skin_gvhd", "liver_gvhd", "cgvhd",
  "anc_engraftment", "platelet_engraftment",
  "death", "relapse",
  "myelosuppression", "mucositis", "bloodstream_infection", "bronchiolitis_obliterans"
)

# Study labels are the capitalized author surname with no year, matching the
# keys in Functions/study_colors.R. Liu carried a "Liu2017" suffix until
# 2026-08-19; it was dropped so every cohort labels the same way and plots can
# look colors up directly. Edit these constants if you prefer year suffixes.
study_labels <- c(
  artacho = "Artacho",
  damico = "DAmico",
  fujimoto = "Fujimoto",
  ingham = "Ingham",
  liu = "Liu",
  vallet = "Vallet"
)

# Person prefixes are deliberately separate from study labels so Liu2017 can
# produce person IDs such as Liu_01.
person_prefixes <- c(
  artacho = "Artacho",
  damico = "DAmico",
  fujimoto = "Fujimoto",
  ingham = "Ingham",
  liu = "Liu",
  vallet = "Vallet"
)

# Coerce to character, add any missing target columns as NA, and order columns.
to_schema <- function(df) {
  df <- df %>% mutate(across(everything(), as.character))
  for (col in target_cols) {
    if (!col %in% names(df)) df[[col]] <- NA_character_
  }
  df[target_cols]
}

clean_chr <- function(x) {
  out <- str_squish(as.character(x))
  out[out %in% c("", "NA", "N/A", "NaN", "nan", "not available")] <- NA_character_
  out
}

as_num <- function(x) {
  suppressWarnings(as.numeric(clean_chr(x)))
}

# Accept either the dictionary name sample-id or the Liu example name ID.
ensure_sample_id <- function(df) {
  if ("sample-id" %in% names(df)) return(df)
  if ("ID" %in% names(df)) return(df %>% rename(`sample-id` = ID))
  stop("No sample identifier column found. Expected 'sample-id' or 'ID'.", call. = FALSE)
}

parse_date_flexible <- function(x) {
  x <- clean_chr(x)
  out <- suppressWarnings(as.Date(ymd_hms(x, quiet = TRUE, tz = "UTC")))

  idx <- is.na(out) & !is.na(x)
  if (any(idx)) out[idx] <- suppressWarnings(as.Date(ymd(x[idx], quiet = TRUE)))

  idx <- is.na(out) & !is.na(x)
  if (any(idx)) out[idx] <- suppressWarnings(as.Date(dmy(x[idx], quiet = TRUE)))

  out
}

harmonize_sex <- function(x) {
  key <- str_to_upper(clean_chr(x))
  case_when(
    is.na(key) ~ NA_character_,
    key %in% c("M", "MALE", "1") ~ "male",
    key %in% c("F", "FEMALE", "2") ~ "female",
    TRUE ~ NA_character_
  )
}

# Canonical binary coding for the event outcomes gut_gvhd, death and relapse.
# 1 = event occurred, 0 = event did not occur, NA = unknown or not applicable.
# Takes a logical (or a vector coercible to logical) so each study can express
# its own source-specific event test and get the shared coding for free.
harmonize_binary <- function(event) {
  event <- as.logical(event)
  case_when(
    is.na(event) ~ NA_character_,
    event ~ "1",
    TRUE ~ "0"
  )
}

# -----------------------------------------------------------------------------
# timepoint
#
# Coarse transplant-phase label for the sample. The shared rule bins the
# sample's day relative to transplant (day 0 = graft infusion):
#
#            day < -7   pre-conditioning
#      -7 <= day < -1   conditioning
#      -1 <= day <=  1  transplant
#       1 <  day < 14   pre-engraftment
#      14 <= day < 21   engraftment
#      21 <= day        follow-up
#
# Studies that do not supply a usable numeric day override this with a
# study-specific rule inside their harmonize_* function (Liu, Fujimoto 'pre',
# Vallet pre-transplant samples). Those overrides are documented at the point
# of use.
# -----------------------------------------------------------------------------
timepoint_levels <- c(
  "pre-conditioning",
  "conditioning",
  "transplant",
  "pre-engraftment",
  "engraftment",
  "follow-up"
)

# -----------------------------------------------------------------------------
# GVHD organ involvement
#
# Studies split into two families:
#
#   * grade-per-organ (Artacho, DAmico) supply a separate 0-4 stage for gut,
#     skin and liver. Organ involvement is stage > 0 and the stage column is a
#     true organ stage.
#   * organ-list (Fujimoto, Liu) supply one overall aGVHD grade plus a list of
#     involved organs, e.g. "Gut_Skin" or "skin, upper gut". Involvement is
#     membership in that list, and the overall grade and overall onset day are
#     applied to every organ named in the list.
#
# Studies with neither (Ingham, Vallet) leave all organ columns NA and populate
# only the overall agvhd triple.
# -----------------------------------------------------------------------------

# Regexes are matched against the lower-cased organ list. "gut" deliberately
# also matches Liu's "upper gut": upper and lower GI involvement are combined
# into the single gut_gvhd outcome.
organ_patterns <- c(gut = "gut", skin = "skin", liver = "liver")

# Returns a logical: is this organ involved? Requires the study's overall aGVHD
# event so that a documented aGVHD-negative patient becomes FALSE (a confirmed
# negative) rather than NA, while an aGVHD-positive patient with no recorded
# organ list stays NA (genuinely unknown).
organ_involved <- function(agvhd_event, organ_text, pattern) {
  agvhd_event <- as.logical(agvhd_event)
  organ <- str_to_lower(clean_chr(organ_text))
  case_when(
    !is.na(agvhd_event) & !agvhd_event ~ FALSE,
    is.na(organ) ~ NA,
    str_detect(organ, pattern) ~ TRUE,
    TRUE ~ FALSE
  )
}

# Liu records severity as free text on the IBMTR scale. "no" is an explicit
# aGVHD-negative. "yes" and "suspected" mean aGVHD occurred but was never
# assigned a grade, so they become NA rather than being forced onto the scale.
parse_liu_agvhd_grade <- function(x) {
  key <- str_to_lower(clean_chr(x))
  case_when(
    is.na(key) ~ NA_real_,
    key == "no" ~ 0,
    key == "grade i" ~ 1,
    key == "grade ii" ~ 2,
    key == "grade iii" ~ 3,
    key == "grade iv" ~ 4,
    TRUE ~ NA_real_
  )
}

# Chronic GVHD severity on a shared 1-3 scale. Liu reports Shulman-style
# "Stage 1/2/3"; Vallet reports NIH consensus "mild/moderate/severe". These are
# different instruments that happen to share a three-level ordinal structure;
# they are aligned here so cgvhd_stage is usable across studies, and the
# instrument difference is recorded in the decision log.
harmonize_cgvhd_stage <- function(x) {
  key <- str_to_lower(clean_chr(x))
  case_when(
    is.na(key) ~ NA_real_,
    key %in% c("mild", "stage 1", "1") ~ 1,
    key %in% c("moderate", "stage 2", "2") ~ 2,
    key %in% c("severe", "stage 3", "3") ~ 3,
    TRUE ~ NA_real_
  )
}

harmonize_timepoint <- function(day) {
  day <- as.numeric(day)
  case_when(
    is.na(day) ~ NA_character_,
    day < -7 ~ "pre-conditioning",
    day < -1 ~ "conditioning",
    day <= 1 ~ "transplant",
    day < 14 ~ "pre-engraftment",
    day < 21 ~ "engraftment",
    TRUE ~ "follow-up"
  )
}

# Shared detailed disease vocabulary. Unknown source labels are retained in
# lower case and are surfaced by the QA table noncanonical_disease_values.
harmonize_disease <- function(x, donor = FALSE) {
  raw <- clean_chr(x)
  key <- str_to_upper(raw)
  donor <- replace(as.logical(donor), is.na(donor), FALSE)

  case_when(
    donor ~ "none",
    is.na(raw) ~ NA_character_,

    (str_detect(key, "MDS\\s*/\\s*(MPN|MPS)") |
      str_detect(key, "MYELODYSPLASTIC.*MYELOPROLIFERATIVE")) ~
      "myelodysplastic/myeloproliferative neoplasm",
    str_detect(key, "BIPHENOTYPIC") ~ "biphenotypic acute leukemia",
    str_detect(key, "DUAL HEMOPATHY") ~ "dual hematologic malignancy",
    str_detect(key, "MYELOFIBROSIS") ~ "myelofibrosis",

    key == "JMML" ~ "juvenile myelomonocytic leukemia",
    key == "CMML" | str_detect(key, "CHRONIC MYELOMONOCYTIC") ~
      "chronic myelomonocytic leukemia",
    key == "TCL" ~ "T-cell leukemia/lymphoma",

    key == "SAL" ~ "secondary acute leukemia",
    key == "OAL" ~ "other acute leukemia",
    key == "AL" ~ "acute leukemia, not otherwise specified",

    str_detect(key, "\\bAMML\\b|\\bAML\\b|\\bANLL\\b|ACUTE MYELOID|ACUTE MYELOMONOCYTIC") ~
      "acute myeloid leukemia",
    str_detect(key, "\\bC?ALL\\b|ACUTE LYMPHOBLASTIC") ~
      "acute lymphoblastic leukemia",

    key == "CML" | str_detect(key, "CHRONIC MYELOID") ~
      "chronic myeloid leukemia",
    key == "CLL" | str_detect(key, "CHRONIC LYMPHOCYTIC") ~
      "chronic lymphocytic leukemia",

    key == "RCC" | str_detect(key, "REFRACTORY CYTOPENIA") ~
      "refractory cytopenia of childhood",
    key == "MDS" | str_detect(key, "MYELODYSPLASTIC") ~
      "myelodysplastic syndrome",
    key %in% c("MPS", "MPN") | str_detect(key, "MYELOPROLIFERATIVE") ~
      "myeloproliferative neoplasm",

    key == "NHL" | str_detect(key, "NON[- ]HODGKIN") ~
      "non-Hodgkin lymphoma",
    key == "HD" | str_detect(key, "HODGKIN") ~ "Hodgkin lymphoma",
    key == "LYMPHOMA" ~ "lymphoma, not otherwise specified",

    key == "MM" | str_detect(key, "MULTIPLE MYELOMA") ~ "multiple myeloma",
    key %in% c("AA", "BMA") | str_detect(key, "APLASTIC ANEMIA|BONE MARROW APLASIA") ~
      "aplastic anemia",

    key == "CGD" | str_detect(key, "CHRONIC GRANULOMATOUS") ~
      "chronic granulomatous disease",
    key == "SCID" | str_detect(key, "SCID|ABSENCE OF T AND B CELLS") ~
      "severe combined immunodeficiency",
    key == "HLH" | str_detect(key, "LYMPHOHISTIOCYT|ERYTHROPHAGOCYT") ~
      "hemophagocytic lymphohistiocytosis",
    key == "TM" | str_detect(key, "THALASSEMIA") ~ "thalassemia major",

    key %in% c("OTHER DISEASE", "OTHER MALIGNANCIES") ~
      "other hematologic disease",
    TRUE ~ str_to_lower(raw)
  )
}

# Canonical vocabulary for conditioning intensity.
conditioning_intensity_levels <- c("MAC", "RIC", "NMA")

# Canonical vocabularies for the two GVHD prophylaxis columns.
gvhd_prophylaxis_levels <- c("cni-mtx", "cni-mmf", "cni-steroid", "cni-alone", "other")
gvhd_prophylaxis_cni_levels <- c("cyclosporine", "tacrolimus")

# -----------------------------------------------------------------------------
# nutrition
#
# Type of nutritional support received. Source encodings handled:
#   Artacho  "Yes" / "No" in Parenteral.Nutrition → parenteral / enteral
#   DAmico   free-text regimen string containing "EN" and/or "PN" tokens
#            → enteral / parenteral / mixed
#   Vallet   French "parenterale" → parenteral; "enteral" and "oral" pass through
# -----------------------------------------------------------------------------
nutrition_levels <- c("parenteral", "enteral", "mixed", "oral")

harmonize_nutrition <- function(x) {
  key <- str_to_lower(clean_chr(x))
  case_when(
    is.na(key) ~ NA_character_,
    key %in% c("parenteral", "parenterale") ~ "parenteral",
    key == "enteral" ~ "enteral",
    key == "mixed"   ~ "mixed",
    key == "oral"    ~ "oral",
    TRUE ~ NA_character_
  )
}

# -----------------------------------------------------------------------------
# transplant_type
#
# Stem cell source / transplant type. Per-study codes handled:
#   Artacho  numeric 1/2/3 in Transplant.source
#   DAmico   "BM" / "PBSC" in Stem_cell_source
#   Fujimoto "BM" / "PB" / "CB" in Graft_Type
#   Ingham   "BM" / "PBSC" / "UC" / "BM_UC" in transplant_type (source column)
#   Liu      "pbsc" / "marrow" / "cord+cord" in donor_source; donors → "none"
#   Vallet   "PBC" / "cord blood" / "bone marrow" in csh_type
# -----------------------------------------------------------------------------
transplant_type_levels <- c(
  "none",
  "bone marrow",
  "umbilical cord blood",
  "peripheral blood stem cells",
  "bone marrow and umbilical cord blood"
)

harmonize_transplant_type <- function(x) {
  key <- str_to_lower(clean_chr(x))
  case_when(
    is.na(key)                                       ~ NA_character_,
    key == "none"                                    ~ "none",
    key == "bone marrow"                             ~ "bone marrow",
    key == "umbilical cord blood"                    ~ "umbilical cord blood",
    key == "peripheral blood stem cells"             ~ "peripheral blood stem cells",
    key == "bone marrow and umbilical cord blood"    ~ "bone marrow and umbilical cord blood",
    TRUE ~ NA_character_
  )
}

harmonize_liu_cause_of_death <- function(x) {
  key <- str_to_lower(clean_chr(x))
  case_when(
    is.na(key) ~ NA_character_,
    key == "relapse" ~ "relapse",
    key %in% c("relapse/resipatory", "relapse/respiratory") ~
      "relapse; respiratory failure",
    key == "sepsis" ~ "sepsis",
    key == "sepsis/ards/gvhd" ~
      "sepsis; acute respiratory distress syndrome; graft-versus-host disease",
    key == "agvhd/infection" ~
      "acute graft-versus-host disease; infection",
    key == "respiratory failure" ~ "respiratory failure",
    key == "ards/respiratory failure" ~
      "acute respiratory distress syndrome; respiratory failure",
    key == "septic shock" ~ "septic shock",
    TRUE ~ str_replace_all(key, "/", "; ")
  )
}

make_person_crosswalk <- function(x, study, prefix, source_column) {
  keys <- clean_chr(x)
  keys <- keys[!is.na(keys)]
  keys <- str_sort(unique(keys), numeric = TRUE)
  width <- max(2L, nchar(length(keys)))
  fmt <- paste0(prefix, "_%0", width, "d")

  tibble(
    study = study,
    source_column = source_column,
    original_person = keys,
    person = sprintf(fmt, seq_along(keys))
  )
}

lookup_person <- function(x, crosswalk, study) {
  rows <- crosswalk$study == study
  keys <- crosswalk$original_person[rows]
  values <- crosswalk$person[rows]
  unname(values[match(clean_chr(x), keys)])
}

assert_sample_ids_preserved <- function(input, output, study) {
  expected <- as.character(input[["sample-id"]])
  observed <- output[["sample-id"]]
  if (!identical(expected, observed)) {
    stop("sample-id changed during harmonization for study: ", study, call. = FALSE)
  }
}

harmonize_artacho <- function(df, person_crosswalk) {
  df <- ensure_sample_id(df)
  transplant_date <- parse_date_flexible(df[["date.of.transplant"]])
  sample_day <- as_num(df[["Timepoint"]])

  # Grade-per-organ study: gut, skin and liver each carry their own 0-4 organ
  # stage, and GVHD_grade is the overall composite. No aGVHD onset date or day
  # is recorded anywhere in the source, so every *_day_rel_transplant column in
  # the acute GVHD block stays NA. Chronic GVHD is not recorded at all.
  overall_grade <- as_num(df[["GVHD_grade"]])
  gut_stage <- as_num(df[["gut_gvhd_grade"]])
  skin_stage <- as_num(df[["skin_gvhd_grade"]])
  liver_stage <- as_num(df[["liver_GVHD_grade"]])
  # Conditioning: no conditioning regimen, intensity or TBI column in the source.
  # All four conditioning_* columns stay NA via to_schema().
  # NOTE: Myelosuppression (0/98, 1/74) is a toxicity outcome observed during
  # the transplant course — it is NOT a description of the preparative regimen.
  # Myelosuppression can follow MAC, RIC or NMA conditioning. Do not map it to
  # any conditioning column; it is mapped to the myelosuppression outcome below.

  # Secondary outcomes: Myelosuppression 0/1 and Mucositis Yes/No.
  # bloodstream_infection and bronchiolitis_obliterans not recorded → NA.
  myelo_artacho <- harmonize_binary(as.integer(df[["Myelosuppression"]]) == 1L)
  mucositis_artacho <- harmonize_binary(
    str_to_lower(clean_chr(df[["Mucositis"]])) == "yes"
  )

  # gvhd_prophylaxis / gvhd_prophylaxis_cni: no prophylaxis column in the
  # source at all → both stay NA via to_schema().

  # Parenteral.Nutrition is Yes/No with no NAs; Yes → parenteral, No → enteral.
  pn_flag <- str_to_lower(clean_chr(df[["Parenteral.Nutrition"]]))
  nutrition_artacho <- harmonize_nutrition(case_when(
    pn_flag == "yes" ~ "parenteral",
    pn_flag == "no"  ~ "enteral",
    TRUE             ~ NA_character_
  ))
  # Transplant.source is numeric: 1 = bone marrow, 2 = umbilical cord blood,
  # 3 = peripheral blood stem cells. No NAs.
  tx_src <- as_num(df[["Transplant.source"]])
  transplant_type_artacho <- harmonize_transplant_type(case_when(
    tx_src == 1 ~ "bone marrow",
    tx_src == 2 ~ "umbilical cord blood",
    tx_src == 3 ~ "peripheral blood stem cells",
    TRUE        ~ NA_character_
  ))

  out <- df %>%
    transmute(
      `sample-id` = as.character(.data[["sample-id"]]),
      study = study_labels[["artacho"]],
      person = lookup_person(.data[["Patient"]], person_crosswalk, study_labels[["artacho"]]),
      # Timepoint is an exact day relative to transplant, so the shared rule
      # applies. Timepoint_Class (pre/post) is not used: the numeric day is
      # more precise and splits 'post' into pre-engraftment and engraftment.
      timepoint = harmonize_timepoint(sample_day),
      sex = harmonize_sex(.data[["Gender"]]),
      age = as_num(.data[["Age"]]),
      disease = harmonize_disease(.data[["Disease"]]),
      nutrition = nutrition_artacho,
      transplant_type = transplant_type_artacho,
      transplant_date = transplant_date,
      sample_date = transplant_date + as.integer(sample_day),
      sample_day_rel_transplant = sample_day,
      agvhd = harmonize_binary(overall_grade > 0),
      agvhd_grade = overall_grade,
      gut_gvhd = harmonize_binary(gut_stage > 0),
      gut_gvhd_stage = gut_stage,
      skin_gvhd = harmonize_binary(skin_stage > 0),
      skin_gvhd_stage = skin_stage,
      liver_gvhd = harmonize_binary(liver_stage > 0),
      liver_gvhd_stage = liver_stage,
      myelosuppression = myelo_artacho,
      mucositis = mucositis_artacho
    ) %>%
    to_schema()

  assert_sample_ids_preserved(df, out, study_labels[["artacho"]])
  out
}

harmonize_damico <- function(df, person_crosswalk) {
  df <- ensure_sample_id(df)
  sample_day <- as_num(df[["Timepoint"]])
  outcome_100 <- str_to_lower(clean_chr(df[["Outcome_at_100"]]))

  # Grade-per-organ study, but unlike Artacho it records a single aGVHD onset
  # day (gvhd_day = day of first clinical aGVHD diagnosis, any organ) and no
  # overall grade. gvhd_day is therefore applied to every organ the patient has
  # a non-zero stage for: a patient with both gut and skin involvement gets the
  # same onset day on both outcomes. That is the source's resolution -- it does
  # not distinguish which organ presented first. agvhd_grade stays NA because
  # no composite grade exists. Chronic GVHD is not recorded.
  gut_stage <- as_num(df[["gut_gvhd_grade"]])
  skin_stage <- as_num(df[["Skin_gvhd_grade"]])
  liver_stage <- as_num(df[["liver_gvhd_grade"]])
  # Conditioning. Conditioning_regimen is the preparative regimen (see below).
  # conditioning_intensity = MAC for all 104 samples: the data dictionary labels
  # the column "Myeloablative conditioning regimen" per Supplementary Table 2.
  # The five samples with "EDX, FLUDARA, TBI" (Cy+Flu+TBI) are a paediatric
  # cohort — no TBI dose is recorded so MAC cannot be independently verified,
  # but we accept the manuscript's assertion. conditioning_serotherapy → NA.
  dm_cond_src <- str_to_upper(str_squish(clean_chr(df[["Conditioning_regimen"]])))
  dm_regimen <- case_when(
    is.na(dm_cond_src)                    ~ NA_character_,
    dm_cond_src == "BU, TT, FLUDARA"     ~ "bu/flu/thio",
    dm_cond_src == "BU, EDX, L-PAM"      ~ "bu/cy/mel",
    dm_cond_src == "BU, TT, EDX"         ~ "bu/cy/thio",
    dm_cond_src == "TREO, TT, FLUDARA"   ~ "flu/thio/treo",
    # TBI is stripped from the regimen string into conditioning_tbi.
    dm_cond_src == "EDX, FLUDARA, TBI"   ~ "cy/flu",
    dm_cond_src == "TREO, TT, EDX"       ~ "cy/thio/treo",
    TRUE                                  ~ NA_character_
  )
  dm_tbi <- harmonize_binary(str_detect(dm_cond_src, "\\bTBI\\b"))

  # gvhd_prophylaxis / gvhd_prophylaxis_cni: not recorded in this study.
  # Conditioning_regimen (EDX = cyclophosphamide, BU, FLUDARA, etc.) is the
  # PREPARATIVE regimen, not post-transplant GVHD prophylaxis — do not map it.
  # Both columns stay NA via to_schema().

  # Secondary outcomes.
  # Mucositis_grade I/II/III → 1; "/" (ungraded, n=5) → 0; NA (n=5) → 0.
  # An ungraded DAmico patient is treated as mucositis-free rather than unknown
  # because the source manuscript documents mucositis only as a graded adverse
  # event; "/" denotes "not assessed at a grade", which in this cohort is
  # indistinguishable from no mucositis.
  dm_mucositis_grade <- clean_chr(df[["Mucositis_grade"]])
  dm_mucositis <- case_when(
    dm_mucositis_grade %in% c("I", "II", "III") ~ "1",
    TRUE                                         ~ "0"
  )
  # BSI: free-text organisms + event day (e.g. "S.aureus (+7)"); any non-missing
  # value → 1, NA → 0. NA genuinely means no BSI — all events were in the PN
  # group and the EN group had zero (confirmed by manuscript Table 2).
  # myelosuppression and bronchiolitis_obliterans not recorded → NA.
  dm_bsi <- harmonize_binary(!is.na(df[["BSI"]]))

  # Suffixed: DAmico has a raw column named gvhd_day, which transmute() would
  # otherwise resolve in preference to this cleaned local.
  gvhd_day_num <- as_num(df[["gvhd_day"]])

  # NA only when all three organ stages are missing.
  max_stage <- suppressWarnings(pmax(gut_stage, skin_stage, liver_stage, na.rm = TRUE))
  max_stage[is.infinite(max_stage)] <- NA_real_
  # Suffixed to avoid shadowing the source columns PMN_day / PLT_over_20000_day
  # if those names were ever used bare inside transmute().
  pmn_day_num <- as_num(df[["PMN_day"]])
  plt_day_num <- as_num(df[["PLT_over_20000_day"]])
  # Stem_cell_source: BM = bone marrow, PBSC = peripheral blood stem cells.
  scs <- str_to_upper(clean_chr(df[["Stem_cell_source"]]))
  transplant_type_damico <- harmonize_transplant_type(case_when(
    scs == "BM"   ~ "bone marrow",
    scs == "PBSC" ~ "peripheral blood stem cells",
    TRUE          ~ NA_character_
  ))

  # Nutritional_Regimen is a free-text string encoding EN and/or PN windows,
  # e.g. "EN (+0/+12)", "PN (+0/+16)", "EN (+1/+10); PN (+10/+13)".
  reg <- clean_chr(df[["Nutritional_Regimen"]])
  nutrition_damico <- harmonize_nutrition(case_when(
    is.na(reg)                                    ~ NA_character_,
    str_detect(reg, "EN") & str_detect(reg, "PN") ~ "mixed",
    str_detect(reg, "EN")                         ~ "enteral",
    str_detect(reg, "PN")                         ~ "parenteral",
    TRUE                                          ~ NA_character_
  ))

  out <- df %>%
    transmute(
      `sample-id` = as.character(.data[["sample-id"]]),
      study = study_labels[["damico"]],
      person = lookup_person(.data[["Patient"]], person_crosswalk, study_labels[["damico"]]),
      # Timepoint is days relative to transplant; shared rule applies.
      timepoint = harmonize_timepoint(sample_day),
      sex = harmonize_sex(.data[["Sex"]]),
      age = as_num(.data[["Age"]]),
      disease = harmonize_disease(.data[["Diagnosis"]]),
      nutrition = nutrition_damico,
      transplant_type = transplant_type_damico,
      sample_day_rel_transplant = sample_day,
      conditioning_intensity = "MAC",
      conditioning_regimen = dm_regimen,
      conditioning_tbi = dm_tbi,
      agvhd = harmonize_binary(max_stage > 0),
      agvhd_day_rel_transplant = if_else(max_stage > 0, gvhd_day_num, NA_real_),
      gut_gvhd = harmonize_binary(gut_stage > 0),
      gut_gvhd_stage = gut_stage,
      gut_gvhd_day_rel_transplant = if_else(gut_stage > 0, gvhd_day_num, NA_real_),
      skin_gvhd = harmonize_binary(skin_stage > 0),
      skin_gvhd_stage = skin_stage,
      skin_gvhd_day_rel_transplant = if_else(skin_stage > 0, gvhd_day_num, NA_real_),
      liver_gvhd = harmonize_binary(liver_stage > 0),
      liver_gvhd_stage = liver_stage,
      liver_gvhd_day_rel_transplant = if_else(liver_stage > 0, gvhd_day_num, NA_real_),
      # PMN_day is present for all 20 patients, so anc_engraftment is always 1.
      # PLT_over_20000_day is absent for 1 patient (E10, alive at day +100);
      # that patient gets platelet_engraftment = 0. A missing PLT day cannot be
      # distinguished from a patient who failed to achieve platelet recovery —
      # see decision log for the caveat.
      anc_engraftment = harmonize_binary(!is.na(pmn_day_num)),
      anc_engraftment_day_rel_transplant = if_else(!is.na(pmn_day_num), pmn_day_num, NA_real_),
      platelet_engraftment = harmonize_binary(!is.na(plt_day_num)),
      platelet_engraftment_day_rel_transplant = if_else(!is.na(plt_day_num), plt_day_num, NA_real_),
      # This endpoint is limited to vital status through day +100.
      death = harmonize_binary(case_when(
        outcome_100 == "d" ~ TRUE,
        outcome_100 == "a" ~ FALSE,
        TRUE ~ NA
      )),
      # Follow-up was administratively censored at day +100 for all subjects;
      # no later outcome date is recorded in the source.
      end_observation_reason = "administrative",
      end_observation_day_rel_transplant = 100,
      mucositis = dm_mucositis,
      bloodstream_infection = dm_bsi
    ) %>%
    to_schema()

  assert_sample_ids_preserved(df, out, study_labels[["damico"]])
  out
}

harmonize_fujimoto <- function(df, person_crosswalk) {
  df <- ensure_sample_id(df)
  timepoint <- str_to_lower(clean_chr(df[["Timepoint"]]))
  # Graft_Type: BM = bone marrow, PB = peripheral blood stem cells,
  # CB = umbilical cord blood. No NAs.
  gt <- str_to_upper(clean_chr(df[["Graft_Type"]]))
  transplant_type_fujimoto <- harmonize_transplant_type(case_when(
    gt == "BM" ~ "bone marrow",
    gt == "PB" ~ "peripheral blood stem cells",
    gt == "CB" ~ "umbilical cord blood",
    TRUE       ~ NA_character_
  ))

  # Conditioning intensity and TBI map directly from source columns.
  # conditioning_regimen and conditioning_serotherapy not recorded → NA.
  # Secondary outcomes (myelosuppression, mucositis, bloodstream_infection,
  # bronchiolitis_obliterans): none recorded in this study → all NA via to_schema().
  intensity_fujimoto <- case_when(
    is.na(clean_chr(df[["Conditioning_Intensity"]])) ~ NA_character_,
    str_to_upper(clean_chr(df[["Conditioning_Intensity"]])) == "MAC" ~ "MAC",
    str_to_upper(clean_chr(df[["Conditioning_Intensity"]])) == "RIC" ~ "RIC",
    str_to_upper(clean_chr(df[["Conditioning_Intensity"]])) == "NMA" ~ "NMA",
    TRUE ~ NA_character_
  )
  # Suffixed to avoid shadowing source column Conditioning_TBI inside transmute().
  tbi_fujimoto <- harmonize_binary(
    str_to_lower(clean_chr(df[["Conditioning_TBI"]])) == "yes"
  )

  # gvhd_prophylaxis / gvhd_prophylaxis_cni: not recorded in this study.
  # AGVHD_Treatment (mPSL, ATG, MSC) is rescue therapy given after aGVHD
  # was diagnosed — it is NOT prophylaxis. Both columns stay NA via to_schema().

  # Organ-list study. AGVHD is the overall event, AGVHD_Severity the overall
  # Glucksberg grade at diagnosis, AGVHD_TTE the overall onset day, and
  # AGVHD_Organ the list of organs involved at diagnosis ("Gut", "Skin",
  # "Gut_Skin", "Gut_Liver_Skin"). The overall grade and onset day are applied
  # to every organ named in the list, so a Gut_Skin patient carries the same
  # stage and day on both gut and skin. Chronic GVHD is not recorded.
  agvhd_event <- as_num(df[["AGVHD"]]) == 1
  organ <- clean_chr(df[["AGVHD_Organ"]])
  overall_grade <- as_num(df[["AGVHD_Severity"]])
  overall_day <- as_num(df[["AGVHD_TTE"]])

  gut_event <- organ_involved(agvhd_event, organ, organ_patterns[["gut"]])
  skin_event <- organ_involved(agvhd_event, organ, organ_patterns[["skin"]])
  liver_event <- organ_involved(agvhd_event, organ, organ_patterns[["liver"]])

  # 'pre' has no numeric day in the source; every other label is dayN.
  sample_day <- if_else(
    str_detect(timepoint, "^day-?[0-9]+$"),
    as_num(str_remove(timepoint, "^day")),
    NA_real_
  )

  # Study-specific override: the 'pre' label is the preconditioning baseline
  # sample (Baseline1), so it is assigned pre-conditioning even though no
  # numeric day exists. All other labels go through the shared day rule.
  sample_timepoint <- if_else(
    timepoint == "pre",
    "pre-conditioning",
    harmonize_timepoint(sample_day)
  )

  out <- df %>%
    transmute(
      `sample-id` = as.character(.data[["sample-id"]]),
      study = study_labels[["fujimoto"]],
      person = lookup_person(.data[["Patient"]], person_crosswalk, study_labels[["fujimoto"]]),
      timepoint = sample_timepoint,
      sex = harmonize_sex(.data[["Sex"]]),
      age = as_num(.data[["Age"]]),
      disease = harmonize_disease(.data[["Disease"]]),
      transplant_type = transplant_type_fujimoto,
      sample_day_rel_transplant = sample_day,
      conditioning_intensity = intensity_fujimoto,
      conditioning_tbi = tbi_fujimoto,
      agvhd = harmonize_binary(agvhd_event),
      agvhd_grade = overall_grade,
      agvhd_day_rel_transplant = overall_day,
      gut_gvhd = harmonize_binary(gut_event),
      gut_gvhd_stage = if_else(gut_event, overall_grade, NA_real_),
      gut_gvhd_day_rel_transplant = if_else(gut_event, overall_day, NA_real_),
      skin_gvhd = harmonize_binary(skin_event),
      skin_gvhd_stage = if_else(skin_event, overall_grade, NA_real_),
      skin_gvhd_day_rel_transplant = if_else(skin_event, overall_day, NA_real_),
      liver_gvhd = harmonize_binary(liver_event),
      liver_gvhd_stage = if_else(liver_event, overall_grade, NA_real_),
      liver_gvhd_day_rel_transplant = if_else(liver_event, overall_day, NA_real_)
    ) %>%
    to_schema()

  assert_sample_ids_preserved(df, out, study_labels[["fujimoto"]])
  out
}

harmonize_ingham <- function(df, person_crosswalk) {
  df <- ensure_sample_id(df)
  death_event <- as_num(df[["death"]])
  relapse_event <- as_num(df[["relapse"]])
  death_code <- clean_chr(df[["cause_of_death"]])
  sample_day <- as_num(df[["timepoint"]])

  # Overall-only study: aGVHD is recorded as an event, a Glucksberg grade and a
  # calendar onset date, with no organ breakdown anywhere in the source, so all
  # gut/skin/liver columns stay NA. agvhd_date is converted to a day relative to
  # transplant. cgvhd is present but constant 0 in this cohort, giving a genuine
  # all-negative chronic GVHD column with no stage or onset day.
  # Secondary outcomes (myelosuppression, mucositis, bloodstream_infection,
  # bronchiolitis_obliterans): none recorded in this study → all NA via to_schema().
  #
  # NOTE ON NAMING: these locals are suffixed because transmute() resolves bare
  # names against the source data frame first. Ingham has raw columns literally
  # named transplant_date and agvhd_date, so an unsuffixed local would be
  # silently shadowed by the unparsed character column.
  transplant_date_parsed <- parse_date_flexible(df[["transplant_date"]])
  agvhd_event <- as_num(df[["agvhd"]]) == 1
  agvhd_date_parsed <- parse_date_flexible(df[["agvhd_date"]])
  cgvhd_event <- as_num(df[["cgvhd"]]) == 1
  # Suffixed: Ingham has a raw column named censor; the bare name inside
  # transmute() would resolve to the unparsed source column.
  censor_day_num <- as_num(df[["censor"]])
  # Engraphment (source spelling) is a 0/1 flag; no day column exists in
  # Ingham, so anc_engraftment_day_rel_transplant stays NA via to_schema().
  engraftment_num <- as_num(df[["Engraphment"]])
  # Conditioning. Myeloabl is constant 1 for all 96 documented rows → MAC.
  # The one metadata-less row (Myeloabl = NA) stays NA.
  intensity_ingham <- if_else(!is.na(df[["Myeloabl"]]), "MAC", NA_character_)

  # Drug-presence flags for conditioning_regimen assembly.
  # X233Bu: 1 and 2 both mean busulfan was given; value 2 is undocumented
  # but treated as positive per spec.
  # Thiotepa is constant 0 in this cohort, kept so the branch is uniform.
  ig_bu   <- !is.na(df[["X233Bu"]])                & df[["X233Bu"]] %in% c(1, 2)
  ig_cy   <- !is.na(df[["X270Cyclo"]])             & df[["X270Cyclo"]]  == 1
  ig_flu  <- !is.na(df[["X284.2Fludarab"]])        & df[["X284.2Fludarab"]] == 1
  ig_mel  <- !is.na(df[["Total.dose.melphalan..mg."]]) &
               as.numeric(df[["Total.dose.melphalan..mg."]]) > 0
  ig_vp16 <- !is.na(df[["Total.dose.VP16..mg."]]) &
               as.numeric(df[["Total.dose.VP16..mg."]]) > 0
  ig_thio <- !is.na(df[["Total.dose.thiotepa..mg."]]) &
               as.numeric(df[["Total.dose.thiotepa..mg."]]) > 0
  # Metadata-less row: all indicators are FALSE → empty token set → NA.
  ig_regimen <- mapply(function(b, c, f, m, v, t) {
    tokens <- c(if (b) "bu", if (c) "cy", if (f) "flu",
                if (m) "mel", if (v) "vp16", if (t) "thio")
    if (length(tokens) == 0L) NA_character_ else paste(sort(tokens), collapse = "/")
  }, ig_bu, ig_cy, ig_flu, ig_mel, ig_vp16, ig_thio,
  SIMPLIFY = TRUE, USE.NAMES = FALSE)

  # TBI: source TBI is NA for 28 samples where Irrad = 0 (confirmed: every
  # TBI-missing row has Irrad = 0). Recover those to TBI = 0.
  # Suffixed to avoid shadowing source column TBI inside transmute().
  tbi_raw_ingham  <- as.integer(df[["TBI"]])
  irrad_ingham    <- as.integer(df[["Irrad"]])
  tbi_ingham <- case_when(
    !is.na(tbi_raw_ingham)                           ~ tbi_raw_ingham,
    !is.na(irrad_ingham) & irrad_ingham == 0L        ~ 0L,
    TRUE                                             ~ NA_integer_
  )

  # Serotherapy: ATG (X197ATGmm) or antibody-based agent (X10Ab).
  # The metadata-less row has both NA → serotherapy NA.
  sero_ingham <- case_when(
    is.na(df[["X197ATGmm"]]) & is.na(df[["X10Ab"]]) ~ NA,
    df[["X197ATGmm"]] == 1 | df[["X10Ab"]] == 1     ~ TRUE,
    TRUE                                             ~ FALSE
  )

  # GVHD prophylaxis. Source column gvhd_prophylaxis has three string levels,
  # all cyclosporine-based. X197ATGmm (ATG in conditioning, n=72) and
  # Was.graft.manipulated.for.GVHD.prophylaxis (constant 0) are intentionally
  # excluded — ATG is conditioning, not prophylaxis; see decision log.
  # Suffixed because transmute() would shadow a bare local named gvhd_prophylaxis
  # with the source column of the same name.
  src_proph_ingham <- str_to_lower(clean_chr(df[["gvhd_prophylaxis"]]))
  proph_val_ingham <- case_when(
    is.na(src_proph_ingham)                          ~ NA_character_,
    src_proph_ingham == "cyclosporine a + methotrexate" ~ "cni-mtx",
    src_proph_ingham == "cyclosporine + corticosteroids" ~ "cni-steroid",
    # The EBMT registry code 1 ("Cyclosporine A") is a distinct category that
    # records the backbone without any partner agent. Taken at face value as
    # monotherapy; see decision log.
    src_proph_ingham == "cyclosporine a"             ~ "cni-alone",
    TRUE                                             ~ NA_character_
  )
  proph_cni_val_ingham <- if_else(!is.na(proph_val_ingham), "cyclosporine", NA_character_)

  # Suffixed: Ingham has a raw column literally named transplant_type; the bare
  # name inside transmute() would resolve to the source column.
  tt_ingham <- str_to_upper(clean_chr(df[["transplant_type"]]))
  transplant_type_ingham <- harmonize_transplant_type(case_when(
    tt_ingham == "BM"    ~ "bone marrow",
    tt_ingham == "PBSC"  ~ "peripheral blood stem cells",
    tt_ingham == "UC"    ~ "umbilical cord blood",
    tt_ingham == "BM_UC" ~ "bone marrow and umbilical cord blood",
    TRUE                 ~ NA_character_
  ))

  out <- df %>%
    transmute(
      `sample-id` = as.character(.data[["sample-id"]]),
      study = study_labels[["ingham"]],
      person = lookup_person(.data[["patient"]], person_crosswalk, study_labels[["ingham"]]),
      # Source 'timepoint' is days relative to transplant; shared rule applies.
      timepoint = harmonize_timepoint(sample_day),
      sex = harmonize_sex(.data[["sex"]]),
      age = as_num(.data[["age"]]),
      disease = harmonize_disease(.data[["disease"]]),
      transplant_type = transplant_type_ingham,
      transplant_date = transplant_date_parsed,
      sample_date = parse_date_flexible(.data[["sampling_date"]]),
      sample_day_rel_transplant = sample_day,
      conditioning_intensity = intensity_ingham,
      conditioning_regimen = ig_regimen,
      conditioning_tbi = harmonize_binary(tbi_ingham == 1L),
      conditioning_serotherapy = harmonize_binary(sero_ingham),
      gvhd_prophylaxis = proph_val_ingham,
      gvhd_prophylaxis_cni = proph_cni_val_ingham,
      agvhd = harmonize_binary(agvhd_event),
      agvhd_grade = as_num(.data[["agvhd_grade"]]),
      agvhd_day_rel_transplant = if_else(
        agvhd_event & !is.na(agvhd_date_parsed) & !is.na(transplant_date_parsed),
        as.numeric(agvhd_date_parsed - transplant_date_parsed),
        NA_real_
      ),
      cgvhd = harmonize_binary(cgvhd_event),
      anc_engraftment = harmonize_binary(engraftment_num == 1),
      death = harmonize_binary(death_event == 1),
      # No calendar death date is supplied. tte_death is masked by the event so
      # censoring times are never mistaken for death times.
      cause_of_death = if_else(
        death_event == 1 & !is.na(death_code),
        paste0("EBMT_code_", death_code),
        NA_character_
      ),
      death_day_rel_transplant = if_else(
        death_event == 1,
        as_num(.data[["tte_death"]]),
        NA_real_
      ),
      relapse = harmonize_binary(relapse_event == 1),
      # tte_relapse contains event or censoring time, so retain it only for
      # relapse events.
      relapse_day_rel_transplant = if_else(
        relapse_event == 1,
        as_num(.data[["tte_relapse"]]),
        NA_real_
      ),
      # censor is the planned end-of-follow-up day (relative to transplant).
      # If the patient died, the last observable day is tte_death (earlier than
      # censor). One patient has death=NA and censor=NA; both new columns stay NA.
      end_observation_reason = case_when(
        death_event == 1 ~ "death",
        !is.na(censor_day_num) ~ "EOS",
        TRUE ~ NA_character_
      ),
      end_observation_day_rel_transplant = case_when(
        death_event == 1 ~ as_num(.data[["tte_death"]]),
        !is.na(censor_day_num) ~ censor_day_num,
        TRUE ~ NA_real_
      )
    ) %>%
    to_schema()

  assert_sample_ids_preserved(df, out, study_labels[["ingham"]])
  out
}

# Liu BSI classification lookup maps.
# Each distinct source string that appears in the real data is listed here with
# its manual classification (1 = bloodstream infection, 0 = not a BSI).
# The classification was read from the raw free text and confirmed by the
# analyst before being hard-coded. See the decision log for reasoning on each
# uncertain call. NA source values map to "0" in the derivation code below.
# A QA table (liu_bsi_crosswalk) and a test (liu_bsi_unrecognized is empty)
# enforce that every future distinct value is present in one of these maps.
liu_bsi_col1_map <- c(
  # infection_duringafter_transplant
  "adenovirus in urine; VZV/shingles"                                              = "0",
  "bacteremia, C difficile, cholecystitis"                                          = "1",
  "bacteremia, EBV viremia, C difficile"                                            = "1",
  "bacteremia: pseudomonas, E coli, VRE"                                            = "1",
  "bipolaris mold, neutropenic fever"                                                = "0",  # mold without bloodstream context
  "C difficile"                                                                      = "0",
  "C difficile recurrence"                                                           = "0",
  "C difficile, mold in sinus"                                                       = "0",
  "C difficile, pneunomia, VRE, proteus mirabilis UTI"                              = "0",
  "C difficile, rhinovirus"                                                          = "0",
  "C difficile, sepsis, Strep pneumonia, VRE UTI"                                   = "1",  # "sepsis" → BSI
  "C difficile, shingles"                                                            = "0",
  "chronic hepatitis C on INF; thigh cellulitis 8/2013"                             = "0",
  "Citrobacter UTI, otitis external, entercoccus UTI, aspergillus sinus infection 8/2014" = "0",
  "CMV colitis"                                                                      = "0",
  "CMV pneumonitis, fungal sinusitis, cystitis,"                                    = "0",
  "CMV viremia"                                                                      = "0",
  "CMV viremia, peritonitis, septic shock"                                           = "1",  # "septic shock" → BSI
  "CMV viremia, rhinovirus, influenza, candida glabrata"                             = "0",  # Candida without bloodstream site
  "CMV, CNS, rhinovirus"                                                             = "0",  # CNS = CNS infection, not CoNS bacteremia
  "diverticulitis, neutropenic fever, oral candida"                                  = "0",
  "Enterococcus UTI"                                                                 = "0",
  "facial cellulitis"                                                                = "0",
  "human metapneumovirus, PCP pneumonia, oral candida, CMV pneumonia, rhinovirus"   = "0",
  "influenza"                                                                        = "0",
  "knee 9/2013"                                                                      = "0",  # septic joint; no bacteremia named
  "neck abscess, shingles, dental caries"                                            = "0",
  "neutropenic fever 7/2013; rhinovirus 8/2013; E coli bacteremia 12/2013"          = "1",
  "neutropenic fever, C difficile colitis, pneumatosis coli, CMV colitis"           = "0",
  "neutropenic fever, septic knee, CNS bacteremia, cellulitis"                      = "1",
  "oral candida, pneumonia"                                                          = "0",
  "oral candida, rhinovirus"                                                         = "0",
  "oral candida, VRE"                                                                = "0",  # VRE without bloodstream site
  "Pneumonia, infected wound, CMV viremia, human metapneumovirus, C difficile"      = "0",
  "pneumonia, oral candida, CNS, rhinovirus"                                         = "0",
  "pneumonia, strep viridans bacteremia"                                             = "1",
  "Rhinovirus"                                                                       = "0",
  "RSV, folliculitis"                                                                = "0",
  "RSV, fungal pneumonia, neutropenic fever"                                         = "0",
  "sepsis, VRE bacteremia"                                                           = "1",
  "synovitis, influenza A"                                                           = "0",
  "UTI"                                                                              = "0",
  "VRE, C difficile, CMV viremia, BK virus, adenovirus"                             = "0",  # VRE without bloodstream site
  "VRE, fungal pneumonia, C difficile, bowel pneumatosis, CMV viremia"              = "0",
  "pneumonia"                                                                        = "0"
)

liu_bsi_col2_map <- c(
  # infection_details
  "appendicitis"                                  = "0",
  "aspergillus pneumonia/sinusitis"               = "0",
  "bacteremia"                                    = "1",
  "C difficile"                                   = "0",
  "C difficile, recurrence"                       = "0",
  "cellulitis, bacteremia"                        = "1",
  "colitis, bacteremia"                           = "1",
  "diarrhea, fever"                               = "0",
  "ear abscesses"                                 = "0",
  "EBV"                                           = "0",
  "Fungal pneumonia, parainfluenza virus"         = "0",
  "hepatosplenic candidiasis"                     = "1",  # disseminated Candida; invasive fungal equivalent
  "hepatitis C"                                   = "0",
  "herpes"                                        = "0",
  "HSV"                                           = "0",
  "HSV oral, tinea cruris"                        = "0",
  "Leuconostoc bacteremia, sinusitis"             = "1",
  "neutropenic fever"                             = "0",
  "neutropenic fever, Abiotopia/strep viridans"   = "0",  # no explicit bloodstream site
  "oral hsv; hepatitis B"                         = "0",
  "perifacial abscess"                            = "0",
  "pneumonia"                                     = "0",
  "port infection"                                = "0",  # local vs CLABSI ambiguous; classified non-BSI
  "propionibacterium acnes"                       = "0",  # no bloodstream context
  "unclear"                                       = "0",
  "UTI"                                           = "0",
  "VRE bacteremia; cellulitis; Klebsiella UTI"    = "1"
)

harmonize_liu <- function(df, person_crosswalk) {
  df <- ensure_sample_id(df)
  donor <- str_to_lower(clean_chr(df[["donor_or_patient"]])) == "donor"
  deceased <- as_num(df[["deceased"]])
  relapsed <- str_to_lower(clean_chr(df[["relapsed"]]))

  # Organ-list study. agvhd_organ is a comma-separated free-text list
  # ("gut", "skin, gut", "skin, upper gut", "liver, skin", "None documented").
  # Upper and lower GI involvement are combined into the single gut_gvhd
  # outcome, so "upper gut" counts as gut. The overall severity and onset day
  # are applied to every organ named in the list, exactly as for Fujimoto.
  # Organs outside the gut/skin/liver triple (Liu also records "oral") are
  # carried by agvhd but have no target column of their own.
  organ <- clean_chr(df[["agvhd_organ"]])
  agvhd_event <- if_else(donor, NA, as_num(df[["agvhd"]]) == 1)
  overall_grade <- parse_liu_agvhd_grade(df[["agvhd_severity"]])
  overall_day <- as_num(df[["time_to_agvhd"]])

  gut_event <- organ_involved(agvhd_event, organ, organ_patterns[["gut"]])
  skin_event <- organ_involved(agvhd_event, organ, organ_patterns[["skin"]])
  liver_event <- organ_involved(agvhd_event, organ, organ_patterns[["liver"]])

  gut_gvhd <- harmonize_binary(gut_event)

  # Chronic GVHD. cgvhd_severity is staged for recipients who developed cGVHD
  # and blank for those who did not, so a blank recipient row is a confirmed
  # negative; donors stay NA. time_to_cgvhd is NOT used: it duplicates
  # time_to_agvhd in 78 of 79 rows and its missingness does not track
  # cgvhd_severity, so it is not a usable chronic onset time. See the decision
  # log entry for the evidence.
  cgvhd_stage <- harmonize_cgvhd_stage(df[["cgvhd_severity"]])
  cgvhd_event <- case_when(
    donor ~ NA,
    !is.na(cgvhd_stage) ~ TRUE,
    TRUE ~ FALSE
  )

  # GVHD prophylaxis. Five one-hot columns (cyclosporine, tacrolimus,
  # methotrexate, mmf, sirolimus) are constant "no" for donors (NA stored) and
  # yes/no for recipients. Sirolimus is constant "no" in this cohort.
  # All five names exist as source columns, so locals are computed here and given
  # distinct names to avoid transmute() shadowing them.
  # Data dictionary note cites Table 1 as tac/MTX=21 and tac/MMF=13, but the
  # patient-level one-hot columns give tac/MTX=13 and tac/MMF=21. Patient-level
  # data is authoritative; the Table 1 counts appear to be a transposition error.
  cyc_yes  <- !donor & str_to_lower(clean_chr(df[["cyclosporine"]])) == "yes"
  tac_yes  <- !donor & str_to_lower(clean_chr(df[["tacrolimus"]]))   == "yes"
  mtx_yes  <- !donor & str_to_lower(clean_chr(df[["methotrexate"]])) == "yes"
  mmf_yes  <- !donor & str_to_lower(clean_chr(df[["mmf"]]))          == "yes"
  liu_prophylaxis <- case_when(
    donor    ~ NA_character_,
    mtx_yes  ~ "cni-mtx",
    mmf_yes  ~ "cni-mmf",
    TRUE     ~ NA_character_
  )
  liu_prophylaxis_cni <- case_when(
    donor   ~ NA_character_,
    cyc_yes ~ "cyclosporine",
    tac_yes ~ "tacrolimus",
    TRUE    ~ NA_character_
  )

  # donor_source: pbsc / marrow / cord+cord for recipients; donors → "none".
  # 22 donor rows have NA donor_source; donor flag handles them.
  ds <- str_to_lower(clean_chr(df[["donor_source"]]))
  transplant_type_liu <- harmonize_transplant_type(case_when(
    donor            ~ "none",
    ds == "pbsc"      ~ "peripheral blood stem cells",
    ds == "marrow"    ~ "bone marrow",
    ds == "cord+cord" ~ "umbilical cord blood",
    TRUE              ~ NA_character_
  ))

  # Engraftment. Source uses single-t spelling: anc_engrafment /
  # platelet_engrafment and days_to_anc_engrafment / days_to_platelet_engrafment.
  # Both "no" patients (QOHVF823, XI91FUC4) have NA days for both outcomes.
  anc_eng_raw <- tolower(clean_chr(df[["anc_engrafment"]]))
  plt_eng_raw <- tolower(clean_chr(df[["platelet_engrafment"]]))
  anc_eng_flag  <- if_else(donor, NA, anc_eng_raw == "yes")
  plt_eng_flag  <- if_else(donor, NA, plt_eng_raw == "yes")
  anc_eng_day   <- as_num(df[["days_to_anc_engrafment"]])
  plt_eng_day   <- as_num(df[["days_to_platelet_engrafment"]])

  # End of observation. right_censor_time is the last observed day for all
  # subjects; for deceased recipients it equals time_to_death in 16/18 cases.
  # The two exceptions: NYYC95BI has right_censor_time=365 > time_to_death=345
  # (apparent recording error — death day used); CCHWVERY has deceased=1 but
  # time_to_death=NA (right_censor_time=100 used, reason still death).
  rct_num <- as_num(df[["right_censor_time"]])
  ttd_num <- as_num(df[["time_to_death"]])
  end_obs_day_liu <- case_when(
    donor ~ NA_real_,
    deceased == 1 & !is.na(ttd_num) ~ ttd_num,
    deceased == 1 ~ rct_num,
    TRUE ~ rct_num
  )
  end_obs_reason_liu <- case_when(
    donor ~ NA_character_,
    deceased == 1 ~ "death",
    TRUE ~ "EOS"
  )

  # BSI derivation. Two free-text columns are looked up against literal crosswalk
  # maps defined at module level (liu_bsi_col1_map / liu_bsi_col2_map). NA source
  # → "0" (6 recipients with both fields empty are treated as no documented BSI;
  # "not documented" and "not assessed" are indistinguishable in this source).
  # Donor rows → NA. A recipient is BSI=1 if EITHER column maps to 1.
  col1_val <- liu_bsi_col1_map[clean_chr(df[["infection_duringafter_transplant"]])]
  col2_val <- liu_bsi_col2_map[clean_chr(df[["infection_details"]])]
  col1_bsi <- if_else(is.na(df[["infection_duringafter_transplant"]]), "0", unname(col1_val))
  col2_bsi <- if_else(is.na(df[["infection_details"]]),                "0", unname(col2_val))
  liu_bsi <- case_when(
    donor                           ~ NA_character_,
    col1_bsi == "1" | col2_bsi == "1" ~ "1",
    TRUE                            ~ "0"
  )
  # myelosuppression, mucositis, bronchiolitis_obliterans not recorded → NA.

  # Conditioning. GOTCHA: `conditioning_intensity` and `chemotherapy_regimen`
  # are source column names — locals use suffixed names to avoid transmute()
  # shadowing them.
  # Intensity: High→MAC, Intermediate→RIC, Low→NMA. The Low group's regimens
  # (Flu/TBI and Cy/ATG) are consistent with NMA despite the paper labelling
  # them "RIC" parenthetically.
  intensity_liu <- case_when(
    donor ~ NA_character_,
    str_detect(str_to_lower(clean_chr(df[["conditioning_intensity"]])), "high")         ~ "MAC",
    str_detect(str_to_lower(clean_chr(df[["conditioning_intensity"]])), "intermediate") ~ "RIC",
    str_detect(str_to_lower(clean_chr(df[["conditioning_intensity"]])), "low")          ~ "NMA",
    TRUE ~ NA_character_
  )
  # Regimen: strip dose annotations in parentheses, split on "/", separate
  # TBI and ATG into their own binary columns, map remaining tokens to
  # canonical names, sort alphabetically.
  liu_token_map <- c(Flu = "flu", Mel = "mel", Bu = "bu", Cy = "cy",
                     Thio = "thio", Treo = "treo")
  chem_raw_liu   <- clean_chr(df[["chemotherapy_regimen"]])
  chem_clean_liu <- str_remove_all(chem_raw_liu, "\\s*\\([^)]+\\)")
  liu_tbi  <- harmonize_binary(if_else(donor, NA, str_detect(str_to_upper(chem_clean_liu), "\\bTBI\\b")))
  liu_sero <- harmonize_binary(if_else(donor, NA, str_detect(str_to_upper(chem_clean_liu), "\\bATG\\b")))
  liu_regimen <- vapply(seq_along(chem_clean_liu), function(i) {
    if (is.na(chem_clean_liu[i]) || donor[i]) return(NA_character_)
    tokens <- str_split(chem_clean_liu[i], "/")[[1]]
    tokens <- tokens[!str_to_upper(str_squish(tokens)) %in% c("TBI", "ATG")]
    mapped <- liu_token_map[str_squish(tokens)]
    mapped <- mapped[!is.na(mapped)]
    if (length(mapped) == 0L) return(NA_character_)
    paste(sort(unname(mapped)), collapse = "/")
  }, character(1))

  out <- df %>%
    transmute(
      `sample-id` = as.character(.data[["sample-id"]]),
      study = study_labels[["liu"]],
      person = lookup_person(.data[["host_subject_id"]], person_crosswalk, study_labels[["liu"]]),
      # Study-specific override: Liu2017 sampled every subject once, before the
      # start of conditioning, and supplies no sample day or sample date. Every
      # row is therefore pre-conditioning by design rather than by day rule.
      timepoint = "pre-conditioning",
      sex = harmonize_sex(.data[["sex"]]),
      age = if_else(donor, NA_real_, as_num(.data[["age"]])),
      disease = harmonize_disease(.data[["disease"]], donor = donor),
      transplant_type = transplant_type_liu,
      conditioning_intensity = intensity_liu,
      conditioning_regimen = liu_regimen,
      conditioning_tbi = liu_tbi,
      conditioning_serotherapy = liu_sero,
      bloodstream_infection = liu_bsi,
      gvhd_prophylaxis = liu_prophylaxis,
      gvhd_prophylaxis_cni = liu_prophylaxis_cni,
      agvhd = harmonize_binary(agvhd_event),
      agvhd_grade = overall_grade,
      agvhd_day_rel_transplant = overall_day,
      gut_gvhd = gut_gvhd,
      gut_gvhd_stage = if_else(gut_event, overall_grade, NA_real_),
      gut_gvhd_day_rel_transplant = if_else(gut_event, overall_day, NA_real_),
      skin_gvhd = harmonize_binary(skin_event),
      skin_gvhd_stage = if_else(skin_event, overall_grade, NA_real_),
      skin_gvhd_day_rel_transplant = if_else(skin_event, overall_day, NA_real_),
      liver_gvhd = harmonize_binary(liver_event),
      liver_gvhd_stage = if_else(liver_event, overall_grade, NA_real_),
      liver_gvhd_day_rel_transplant = if_else(liver_event, overall_day, NA_real_),
      cgvhd = harmonize_binary(cgvhd_event),
      cgvhd_stage = cgvhd_stage,
      anc_engraftment = harmonize_binary(anc_eng_flag),
      anc_engraftment_day_rel_transplant = if_else(
        !is.na(anc_eng_flag) & anc_eng_flag, anc_eng_day, NA_real_
      ),
      platelet_engraftment = harmonize_binary(plt_eng_flag),
      platelet_engraftment_day_rel_transplant = if_else(
        !is.na(plt_eng_flag) & plt_eng_flag, plt_eng_day, NA_real_
      ),
      death = harmonize_binary(case_when(
        donor ~ NA,
        deceased == 1 ~ TRUE,
        deceased == 0 ~ FALSE,
        TRUE ~ NA
      )),
      cause_of_death = if_else(
        !donor & deceased == 1,
        harmonize_liu_cause_of_death(.data[["etiology_of_death"]]),
        NA_character_
      ),
      death_day_rel_transplant = if_else(
        !donor & deceased == 1,
        as_num(.data[["time_to_death"]]),
        NA_real_
      ),
      relapse = harmonize_binary(case_when(
        donor ~ NA,
        relapsed == "yes" ~ TRUE,
        relapsed == "no" ~ FALSE,
        TRUE ~ NA
      )),
      relapse_day_rel_transplant = if_else(
        !donor & relapsed == "yes",
        as_num(.data[["days_at_relapse"]]),
        NA_real_
      ),
      end_observation_reason = end_obs_reason_liu,
      end_observation_day_rel_transplant = end_obs_day_liu
    ) %>%
    to_schema()

  assert_sample_ids_preserved(df, out, study_labels[["liu"]])
  out
}

harmonize_vallet <- function(df, person_crosswalk) {
  df <- ensure_sample_id(df)
  transplant_date <- parse_date_flexible(df[["dat.hsct"]])
  sample_date <- parse_date_flexible(df[["sample.time"]])
  conditioning_date <- parse_date_flexible(df[["dat.cond"]])
  sample_day <- as_num(df[["j.hsct"]])
  death_raw <- clean_chr(df[["dat.death"]])
  relapse_raw <- clean_chr(df[["dat.relapse"]])
  death_event <- !is.na(death_raw)
  # Suffixed: Vallet has a raw column literally named 'nutrition'; the bare name
  # inside transmute() would resolve to the source column instead of this local.
  nutrition_vallet <- harmonize_nutrition(df[["nutrition"]])
  # csh_type: PBC = peripheral blood stem cells, cord blood = umbilical cord
  # blood, bone marrow = bone marrow. No NAs.
  csh <- str_to_lower(clean_chr(df[["csh_type"]]))
  transplant_type_vallet <- harmonize_transplant_type(case_when(
    csh == "pbc"         ~ "peripheral blood stem cells",
    csh == "cord blood"  ~ "umbilical cord blood",
    csh == "bone marrow" ~ "bone marrow",
    TRUE                 ~ NA_character_
  ))
  death_date <- parse_date_flexible(death_raw)
  relapse_date <- parse_date_flexible(relapse_raw)
  relapse_event <- as_num(df[["relapse01"]])

  # GVHD prophylaxis. gvhd_proph_type has three string levels; all recorded
  # regimens use cyclosporine as the CNI backbone. "Other" leaves the CNI unknown.
  # The source spells the drug "ciclosporin" in the MTX value and "cyclosporin"
  # in the MMF value — both map to cyclosporine in gvhd_prophylaxis_cni.
  proph_src_vallet <- str_to_lower(clean_chr(df[["gvhd_proph_type"]]))
  proph_val_vallet <- case_when(
    is.na(proph_src_vallet)              ~ NA_character_,
    proph_src_vallet == "ciclosporin-mtx" ~ "cni-mtx",
    proph_src_vallet == "cyclosporin-mmf" ~ "cni-mmf",
    proph_src_vallet == "other"          ~ "other",
    TRUE                                 ~ NA_character_
  )
  proph_cni_val_vallet <- case_when(
    proph_val_vallet %in% c("cni-mtx", "cni-mmf") ~ "cyclosporine",
    TRUE                                           ~ NA_character_
  )

  # Overall-only study: aGVHD is recorded as an event, a Glucksberg/Seattle
  # grade and a calendar onset date, with no organ breakdown, so all
  # gut/skin/liver columns stay NA.
  #
  # agvhd is a three-level competing-risk code: 0 = no aGVHD, 1 = aGVHD,
  # 2 = competing event (died before developing aGVHD). Code 2 becomes 0 for
  # the binary outcome -- those patients never developed aGVHD -- but their
  # follow-up was truncated by death, so they are informatively censored. Fit a
  # competing-risks model from the raw three-level code rather than from this
  # column if that distinction matters. Three patients have agvhd = 1 with no
  # recorded date or grade; they keep agvhd = 1 with NA grade and NA day.
  agvhd_code <- as_num(df[["agvhd"]])
  agvhd_date <- parse_date_flexible(df[["dat.agvhd"]])

  # Chronic GVHD: dat_cgvhd and cgvhd_grad are present together or absent
  # together, so a missing date is a confirmed negative rather than unknown.
  cgvhd_date <- parse_date_flexible(df[["dat_cgvhd"]])
  cgvhd_event <- !is.na(cgvhd_date)

  # End of observation: earliest of last-follow-up, end-of-study, and death.
  # dat.lfu is present for all 50 patients; dat.endstudy is patient-specific
  # and NA for 32/50 (those patients' lfu serves as the censoring date, reason
  # EOS). No patient has dat.lfu < dat.endstudy, so "lost to follow up" never
  # fires in this cohort but the logic is preserved for correctness.
  lfu_date <- parse_date_flexible(df[["dat.lfu"]])
  eos_date <- parse_date_flexible(df[["dat.endstudy"]])
  lfu_day_vallet <- if_else(
    !is.na(lfu_date) & !is.na(transplant_date),
    as.numeric(lfu_date - transplant_date), NA_real_
  )
  eos_day_vallet <- if_else(
    !is.na(eos_date) & !is.na(transplant_date),
    as.numeric(eos_date - transplant_date), NA_real_
  )
  death_day_vallet <- if_else(
    death_event & !is.na(death_date) & !is.na(transplant_date),
    as.numeric(death_date - transplant_date), NA_real_
  )
  end_obs_day_vallet <- pmin(lfu_day_vallet, eos_day_vallet, death_day_vallet,
                              na.rm = TRUE)
  end_obs_reason_vallet <- case_when(
    !is.na(death_day_vallet) &
      death_day_vallet <= lfu_day_vallet &
      (is.na(eos_day_vallet) | death_day_vallet <= eos_day_vallet) ~ "death",
    !is.na(lfu_day_vallet) & !is.na(eos_day_vallet) &
      lfu_day_vallet < eos_day_vallet ~ "lost to follow up",
    TRUE ~ "EOS"
  )

  # Study-specific override for the two pre-transplant phases. Vallet records
  # the actual conditioning start date (dat.cond), so pre-conditioning vs
  # conditioning is decided by whether the sample was drawn before conditioning
  # began rather than by the shared -7 day cutoff. Samples from day -1 onward
  # fall back to the shared day rule on j.hsct.
  sample_timepoint <- case_when(
    is.na(sample_day) ~ NA_character_,
    sample_day >= -1 ~ harmonize_timepoint(sample_day),
    is.na(sample_date) | is.na(conditioning_date) ~ harmonize_timepoint(sample_day),
    sample_date < conditioning_date ~ "pre-conditioning",
    TRUE ~ "conditioning"
  )

  # Conditioning. GOTCHA: `conditioning` is a source column name — use
  # src_cond_vallet to avoid transmute() shadowing it.
  # Two levels in this cohort: myeloablative → MAC, non myeloablative → NMA.
  # No RIC patients present. Regimen, TBI and serotherapy columns are not
  # available in the source and stay NA via to_schema().

  # Secondary outcomes.
  # bos: "yes" → 1; NA → 0 (data dictionary explicitly states missing = no BOS;
  # manuscript Table 1 confirms exactly 2 cases). myelosuppression, mucositis
  # and bloodstream_infection not recorded → NA via to_schema().
  bos_vallet <- case_when(
    str_to_lower(clean_chr(df[["bos"]])) == "yes" ~ "1",
    TRUE                                           ~ "0"
  )
  src_cond_vallet <- str_to_lower(clean_chr(df[["conditioning"]]))
  intensity_vallet <- case_when(
    is.na(src_cond_vallet)                  ~ NA_character_,
    src_cond_vallet == "myeloablative"      ~ "MAC",
    src_cond_vallet == "non myeloablative"  ~ "NMA",
    TRUE                                    ~ NA_character_
  )

  out <- df %>%
    transmute(
      `sample-id` = as.character(.data[["sample-id"]]),
      study = study_labels[["vallet"]],
      person = lookup_person(.data[["allozithro_id"]], person_crosswalk, study_labels[["vallet"]]),
      timepoint = sample_timepoint,
      sex = harmonize_sex(.data[["gender"]]),
      age = as_num(.data[["age"]]),
      disease = harmonize_disease(.data[["diagnosis2"]]),
      nutrition = nutrition_vallet,
      transplant_type = transplant_type_vallet,
      transplant_date = transplant_date,
      sample_date = sample_date,
      sample_day_rel_transplant = sample_day,
      conditioning_intensity = intensity_vallet,
      gvhd_prophylaxis = proph_val_vallet,
      gvhd_prophylaxis_cni = proph_cni_val_vallet,
      agvhd = harmonize_binary(agvhd_code == 1),
      agvhd_grade = as_num(.data[["grad.agvhd"]]),
      agvhd_day_rel_transplant = if_else(
        agvhd_code == 1 & !is.na(agvhd_date) & !is.na(transplant_date),
        as.numeric(agvhd_date - transplant_date),
        NA_real_
      ),
      cgvhd = harmonize_binary(cgvhd_event),
      cgvhd_stage = harmonize_cgvhd_stage(.data[["cgvhd_grad"]]),
      cgvhd_day_rel_transplant = if_else(
        cgvhd_event & !is.na(transplant_date),
        as.numeric(cgvhd_date - transplant_date),
        NA_real_
      ),
      death = harmonize_binary(death_event),
      death_date = death_date,
      death_day_rel_transplant = if_else(
        death_event & !is.na(death_date) & !is.na(transplant_date),
        as.numeric(death_date - transplant_date),
        NA_real_
      ),
      relapse = harmonize_binary(relapse_event == 1),
      relapse_day_rel_transplant = if_else(
        relapse_event == 1 & !is.na(relapse_date),
        as.numeric(relapse_date - transplant_date),
        NA_real_
      ),
      end_observation_reason = end_obs_reason_vallet,
      end_observation_day_rel_transplant = end_obs_day_vallet,
      bronchiolitis_obliterans = bos_vallet
    ) %>%
    to_schema()

  assert_sample_ids_preserved(df, out, study_labels[["vallet"]])
  out
}

canonical_disease_values <- c(
  "none",
  "acute lymphoblastic leukemia",
  "acute myeloid leukemia",
  "acute leukemia, not otherwise specified",
  "secondary acute leukemia",
  "other acute leukemia",
  "biphenotypic acute leukemia",
  "chronic myeloid leukemia",
  "chronic lymphocytic leukemia",
  "juvenile myelomonocytic leukemia",
  "chronic myelomonocytic leukemia",
  "T-cell leukemia/lymphoma",
  "myelodysplastic syndrome",
  "myelodysplastic/myeloproliferative neoplasm",
  "myeloproliferative neoplasm",
  "myelofibrosis",
  "non-Hodgkin lymphoma",
  "Hodgkin lymphoma",
  "lymphoma, not otherwise specified",
  "multiple myeloma",
  "aplastic anemia",
  "refractory cytopenia of childhood",
  "chronic granulomatous disease",
  "severe combined immunodeficiency",
  "hemophagocytic lymphohistiocytosis",
  "thalassemia major",
  "dual hematologic malignancy",
  "other hematologic disease"
)

build_qa <- function(metadata, raw = list()) {
  duplicate_sample_ids <- metadata %>%
    filter(!is.na(.data[["sample-id"]])) %>%
    count(`sample-id`, name = "n") %>%
    filter(n > 1)

  missing_sample_ids <- metadata %>%
    filter(is.na(.data[["sample-id"]]) | .data[["sample-id"]] == "")

  missing_person_samples <- metadata %>%
    filter(is.na(person) | person == "") %>%
    select(`sample-id`, study, person)

  person_level_fields <- c(
    "sex", "age", "disease", "nutrition", "transplant_type", "transplant_date",
    "conditioning_intensity", "conditioning_regimen",
    "conditioning_tbi", "conditioning_serotherapy",
    "gvhd_prophylaxis", "gvhd_prophylaxis_cni",
    "agvhd", "agvhd_grade", "agvhd_day_rel_transplant",
    "gut_gvhd", "gut_gvhd_stage", "gut_gvhd_day_rel_transplant",
    "skin_gvhd", "skin_gvhd_stage", "skin_gvhd_day_rel_transplant",
    "liver_gvhd", "liver_gvhd_stage", "liver_gvhd_day_rel_transplant",
    "cgvhd", "cgvhd_stage", "cgvhd_day_rel_transplant",
    "anc_engraftment", "anc_engraftment_day_rel_transplant",
    "platelet_engraftment", "platelet_engraftment_day_rel_transplant",
    "death", "death_date", "cause_of_death", "death_day_rel_transplant",
    "relapse", "relapse_day_rel_transplant",
    "end_observation_reason", "end_observation_day_rel_transplant",
    "myelosuppression", "mucositis", "bloodstream_infection", "bronchiolitis_obliterans"
  )

  person_conflicts <- map_dfr(person_level_fields, function(field) {
    metadata %>%
      filter(!is.na(person), !is.na(.data[[field]])) %>%
      group_by(study, person) %>%
      summarise(
        n_values = n_distinct(.data[[field]]),
        values = paste(sort(unique(.data[[field]])), collapse = " | "),
        .groups = "drop"
      ) %>%
      filter(n_values > 1) %>%
      mutate(column = field, .before = n_values)
  })

  # (b) Non-canonical intensity values — empty when correct.
  noncanonical_conditioning_intensity_values <- metadata %>%
    distinct(study, conditioning_intensity) %>%
    filter(!is.na(conditioning_intensity),
           !conditioning_intensity %in% conditioning_intensity_levels) %>%
    arrange(study, conditioning_intensity)

  # (c) Every distinct conditioning_regimen string by study, so shared strings
  # are visible by scanning for the same regimen in multiple rows.
  conditioning_regimen_by_study <- metadata %>%
    filter(!is.na(conditioning_regimen)) %>%
    count(conditioning_regimen, study, name = "n_samples") %>%
    arrange(conditioning_regimen, study)

  # (d) Regimen strings must not contain "tbi" or "atg" as tokens — those
  # belong in conditioning_tbi / conditioning_serotherapy.
  conditioning_regimen_forbidden_tokens <- metadata %>%
    filter(!is.na(conditioning_regimen),
           str_detect(conditioning_regimen, "\\btbi\\b|\\batg\\b")) %>%
    select(`sample-id`, study, conditioning_regimen)

  # (a) Coverage for all four new columns.
  conditioning_coverage <- metadata %>%
    group_by(study) %>%
    summarise(
      n_samples      = n(),
      n_intensity    = sum(!is.na(conditioning_intensity)),
      n_regimen      = sum(!is.na(conditioning_regimen)),
      n_tbi          = sum(!is.na(conditioning_tbi)),
      n_serotherapy  = sum(!is.na(conditioning_serotherapy)),
      .groups = "drop"
    )

  # (e) Ingham dose-vs-intensity cross-check. Flags the three patients (P23,
  # P25, P27) with 200 cGy single-fraction TBI — below the 500 cGy threshold
  # for myeloablative single-fraction TBI — who are nonetheless Myeloabl = 1.
  # Requires raw Ingham data; returns an empty tibble if not supplied.
  ingham_mac_tbi_dose_check <- if (!is.null(raw[["ingham"]])) {
    src <- raw[["ingham"]]
    src %>%
      filter(!is.na(.data[["Myeloabl"]]),
             !is.na(.data[["TBI"]]),
             as.integer(.data[["TBI"]]) == 1L) %>%
      distinct(.data[["patient"]], .keep_all = TRUE) %>%
      transmute(
        patient         = .data[["patient"]],
        tbi_dose_cgy    = as.numeric(.data[["Total.dose.of.TBI.in.cGy"]]),
        fractionated    = as.integer(.data[["FracTBI"]]),
        dose_per_frac   = as.numeric(.data[["Dose.frac"]]),
        drug_cy         = as.integer(.data[["X270Cyclo"]]),
        drug_bu         = as.integer(.data[["X233Bu"]]),
        drug_flu        = as.integer(.data[["X284.2Fludarab"]]),
        sub_mac_tbi_flag = tbi_dose_cgy < 500 & fractionated == 0L
      ) %>%
      arrange(tbi_dose_cgy)
  } else {
    tibble(
      patient = character(), tbi_dose_cgy = numeric(),
      fractionated = integer(), dose_per_frac = numeric(),
      drug_cy = integer(), drug_bu = integer(), drug_flu = integer(),
      sub_mac_tbi_flag = logical()
    )
  }

  noncanonical_gvhd_prophylaxis_values <- metadata %>%
    distinct(study, gvhd_prophylaxis) %>%
    filter(!is.na(gvhd_prophylaxis),
           !gvhd_prophylaxis %in% gvhd_prophylaxis_levels) %>%
    arrange(study, gvhd_prophylaxis)

  noncanonical_gvhd_prophylaxis_cni_values <- metadata %>%
    distinct(study, gvhd_prophylaxis_cni) %>%
    filter(!is.na(gvhd_prophylaxis_cni),
           !gvhd_prophylaxis_cni %in% gvhd_prophylaxis_cni_levels) %>%
    arrange(study, gvhd_prophylaxis_cni)

  gvhd_prophylaxis_coverage <- metadata %>%
    group_by(study) %>%
    summarise(
      n_samples = n(),
      n_prophylaxis_present = sum(!is.na(gvhd_prophylaxis)),
      n_prophylaxis_missing = sum(is.na(gvhd_prophylaxis)),
      n_cni_present = sum(!is.na(gvhd_prophylaxis_cni)),
      n_cni_missing = sum(is.na(gvhd_prophylaxis_cni)),
      .groups = "drop"
    )

  noncanonical_disease_values <- metadata %>%
    distinct(study, disease) %>%
    filter(!is.na(disease), !disease %in% canonical_disease_values) %>%
    arrange(study, disease)

  noncanonical_nutrition_values <- metadata %>%
    distinct(study, nutrition) %>%
    filter(!is.na(nutrition), !nutrition %in% nutrition_levels) %>%
    arrange(study, nutrition)

  noncanonical_transplant_type_values <- metadata %>%
    distinct(study, transplant_type) %>%
    filter(!is.na(transplant_type), !transplant_type %in% transplant_type_levels) %>%
    arrange(study, transplant_type)

  invalid_binary_values <- map_dfr(binary_outcome_cols, function(field) {
    metadata %>%
      distinct(study, value = .data[[field]]) %>%
      mutate(column = field)
  }) %>%
    filter(!is.na(value), !value %in% c("0", "1")) %>%
    select(study, column, value)

  # An event day without its event is a masking failure: a censoring or
  # diagnosis time has leaked into a column that must hold event times only.
  event_day_cols <- c(
    agvhd = "agvhd_day_rel_transplant",
    gut_gvhd = "gut_gvhd_day_rel_transplant",
    skin_gvhd = "skin_gvhd_day_rel_transplant",
    liver_gvhd = "liver_gvhd_day_rel_transplant",
    cgvhd = "cgvhd_day_rel_transplant",
    anc_engraftment = "anc_engraftment_day_rel_transplant",
    platelet_engraftment = "platelet_engraftment_day_rel_transplant",
    death = "death_day_rel_transplant",
    relapse = "relapse_day_rel_transplant"
  )

  unmasked_event_days <- map_dfr(names(event_day_cols), function(event) {
    day_col <- event_day_cols[[event]]
    metadata %>%
      filter(!is.na(.data[[day_col]]), is.na(.data[[event]]) | .data[[event]] != "1") %>%
      transmute(
        `sample-id`,
        study,
        column = day_col,
        event_value = .data[[event]],
        day_value = .data[[day_col]]
      )
  })

  # A non-zero organ outcome with no overall aGVHD is internally inconsistent.
  organ_without_agvhd <- metadata %>%
    filter(
      !is.na(agvhd), agvhd == "0",
      (!is.na(gut_gvhd) & gut_gvhd == "1") |
        (!is.na(skin_gvhd) & skin_gvhd == "1") |
        (!is.na(liver_gvhd) & liver_gvhd == "1")
    ) %>%
    select(`sample-id`, study, agvhd, gut_gvhd, skin_gvhd, liver_gvhd)

  outcome_coverage <- map_dfr(binary_outcome_cols, function(field) {
    metadata %>%
      group_by(study) %>%
      summarise(
        column = field,
        n = n(),
        n_event = sum(.data[[field]] == "1", na.rm = TRUE),
        n_nonevent = sum(.data[[field]] == "0", na.rm = TRUE),
        n_missing = sum(is.na(.data[[field]])),
        .groups = "drop"
      )
  }) %>%
    select(study, column, n, n_event, n_nonevent, n_missing) %>%
    arrange(study, match(column, binary_outcome_cols))

  invalid_timepoint_values <- metadata %>%
    distinct(study, timepoint) %>%
    filter(!is.na(timepoint), !timepoint %in% timepoint_levels) %>%
    arrange(study, timepoint)

  missing_timepoint_samples <- metadata %>%
    filter(is.na(timepoint)) %>%
    select(`sample-id`, study, sample_day_rel_transplant)

  timepoint_by_study <- metadata %>%
    count(study, timepoint, name = "n") %>%
    arrange(study, match(timepoint, timepoint_levels))

  end_obs_reason_levels <- c(
    "EOS", "administrative", "death", "last observation", "lost to follow up"
  )

  noncanonical_end_reason_values <- metadata %>%
    distinct(study, end_observation_reason) %>%
    filter(
      !is.na(end_observation_reason),
      !end_observation_reason %in% end_obs_reason_levels
    ) %>%
    arrange(study, end_observation_reason)

  end_observation_coverage <- metadata %>%
    group_by(study) %>%
    summarise(
      n_samples = n(),
      n_day_present = sum(!is.na(end_observation_day_rel_transplant)),
      n_day_missing = sum(is.na(end_observation_day_rel_transplant)),
      reasons = paste(sort(unique(na.omit(end_observation_reason))), collapse = ", "),
      .groups = "drop"
    )

  # Secondary outcomes coverage.
  secondary_outcomes_coverage <- metadata %>%
    group_by(study) %>%
    summarise(
      n_samples               = n(),
      n_myelosuppression      = sum(!is.na(myelosuppression)),
      n_mucositis             = sum(!is.na(mucositis)),
      n_bloodstream_infection = sum(!is.na(bloodstream_infection)),
      n_bronchiolitis_obliterans = sum(!is.na(bronchiolitis_obliterans)),
      .groups = "drop"
    )

  # Liu BSI crosswalk audit table. Reproduces every source string, its column,
  # its classification, and the number of recipient rows with that value.
  # Requires raw Liu data; returns an empty tibble if not supplied.
  make_bsi_cw <- function(col_vals, map, col_name) {
    n_tbl <- table(col_vals, useNA = "ifany")
    tibble(
      column       = col_name,
      source_value = names(n_tbl),
      bsi          = if_else(
        is.na(names(n_tbl)), "0",
        unname(map[names(n_tbl)])
      ),
      n_recipients = as.integer(n_tbl)
    )
  }

  liu_bsi_crosswalk <- if (!is.null(raw[["liu"]])) {
    src <- raw[["liu"]]
    rec <- src[str_to_lower(clean_chr(src[["donor_or_patient"]])) == "patient", ]
    bind_rows(
      make_bsi_cw(clean_chr(rec[["infection_duringafter_transplant"]]),
                  liu_bsi_col1_map, "infection_duringafter_transplant"),
      make_bsi_cw(clean_chr(rec[["infection_details"]]),
                  liu_bsi_col2_map, "infection_details")
    )
  } else {
    tibble(column = character(), source_value = character(),
           bsi = character(), n_recipients = integer())
  }

  # Liu BSI unrecognized: any distinct source value not present in the lookup.
  # Must be empty; a non-zero row count means the source file has new values
  # that have not been manually classified.
  liu_bsi_unrecognized <- if (!is.null(raw[["liu"]])) {
    src <- raw[["liu"]]
    rec <- src[str_to_lower(clean_chr(src[["donor_or_patient"]])) == "patient", ]
    bind_rows(
      tibble(
        column = "infection_duringafter_transplant",
        source_value = setdiff(
          unique(na.omit(clean_chr(rec[["infection_duringafter_transplant"]]))),
          names(liu_bsi_col1_map)
        )
      ),
      tibble(
        column = "infection_details",
        source_value = setdiff(
          unique(na.omit(clean_chr(rec[["infection_details"]]))),
          names(liu_bsi_col2_map)
        )
      )
    )
  } else {
    tibble(column = character(), source_value = character())
  }

  list(
    duplicate_sample_ids = duplicate_sample_ids,
    missing_sample_ids = missing_sample_ids,
    missing_person_samples = missing_person_samples,
    person_conflicts = person_conflicts,
    noncanonical_conditioning_intensity_values = noncanonical_conditioning_intensity_values,
    conditioning_regimen_by_study = conditioning_regimen_by_study,
    conditioning_regimen_forbidden_tokens = conditioning_regimen_forbidden_tokens,
    conditioning_coverage = conditioning_coverage,
    ingham_mac_tbi_dose_check = ingham_mac_tbi_dose_check,
    noncanonical_gvhd_prophylaxis_values = noncanonical_gvhd_prophylaxis_values,
    noncanonical_gvhd_prophylaxis_cni_values = noncanonical_gvhd_prophylaxis_cni_values,
    gvhd_prophylaxis_coverage = gvhd_prophylaxis_coverage,
    noncanonical_disease_values = noncanonical_disease_values,
    noncanonical_nutrition_values = noncanonical_nutrition_values,
    noncanonical_transplant_type_values = noncanonical_transplant_type_values,
    invalid_binary_values = invalid_binary_values,
    invalid_timepoint_values = invalid_timepoint_values,
    missing_timepoint_samples = missing_timepoint_samples,
    timepoint_by_study = timepoint_by_study,
    unmasked_event_days = unmasked_event_days,
    organ_without_agvhd = organ_without_agvhd,
    outcome_coverage = outcome_coverage,
    noncanonical_end_reason_values = noncanonical_end_reason_values,
    end_observation_coverage = end_observation_coverage,
    secondary_outcomes_coverage = secondary_outcomes_coverage,
    liu_bsi_crosswalk = liu_bsi_crosswalk,
    liu_bsi_unrecognized = liu_bsi_unrecognized
  )
}

harmonize_all <- function(
  artacho_raw,
  damico_raw,
  fujimoto_raw,
  ingham_raw,
  liu_raw,
  vallet_raw
) {
  artacho_raw <- ensure_sample_id(artacho_raw)
  damico_raw <- ensure_sample_id(damico_raw)
  fujimoto_raw <- ensure_sample_id(fujimoto_raw)
  ingham_raw <- ensure_sample_id(ingham_raw)
  liu_raw <- ensure_sample_id(liu_raw)
  vallet_raw <- ensure_sample_id(vallet_raw)

  person_crosswalk <- bind_rows(
    make_person_crosswalk(
      artacho_raw[["Patient"]], study_labels[["artacho"]],
      person_prefixes[["artacho"]], "Patient"
    ),
    make_person_crosswalk(
      damico_raw[["Patient"]], study_labels[["damico"]],
      person_prefixes[["damico"]], "Patient"
    ),
    make_person_crosswalk(
      fujimoto_raw[["Patient"]], study_labels[["fujimoto"]],
      person_prefixes[["fujimoto"]], "Patient"
    ),
    make_person_crosswalk(
      ingham_raw[["patient"]], study_labels[["ingham"]],
      person_prefixes[["ingham"]], "patient"
    ),
    make_person_crosswalk(
      liu_raw[["host_subject_id"]], study_labels[["liu"]],
      person_prefixes[["liu"]], "host_subject_id"
    ),
    make_person_crosswalk(
      vallet_raw[["allozithro_id"]], study_labels[["vallet"]],
      person_prefixes[["vallet"]], "allozithro_id"
    )
  )

  metadata <- bind_rows(
    harmonize_artacho(artacho_raw, person_crosswalk),
    harmonize_damico(damico_raw, person_crosswalk),
    harmonize_fujimoto(fujimoto_raw, person_crosswalk),
    harmonize_ingham(ingham_raw, person_crosswalk),
    harmonize_liu(liu_raw, person_crosswalk),
    harmonize_vallet(vallet_raw, person_crosswalk)
  ) %>%
    select(all_of(target_cols))

  qa <- build_qa(metadata, raw = list(ingham = ingham_raw, liu = liu_raw))

  if (nrow(qa$duplicate_sample_ids) > 0) {
    stop("Duplicate sample-id values found after harmonization.", call. = FALSE)
  }
  if (nrow(qa$missing_sample_ids) > 0) {
    stop("Missing sample-id values found after harmonization.", call. = FALSE)
  }

  list(
    metadata = metadata,
    person_crosswalk = person_crosswalk,
    qa = qa
  )
}

# -----------------------------------------------------------------------------
# Example usage. Replace paths with the actual metadata files. name_repair =
# "minimal" preserves source headers exactly, including spaces and punctuation.
# -----------------------------------------------------------------------------
# artacho_raw <- read_tsv("PATH/Artacho_metadata.tsv", show_col_types = FALSE,
#                         name_repair = "minimal")
# damico_raw <- read_tsv("PATH/DAmico_metadata.tsv", show_col_types = FALSE,
#                        name_repair = "minimal")
# fujimoto_raw <- read_tsv("PATH/Fujimoto_metadata.tsv", show_col_types = FALSE,
#                          name_repair = "minimal")
# ingham_raw <- read_tsv("PATH/Ingham_metadata.tsv", show_col_types = FALSE,
#                        name_repair = "minimal")
# liu_raw <- read_tsv("~/Documents/ODSi/ODSiData/Liu2017/Metadata/liu_meta_qiime.tsv",
#                     show_col_types = FALSE, name_repair = "minimal")
# vallet_raw <- read_tsv("PATH/Vallet_metadata.tsv", show_col_types = FALSE,
#                        name_repair = "minimal")
#
# result <- harmonize_all(
#   artacho_raw = artacho_raw,
#   damico_raw = damico_raw,
#   fujimoto_raw = fujimoto_raw,
#   ingham_raw = ingham_raw,
#   liu_raw = liu_raw,
#   vallet_raw = vallet_raw
# )
#
# harmonized_metadata <- result$metadata
# person_crosswalk <- result$person_crosswalk
#
# write_tsv(harmonized_metadata, "harmonized_gvhd_metadata.tsv", na = "NA")
# write_tsv(person_crosswalk, "person_crosswalk.tsv", na = "NA")
# walk2(result$qa, names(result$qa), ~ write_tsv(.x, paste0("qa_", .y, ".tsv"), na = "NA"))
