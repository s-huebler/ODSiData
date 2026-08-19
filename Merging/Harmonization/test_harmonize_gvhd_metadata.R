# Tests for harmonize_gvhd_metadata.R
#
# Run from the repository root:
#   Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R
#
# Part 1 is unit tests on the shared helpers (no data files needed).
# Part 2 runs harmonize_all() against the six real *_meta_qiime.tsv files and
# checks the QA tables plus a per-study cross-tabulation against the source
# columns. Part 2 is skipped with a message if the metadata files are absent.

suppressPackageStartupMessages(library(readr))

here <- tryCatch(dirname(normalizePath(sys.frame(1)$ofile)), error = function(e) ".")
script <- file.path(here, "harmonize_gvhd_metadata.R")
if (!file.exists(script)) script <- "Merging/Harmonization/harmonize_gvhd_metadata.R"
source(script)

failures <- 0L
check <- function(label, ok) {
  ok <- isTRUE(ok)
  cat(sprintf("  [%s] %s\n", if (ok) "PASS" else "FAIL", label))
  if (!ok) failures <<- failures + 1L
  invisible(ok)
}

# =============================================================================
# Part 1: unit tests
# =============================================================================
cat("\n=== Part 1: helper unit tests ===\n")

check("timepoint appears immediately after person",
      identical(target_cols[3:4], c("person", "timepoint")))

days <- c(-30, -8, -7.0001, -7, -2, -1.0001, -1, 0, 1, 1.5, 2, 13, 13.9, 14,
          20, 20.9, 21, 100, NA)
want <- c("pre-conditioning", "pre-conditioning", "pre-conditioning",
          "conditioning", "conditioning", "conditioning",
          "transplant", "transplant", "transplant",
          "pre-engraftment", "pre-engraftment", "pre-engraftment",
          "pre-engraftment", "engraftment", "engraftment", "engraftment",
          "follow-up", "follow-up", NA)
check("harmonize_timepoint bins every boundary correctly",
      identical(harmonize_timepoint(days), want))
check("all timepoint outputs are canonical levels",
      all(na.omit(harmonize_timepoint(days)) %in% timepoint_levels))

check("harmonize_binary maps TRUE/FALSE/NA to 1/0/NA",
      identical(harmonize_binary(c(TRUE, FALSE, NA)), c("1", "0", NA)))

# organ_involved: aGVHD-negative is a confirmed organ negative; aGVHD-positive
# with an unrecorded organ list is unknown.
check("organ_involved: aGVHD negative -> FALSE",
      identical(organ_involved(FALSE, NA, "gut"), FALSE))
check("organ_involved: aGVHD positive, organ unknown -> NA",
      identical(organ_involved(TRUE, NA, "gut"), NA))
check("organ_involved: Fujimoto composite label splits",
      identical(
        organ_involved(rep(TRUE, 3), rep("Gut_Liver_Skin", 3),
                       organ_patterns[c("gut", "skin", "liver")]),
        c(TRUE, TRUE, TRUE)
      ))
check("organ_involved: Skin-only is gut-negative",
      identical(organ_involved(TRUE, "Skin", "gut"), FALSE))
check("organ_involved: Liu 'upper gut' counts as gut",
      identical(organ_involved(TRUE, "skin, upper gut", "gut"), TRUE))
check("organ_involved: Liu 'oral' is not gut, skin or liver",
      identical(
        organ_involved(rep(TRUE, 3), rep("oral", 3),
                       organ_patterns[c("gut", "skin", "liver")]),
        c(FALSE, FALSE, FALSE)
      ))

check("parse_liu_agvhd_grade maps roman grades and 'no'",
      identical(
        parse_liu_agvhd_grade(c("no", "Grade I", "Grade II", "Grade III",
                                "Grade IV", "yes", "suspected", NA)),
        c(0, 1, 2, 3, 4, NA, NA, NA)
      ))
check("harmonize_cgvhd_stage aligns NIH and Shulman vocabularies",
      identical(
        harmonize_cgvhd_stage(c("mild", "moderate", "severe",
                                "Stage 1", "Stage 2", "Stage 3", NA)),
        c(1, 2, 3, 1, 2, 3, NA)
      ))

check("gvhd_prophylaxis_levels contains all five canonical values",
      identical(gvhd_prophylaxis_levels,
                c("cni-mtx", "cni-mmf", "cni-steroid", "cni-alone", "other")))
check("gvhd_prophylaxis_cni_levels contains both canonical CNI names",
      identical(gvhd_prophylaxis_cni_levels, c("cyclosporine", "tacrolimus")))
check("gvhd_prophylaxis and gvhd_prophylaxis_cni appear after the conditioning block",
      {
        idx <- match(c("conditioning_serotherapy",
                       "gvhd_prophylaxis", "gvhd_prophylaxis_cni"),
                     target_cols)
        all(!is.na(idx)) && idx[2] == idx[1] + 1L && idx[3] == idx[1] + 2L
      })
check("gvhd_prophylaxis_cni appears before agvhd in target_cols",
      match("gvhd_prophylaxis_cni", target_cols) < match("agvhd", target_cols))

check("conditioning_intensity_levels is MAC / RIC / NMA",
      identical(conditioning_intensity_levels, c("MAC", "RIC", "NMA")))
check("conditioning_tbi is in binary_outcome_cols",
      "conditioning_tbi" %in% binary_outcome_cols)
check("conditioning_serotherapy is in binary_outcome_cols",
      "conditioning_serotherapy" %in% binary_outcome_cols)
check("conditioning_intensity immediately follows sample_day_rel_transplant",
      {
        idx <- match(c("sample_day_rel_transplant", "conditioning_intensity"), target_cols)
        all(!is.na(idx)) && idx[2] == idx[1] + 1L
      })
check("conditioning block (4 cols) precedes gvhd_prophylaxis",
      match("conditioning_serotherapy", target_cols) <
        match("gvhd_prophylaxis", target_cols))

check("all four secondary outcome cols in binary_outcome_cols",
      all(c("myelosuppression", "mucositis",
            "bloodstream_infection", "bronchiolitis_obliterans") %in%
            binary_outcome_cols))
check("secondary outcomes appear at end of target_cols in correct order",
      {
        idx <- match(c("end_observation_day_rel_transplant",
                       "myelosuppression", "mucositis",
                       "bloodstream_infection", "bronchiolitis_obliterans"),
                     target_cols)
        all(!is.na(idx)) && all(diff(idx) == 1L)
      })

# =============================================================================
# Part 2: end-to-end against the real metadata
# =============================================================================
cat("\n=== Part 2: end-to-end on real metadata ===\n")

root <- Sys.getenv("ODSI_ROOT", unset = ".")
paths <- c(
  artacho  = "Artacho2024/Metadata/artacho_meta_qiime.tsv",
  damico   = "DAmico2019/Metadata/damico_meta_qiime.tsv",
  fujimoto = "Fujimoto2024/Metadata/fuji_meta_qiime.tsv",
  ingham   = "Ingham2019/Metadata/ingham_meta_qiime.tsv",
  liu      = "Liu2017/Metadata/liu_meta_qiime.tsv",
  vallet   = "Vallet2023/Metadata/vallet_meta_qiime.tsv"
)
full <- file.path(root, paths)

if (!all(file.exists(full))) {
  cat("  SKIPPED - metadata files not found under '", root, "'.\n", sep = "")
  cat("  Set ODSI_ROOT to the repository root, or run from it.\n")
} else {
  rd <- function(p) read_tsv(p, show_col_types = FALSE, name_repair = "minimal",
                             progress = FALSE)
  raw <- lapply(full, rd)
  names(raw) <- names(paths)

  res <- harmonize_all(
    artacho_raw = raw$artacho, damico_raw = raw$damico,
    fujimoto_raw = raw$fujimoto, ingham_raw = raw$ingham,
    liu_raw = raw$liu, vallet_raw = raw$vallet
  )
  md <- res$metadata
  qa <- res$qa

  cat(sprintf("  harmonized %d samples x %d columns\n", nrow(md), ncol(md)))

  for (nm in c("duplicate_sample_ids", "missing_sample_ids",
               "invalid_binary_values", "invalid_timepoint_values",
               "unmasked_event_days", "organ_without_agvhd",
               "person_conflicts")) {
    ok <- nrow(qa[[nm]]) == 0
    check(sprintf("QA %s is empty", nm), ok)
    if (!ok) print(head(as.data.frame(qa[[nm]]), 10))
  }

  # Ingham contributes one sequencing run with no clinical metadata at all (no
  # patient, no timepoint). It is the only sample allowed to lack a timepoint.
  check("the only sample missing a timepoint is the metadata-less Ingham run",
        {
          miss <- qa$missing_timepoint_samples
          nrow(miss) <= 1 &&
            (nrow(miss) == 0 ||
               all(miss$`sample-id` %in% md$`sample-id`[is.na(md$person)]))
        })

  check("column order matches target_cols", identical(names(md), target_cols))

  # --- Fujimoto: composite organ labels split correctly ----------------------
  fm <- md[md$study == study_labels[["fujimoto"]], ]
  # %in% rather than == so the 164 NA (aGVHD-free) rows do not index by NA.
  triple <- which(raw$fujimoto$AGVHD_Organ %in% "Gut_Liver_Skin")
  skin_only <- which(raw$fujimoto$AGVHD_Organ %in% "Skin")
  check("Fujimoto Gut_Liver_Skin sets all three organs",
        length(triple) > 0 &&
          all(fm$gut_gvhd[triple] == "1") &&
          all(fm$skin_gvhd[triple] == "1") &&
          all(fm$liver_gvhd[triple] == "1"))
  check("Fujimoto Skin-only leaves gut and liver at 0",
        length(skin_only) > 0 &&
          all(fm$gut_gvhd[skin_only] == "0") &&
          all(fm$liver_gvhd[skin_only] == "0") &&
          all(fm$skin_gvhd[skin_only] == "1"))
  check("Fujimoto organ stage equals the overall grade where involved",
        identical(fm$gut_gvhd_stage[fm$gut_gvhd == "1"],
                  fm$agvhd_grade[fm$gut_gvhd == "1"]))
  check("Fujimoto organ day equals the overall onset day where involved",
        identical(fm$skin_gvhd_day_rel_transplant[fm$skin_gvhd == "1"],
                  fm$agvhd_day_rel_transplant[fm$skin_gvhd == "1"]))

  # --- Liu: derived gut must reproduce the source agvhd_gut flag -------------
  lm <- md[md$study == study_labels[["liu"]], ]
  src_gut <- c(positive = "1", negative = "0")[tolower(raw$liu$agvhd_gut)]
  check("Liu derived gut_gvhd reproduces source agvhd_gut (incl. 'upper gut')",
        identical(unname(src_gut), lm$gut_gvhd))
  check("Liu cgvhd_day_rel_transplant is entirely NA (time_to_cgvhd unusable)",
        all(is.na(lm$cgvhd_day_rel_transplant)))
  check("Liu donor rows have NA for every GVHD outcome",
        {
          donor <- tolower(raw$liu$donor_or_patient) == "donor"
          all(is.na(lm$agvhd[donor])) && all(is.na(lm$gut_gvhd[donor])) &&
            all(is.na(lm$cgvhd[donor]))
        })
  check("Liu ungraded aGVHD ('yes'/'suspected') has event 1 but NA grade",
        {
          ung <- tolower(raw$liu$agvhd_severity) %in% c("yes", "suspected")
          all(lm$agvhd[ung] == "1") && all(is.na(lm$agvhd_grade[ung]))
        })

  # --- Vallet: competing-risk code 2 becomes 0 ------------------------------
  vm <- md[md$study == study_labels[["vallet"]], ]
  check("Vallet agvhd code 2 (competing event) maps to 0",
        all(vm$agvhd[raw$vallet$agvhd == 2] == "0"))
  check("Vallet agvhd code 1 maps to 1",
        all(vm$agvhd[raw$vallet$agvhd == 1] == "1"))
  check("Vallet cgvhd present exactly when dat_cgvhd is present",
        identical(vm$cgvhd == "1", !is.na(raw$vallet$dat_cgvhd)))
  check("Vallet cGVHD onset days are positive",
        all(as.numeric(vm$cgvhd_day_rel_transplant) > 0, na.rm = TRUE))

  # --- Ingham: overall only, cGVHD constant 0 -------------------------------
  im <- md[md$study == study_labels[["ingham"]], ]
  check("Ingham leaves every organ-specific column NA",
        all(is.na(im$gut_gvhd)) && all(is.na(im$skin_gvhd)) &&
          all(is.na(im$liver_gvhd)))
  check("Ingham cgvhd is 0 for all documented patients",
        all(im$cgvhd == "0", na.rm = TRUE))
  check("Ingham aGVHD onset days are positive",
        all(as.numeric(im$agvhd_day_rel_transplant) > 0, na.rm = TRUE))

  # --- DAmico: one onset day shared across involved organs ------------------
  dm <- md[md$study == study_labels[["damico"]], ]
  both <- dm$gut_gvhd == "1" & dm$skin_gvhd == "1"
  check("DAmico shares gvhd_day across every involved organ",
        identical(dm$gut_gvhd_day_rel_transplant[both],
                  dm$skin_gvhd_day_rel_transplant[both]))
  check("DAmico agvhd is 1 whenever any organ stage is non-zero",
        {
          any_organ <- dm$gut_gvhd == "1" | dm$skin_gvhd == "1" |
            dm$liver_gvhd == "1"
          identical(dm$agvhd == "1", any_organ)
        })

  # --- Artacho: organ stages, no onset days anywhere ------------------------
  am <- md[md$study == study_labels[["artacho"]], ]
  check("Artacho leaves every acute GVHD onset day NA",
        all(is.na(am$agvhd_day_rel_transplant)) &&
          all(is.na(am$gut_gvhd_day_rel_transplant)) &&
          all(is.na(am$skin_gvhd_day_rel_transplant)) &&
          all(is.na(am$liver_gvhd_day_rel_transplant)))
  check("Artacho organ stage 0 gives outcome 0, not NA",
        all(am$gut_gvhd[raw$artacho$gut_gvhd_grade == 0] == "0"))

  # --- GVHD prophylaxis: QA tables -------------------------------------------
  check("QA noncanonical_gvhd_prophylaxis_values is empty",
        nrow(qa$noncanonical_gvhd_prophylaxis_values) == 0)
  if (nrow(qa$noncanonical_gvhd_prophylaxis_values) > 0)
    print(as.data.frame(qa$noncanonical_gvhd_prophylaxis_values))

  check("QA noncanonical_gvhd_prophylaxis_cni_values is empty",
        nrow(qa$noncanonical_gvhd_prophylaxis_cni_values) == 0)
  if (nrow(qa$noncanonical_gvhd_prophylaxis_cni_values) > 0)
    print(as.data.frame(qa$noncanonical_gvhd_prophylaxis_cni_values))

  check("all gvhd_prophylaxis values are canonical",
        all(na.omit(md$gvhd_prophylaxis) %in% gvhd_prophylaxis_levels))
  check("all gvhd_prophylaxis_cni values are canonical",
        all(na.omit(md$gvhd_prophylaxis_cni) %in% gvhd_prophylaxis_cni_levels))

  # Studies with no prophylaxis data: both columns all NA.
  for (st_label in c("artacho", "damico", "fujimoto")) {
    sl <- study_labels[[st_label]]
    sub <- md[md$study == sl, ]
    check(sprintf("%s gvhd_prophylaxis is all NA", st_label),
          all(is.na(sub$gvhd_prophylaxis)))
    check(sprintf("%s gvhd_prophylaxis_cni is all NA", st_label),
          all(is.na(sub$gvhd_prophylaxis_cni)))
  }

  # --- Ingham: string mapping ------------------------------------------------
  check("Ingham 'Cyclosporine A + Methotrexate' -> cni-mtx",
        all(im$gvhd_prophylaxis[
              raw$ingham$gvhd_prophylaxis == "Cyclosporine A + Methotrexate"
            ] == "cni-mtx", na.rm = TRUE))
  check("Ingham 'Cyclosporine + Corticosteroids' -> cni-steroid",
        all(im$gvhd_prophylaxis[
              raw$ingham$gvhd_prophylaxis == "Cyclosporine + Corticosteroids"
            ] == "cni-steroid", na.rm = TRUE))
  check("Ingham 'Cyclosporine A' (monotherapy code) -> cni-alone",
        all(im$gvhd_prophylaxis[
              raw$ingham$gvhd_prophylaxis == "Cyclosporine A"
            ] == "cni-alone", na.rm = TRUE))
  check("Ingham gvhd_prophylaxis_cni is cyclosporine wherever prophylaxis is non-NA",
        all(im$gvhd_prophylaxis_cni[!is.na(im$gvhd_prophylaxis)] == "cyclosporine"))
  check("Ingham NA source row gives NA in both prophylaxis columns",
        {
          na_rows <- is.na(raw$ingham$gvhd_prophylaxis)
          all(is.na(im$gvhd_prophylaxis[na_rows])) &&
            all(is.na(im$gvhd_prophylaxis_cni[na_rows]))
        })

  # --- Liu: one-hot collapse --------------------------------------------------
  lm_rec <- lm[tolower(raw$liu$donor_or_patient) == "patient", ]
  raw_rec <- raw$liu[tolower(raw$liu$donor_or_patient) == "patient", ]

  check("Liu every recipient has exactly one CNI",
        all(
          (raw_rec$cyclosporine == "yes") + (raw_rec$tacrolimus == "yes") == 1
        ))
  check("Liu every recipient has exactly one partner agent (mtx or mmf)",
        all(
          (raw_rec$methotrexate == "yes") + (raw_rec$mmf == "yes") == 1
        ))
  check("Liu cyclosporine=yes -> gvhd_prophylaxis_cni == cyclosporine",
        all(lm_rec$gvhd_prophylaxis_cni[raw_rec$cyclosporine == "yes"] ==
              "cyclosporine"))
  check("Liu tacrolimus=yes -> gvhd_prophylaxis_cni == tacrolimus",
        all(lm_rec$gvhd_prophylaxis_cni[raw_rec$tacrolimus == "yes"] ==
              "tacrolimus"))
  check("Liu methotrexate=yes -> gvhd_prophylaxis == cni-mtx",
        all(lm_rec$gvhd_prophylaxis[raw_rec$methotrexate == "yes"] == "cni-mtx"))
  check("Liu mmf=yes -> gvhd_prophylaxis == cni-mmf",
        all(lm_rec$gvhd_prophylaxis[raw_rec$mmf == "yes"] == "cni-mmf"))
  check("Liu donor rows have NA prophylaxis columns",
        {
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(is.na(lm$gvhd_prophylaxis[donor_flag])) &&
            all(is.na(lm$gvhd_prophylaxis_cni[donor_flag]))
        })

  # --- Vallet: string mapping ------------------------------------------------
  check("Vallet 'ciclosporin-MTX' -> cni-mtx / cyclosporine",
        {
          rows <- raw$vallet$gvhd_proph_type == "ciclosporin-MTX"
          all(vm$gvhd_prophylaxis[rows] == "cni-mtx") &&
            all(vm$gvhd_prophylaxis_cni[rows] == "cyclosporine")
        })
  check("Vallet 'cyclosporin-MMF' -> cni-mmf / cyclosporine",
        {
          rows <- raw$vallet$gvhd_proph_type == "cyclosporin-MMF"
          all(vm$gvhd_prophylaxis[rows] == "cni-mmf") &&
            all(vm$gvhd_prophylaxis_cni[rows] == "cyclosporine")
        })
  check("Vallet 'Other' -> other / NA cni",
        {
          rows <- raw$vallet$gvhd_proph_type == "Other"
          all(vm$gvhd_prophylaxis[rows] == "other") &&
            all(is.na(vm$gvhd_prophylaxis_cni[rows]))
        })

  cat("\n  --- gvhd_prophylaxis coverage by study ---\n")
  print(as.data.frame(qa$gvhd_prophylaxis_coverage), row.names = FALSE)

  # --- transplant_type -------------------------------------------------------
  check("QA noncanonical_transplant_type_values is empty",
        nrow(qa$noncanonical_transplant_type_values) == 0)
  if (nrow(qa$noncanonical_transplant_type_values) > 0)
    print(as.data.frame(qa$noncanonical_transplant_type_values))

  check("all transplant_type values are canonical",
        all(na.omit(md$transplant_type) %in% transplant_type_levels))

  # Artacho: numeric 1/2/3 → bone marrow / cord / PBSC
  check("Artacho Transplant.source 1 → bone marrow",
        all(am$transplant_type[raw$artacho$Transplant.source == 1] == "bone marrow"))
  check("Artacho Transplant.source 2 → umbilical cord blood",
        all(am$transplant_type[raw$artacho$Transplant.source == 2] == "umbilical cord blood"))
  check("Artacho Transplant.source 3 → peripheral blood stem cells",
        all(am$transplant_type[raw$artacho$Transplant.source == 3] == "peripheral blood stem cells"))
  check("Artacho transplant_type has no NAs",
        sum(is.na(am$transplant_type)) == 0)

  # DAmico: BM → bone marrow, PBSC → peripheral blood stem cells
  check("DAmico BM → bone marrow",
        all(dm$transplant_type[raw$damico$Stem_cell_source == "BM"] == "bone marrow"))
  check("DAmico PBSC → peripheral blood stem cells",
        all(dm$transplant_type[raw$damico$Stem_cell_source == "PBSC"] == "peripheral blood stem cells"))

  # Fujimoto: BM/PB/CB → bone marrow / PBSC / cord
  check("Fujimoto BM → bone marrow",
        all(fm$transplant_type[raw$fujimoto$Graft_Type == "BM"] == "bone marrow"))
  check("Fujimoto PB → peripheral blood stem cells",
        all(fm$transplant_type[raw$fujimoto$Graft_Type == "PB"] == "peripheral blood stem cells"))
  check("Fujimoto CB → umbilical cord blood",
        all(fm$transplant_type[raw$fujimoto$Graft_Type == "CB"] == "umbilical cord blood"))

  # Ingham: BM/PBSC/UC/BM_UC → canonical values; 1 NA patient stays NA
  check("Ingham BM → bone marrow",
        all(im$transplant_type[raw$ingham$transplant_type == "BM"] == "bone marrow",
            na.rm = TRUE))
  check("Ingham PBSC → peripheral blood stem cells",
        all(im$transplant_type[raw$ingham$transplant_type == "PBSC"] ==
              "peripheral blood stem cells", na.rm = TRUE))
  check("Ingham UC → umbilical cord blood",
        all(im$transplant_type[raw$ingham$transplant_type == "UC"] ==
              "umbilical cord blood", na.rm = TRUE))
  check("Ingham BM_UC → bone marrow and umbilical cord blood",
        all(im$transplant_type[raw$ingham$transplant_type == "BM_UC"] ==
              "bone marrow and umbilical cord blood", na.rm = TRUE))
  check("Ingham NA transplant_type stays NA",
        all(is.na(im$transplant_type[is.na(raw$ingham$transplant_type)])))

  # Liu: donor → none; pbsc/marrow/cord+cord → canonical values
  check("Liu donor rows → none",
        {
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(lm$transplant_type[donor_flag] == "none")
        })
  check("Liu pbsc → peripheral blood stem cells",
        all(lm$transplant_type[raw$liu$donor_source == "pbsc"] ==
              "peripheral blood stem cells", na.rm = TRUE))
  check("Liu marrow → bone marrow",
        all(lm$transplant_type[raw$liu$donor_source == "marrow"] == "bone marrow",
            na.rm = TRUE))
  check("Liu cord+cord → umbilical cord blood",
        all(lm$transplant_type[raw$liu$donor_source == "cord+cord"] ==
              "umbilical cord blood", na.rm = TRUE))

  # Vallet: PBC/cord blood/bone marrow → canonical values, no NAs
  check("Vallet PBC → peripheral blood stem cells",
        all(vm$transplant_type[raw$vallet$csh_type == "PBC"] ==
              "peripheral blood stem cells"))
  check("Vallet cord blood → umbilical cord blood",
        all(vm$transplant_type[raw$vallet$csh_type == "cord blood"] ==
              "umbilical cord blood"))
  check("Vallet bone marrow → bone marrow",
        all(vm$transplant_type[raw$vallet$csh_type == "bone marrow"] == "bone marrow"))
  check("Vallet transplant_type has no NAs",
        sum(is.na(vm$transplant_type)) == 0)

  # --- nutrition -------------------------------------------------------------
  check("QA noncanonical_nutrition_values is empty",
        nrow(qa$noncanonical_nutrition_values) == 0)
  if (nrow(qa$noncanonical_nutrition_values) > 0)
    print(as.data.frame(qa$noncanonical_nutrition_values))

  check("harmonize_nutrition maps values to canonical vocabulary",
        all(na.omit(md$nutrition) %in% nutrition_levels))

  # Artacho: Parenteral.Nutrition Yes→parenteral, No→enteral, no NAs.
  check("Artacho Yes parenteral.nutrition maps to parenteral",
        all(am$nutrition[raw$artacho$Parenteral.Nutrition == "Yes"] == "parenteral"))
  check("Artacho No parenteral.nutrition maps to enteral",
        all(am$nutrition[raw$artacho$Parenteral.Nutrition == "No"] == "enteral"))
  check("Artacho nutrition has no NAs",
        sum(is.na(am$nutrition)) == 0)

  # DAmico: EN-only→enteral, PN-only→parenteral, both→mixed.
  check("DAmico EN-only regimen maps to enteral",
        {
          en_only <- grepl("EN", raw$damico$Nutritional_Regimen) &
            !grepl("PN", raw$damico$Nutritional_Regimen)
          all(dm$nutrition[en_only] == "enteral")
        })
  check("DAmico PN-only regimen maps to parenteral",
        {
          pn_only <- grepl("PN", raw$damico$Nutritional_Regimen) &
            !grepl("EN", raw$damico$Nutritional_Regimen)
          all(dm$nutrition[pn_only] == "parenteral")
        })
  check("DAmico EN+PN regimen maps to mixed",
        {
          both <- grepl("EN", raw$damico$Nutritional_Regimen) &
            grepl("PN", raw$damico$Nutritional_Regimen)
          all(dm$nutrition[both] == "mixed")
        })

  # Vallet: parenterale→parenteral, enteral→enteral, oral→oral; 2 patient NAs.
  check("Vallet parenterale maps to parenteral",
        all(vm$nutrition[raw$vallet$nutrition == "parenterale"] == "parenteral",
            na.rm = TRUE))
  check("Vallet enteral maps to enteral",
        all(vm$nutrition[raw$vallet$nutrition == "enteral"] == "enteral",
            na.rm = TRUE))
  check("Vallet oral maps to oral",
        all(vm$nutrition[raw$vallet$nutrition == "oral"] == "oral",
            na.rm = TRUE))
  check("Vallet NA nutrition rows stay NA",
        all(is.na(vm$nutrition[is.na(raw$vallet$nutrition)])))

  # Fujimoto, Ingham, Liu: not recorded → all NA.
  for (st_label in c("fujimoto", "ingham", "liu")) {
    sl <- study_labels[[st_label]]
    sub <- md[md$study == sl, ]
    check(sprintf("%s nutrition is all NA", sl), all(is.na(sub$nutrition)))
  }

  # --- engraftment -----------------------------------------------------------
  # Helper: align source rows to crosswalk order for a given study.
  cw_align <- function(study_label, orig_ids, src_df, src_id_col) {
    cw <- res$person_crosswalk[
      res$person_crosswalk$study == study_label &
        res$person_crosswalk$original_person %in% orig_ids, ]
    src_aligned <- src_df[match(cw$original_person, src_df[[src_id_col]]), ]
    list(cw = cw, src = src_aligned)
  }

  # DAmico: PMN_day always present -> anc_engraftment always 1; PLT absent for
  # E10 -> platelet_engraftment = 0 for that patient.
  check("DAmico anc_engraftment is 1 for all samples",
        all(dm$anc_engraftment == "1") && sum(is.na(dm$anc_engraftment)) == 0)
  check("DAmico anc_engraftment_day reproduces PMN_day",
        {
          src_dm_uniq <- raw$damico[!duplicated(raw$damico$Patient), ]
          al <- cw_align(study_labels[["damico"]], src_dm_uniq$Patient,
                         src_dm_uniq, "Patient")
          obs <- dm[!duplicated(dm$person), ]
          obs <- obs[match(al$cw$person, obs$person), ]
          expected <- as.character(as.numeric(al$src$PMN_day))
          all(obs$anc_engraftment_day_rel_transplant == expected)
        })
  check("DAmico PLT-absent patient has platelet_engraftment == 0 and NA day",
        {
          no_plt <- which(is.na(as.numeric(raw$damico$PLT_over_20000_day)))
          all(dm$platelet_engraftment[no_plt] == "0") &&
            all(is.na(dm$platelet_engraftment_day_rel_transplant[no_plt]))
        })
  check("DAmico platelet_engraftment_day reproduces PLT_over_20000_day where present",
        {
          has_plt <- !is.na(as.numeric(raw$damico$PLT_over_20000_day))
          expected <- as.character(as.numeric(raw$damico$PLT_over_20000_day[has_plt]))
          all(dm$platelet_engraftment_day_rel_transplant[has_plt] == expected)
        })

  # Liu: yes/no flag drives event; "no" patients get 0 with NA day; donors NA.
  check("Liu 'yes' patients have anc_engraftment == 1 with a day",
        {
          yes_rows <- tolower(raw$liu$anc_engrafment) == "yes" & !is.na(raw$liu$anc_engrafment)
          all(lm$anc_engraftment[yes_rows] == "1") &&
            all(!is.na(lm$anc_engraftment_day_rel_transplant[yes_rows]))
        })
  check("Liu 'no' patients have anc_engraftment == 0 with NA day",
        {
          no_rows <- tolower(raw$liu$anc_engrafment) == "no" & !is.na(raw$liu$anc_engrafment)
          all(lm$anc_engraftment[no_rows] == "0") &&
            all(is.na(lm$anc_engraftment_day_rel_transplant[no_rows]))
        })
  check("Liu anc_engraftment_day reproduces days_to_anc_engrafment for 'yes' rows",
        {
          yes_rows <- tolower(raw$liu$anc_engrafment) == "yes" & !is.na(raw$liu$anc_engrafment)
          expected <- as.character(as.numeric(raw$liu$days_to_anc_engrafment[yes_rows]))
          all(lm$anc_engraftment_day_rel_transplant[yes_rows] == expected)
        })
  check("Liu 'yes' patients have platelet_engraftment == 1 with a day",
        {
          yes_rows <- tolower(raw$liu$platelet_engrafment) == "yes" & !is.na(raw$liu$platelet_engrafment)
          all(lm$platelet_engraftment[yes_rows] == "1") &&
            all(!is.na(lm$platelet_engraftment_day_rel_transplant[yes_rows]))
        })
  check("Liu 'no' patients have platelet_engraftment == 0 with NA day",
        {
          no_rows <- tolower(raw$liu$platelet_engrafment) == "no" & !is.na(raw$liu$platelet_engrafment)
          all(lm$platelet_engraftment[no_rows] == "0") &&
            all(is.na(lm$platelet_engraftment_day_rel_transplant[no_rows]))
        })
  check("Liu donor rows have NA engraftment columns",
        {
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(is.na(lm$anc_engraftment[donor_flag])) &&
            all(is.na(lm$anc_engraftment_day_rel_transplant[donor_flag])) &&
            all(is.na(lm$platelet_engraftment[donor_flag])) &&
            all(is.na(lm$platelet_engraftment_day_rel_transplant[donor_flag]))
        })

  # Studies with no engraftment data at all: all four columns NA.
  for (st_label in c("artacho", "fujimoto", "vallet")) {
    sl <- study_labels[[st_label]]
    sub <- md[md$study == sl, ]
    check(sprintf("%s engraftment columns are all NA", sl),
          all(is.na(sub$anc_engraftment)) &&
            all(is.na(sub$anc_engraftment_day_rel_transplant)) &&
            all(is.na(sub$platelet_engraftment)) &&
            all(is.na(sub$platelet_engraftment_day_rel_transplant)))
  }

  # Ingham: anc_engraftment reflects Engraphment flag; day and platelet NA.
  check("Ingham anc_engraftment reproduces Engraphment flag",
        {
          src_eng <- as.numeric(raw$ingham$Engraphment)
          expected <- dplyr::case_when(
            is.na(src_eng) ~ NA_character_,
            src_eng == 1   ~ "1",
            TRUE           ~ "0"
          )
          identical(im$anc_engraftment, expected)
        })
  check("Ingham anc_engraftment_day_rel_transplant is all NA",
        all(is.na(im$anc_engraftment_day_rel_transplant)))
  check("Ingham platelet engraftment columns are all NA",
        all(is.na(im$platelet_engraftment)) &&
          all(is.na(im$platelet_engraftment_day_rel_transplant)))

  # --- end_observation QA checks --------------------------------------------
  check("QA noncanonical_end_reason_values is empty",
        nrow(qa$noncanonical_end_reason_values) == 0)
  if (nrow(qa$noncanonical_end_reason_values) > 0)
    print(as.data.frame(qa$noncanonical_end_reason_values))

  # --- DAmico: hardcoded day 100, reason administrative --------------------
  check("DAmico end_observation_day is 100 for all samples",
        all(dm$end_observation_day_rel_transplant == "100", na.rm = TRUE) &&
          sum(is.na(dm$end_observation_day_rel_transplant)) == 0)
  check("DAmico end_observation_reason is administrative for all samples",
        all(dm$end_observation_reason == "administrative", na.rm = TRUE) &&
          sum(is.na(dm$end_observation_reason)) == 0)

  # --- Ingham: death patients use tte_death; alive patients use censor ------
  src_ingham <- raw$ingham[!duplicated(raw$ingham$patient), ]
  im_uniq    <- im[!duplicated(im$person), ]

  check("Ingham dead patients have end_observation_day == tte_death",
        {
          dead_ids <- src_ingham$patient[!is.na(src_ingham$death) &
                                           src_ingham$death == 1]
          al <- cw_align(study_labels[["ingham"]], dead_ids, src_ingham, "patient")
          obs <- im_uniq[match(al$cw$person, im_uniq$person), ]
          expected <- as.character(as.numeric(al$src$tte_death))
          all(obs$end_observation_day_rel_transplant == expected)
        })
  check("Ingham dead patients have end_observation_reason == death",
        {
          dead_ids <- src_ingham$patient[!is.na(src_ingham$death) &
                                           src_ingham$death == 1]
          al <- cw_align(study_labels[["ingham"]], dead_ids, src_ingham, "patient")
          obs <- im_uniq[match(al$cw$person, im_uniq$person), ]
          all(obs$end_observation_reason == "death")
        })
  check("Ingham alive patients have end_observation_reason == EOS",
        {
          alive_ids <- src_ingham$patient[!is.na(src_ingham$death) &
                                            src_ingham$death == 0]
          al <- cw_align(study_labels[["ingham"]], alive_ids, src_ingham, "patient")
          obs <- im_uniq[match(al$cw$person, im_uniq$person), ]
          all(obs$end_observation_reason == "EOS")
        })

  # --- Liu: deceased=1 & time_to_death non-NA → day == time_to_death --------
  src_liu_pt_uniq <- raw$liu[tolower(raw$liu$donor_or_patient) == "patient" &
                                !duplicated(raw$liu$host_subject_id), ]
  lm_uniq <- lm[!duplicated(lm$person), ]

  check("Liu deceased with time_to_death uses time_to_death as end_observation_day",
        {
          src <- src_liu_pt_uniq[src_liu_pt_uniq$deceased == 1 &
                                   !is.na(as.numeric(src_liu_pt_uniq$time_to_death)), ]
          al  <- cw_align(study_labels[["liu"]], src$host_subject_id,
                          src, "host_subject_id")
          obs <- lm_uniq[match(al$cw$person, lm_uniq$person), ]
          expected <- as.character(as.numeric(al$src$time_to_death))
          all(obs$end_observation_day_rel_transplant == expected)
        })
  check("Liu alive recipients have end_observation_day == right_censor_time",
        {
          src <- src_liu_pt_uniq[src_liu_pt_uniq$deceased == 0, ]
          al  <- cw_align(study_labels[["liu"]], src$host_subject_id,
                          src, "host_subject_id")
          obs <- lm_uniq[match(al$cw$person, lm_uniq$person), ]
          expected <- as.character(as.numeric(al$src$right_censor_time))
          all(obs$end_observation_day_rel_transplant == expected)
        })
  check("Liu donor rows have NA end_observation columns",
        {
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(is.na(lm$end_observation_reason[donor_flag])) &&
            all(is.na(lm$end_observation_day_rel_transplant[donor_flag]))
        })
  check("Liu deceased patients have end_observation_reason == death",
        {
          src <- src_liu_pt_uniq[src_liu_pt_uniq$deceased == 1, ]
          al  <- cw_align(study_labels[["liu"]], src$host_subject_id,
                          src, "host_subject_id")
          obs <- lm_uniq[match(al$cw$person, lm_uniq$person), ]
          all(obs$end_observation_reason == "death")
        })

  # --- Vallet: death patients use min(lfu, eos, death); reason matches ------
  src_vallet_uniq <- raw$vallet[!duplicated(raw$vallet$allozithro_id), ]
  vm_uniq <- vm[!duplicated(vm$person), ]
  check("Vallet patients with dat.death have end_observation_reason == death",
        {
          src <- src_vallet_uniq[!is.na(src_vallet_uniq$dat.death), ]
          al  <- cw_align(study_labels[["vallet"]], src$allozithro_id,
                          src, "allozithro_id")
          obs <- vm_uniq[match(al$cw$person, vm_uniq$person), ]
          all(obs$end_observation_reason == "death")
        })
  check("Vallet no patient has end_observation_reason == lost to follow up",
        !any(vm$end_observation_reason == "lost to follow up", na.rm = TRUE))
  check("Vallet end_observation_day is non-NA for all patients",
        all(!is.na(vm$end_observation_day_rel_transplant)))

  # --- Artacho / Fujimoto: not recorded → both columns NA ------------------
  check("Artacho end_observation columns are all NA",
        all(is.na(am$end_observation_reason)) &&
          all(is.na(am$end_observation_day_rel_transplant)))
  check("Fujimoto end_observation columns are all NA",
        all(is.na(fm$end_observation_reason)) &&
          all(is.na(fm$end_observation_day_rel_transplant)))

  # ==========================================================================
  # Conditioning variables
  # ==========================================================================

  # --- Unit-style: vocabulary and placement ----------------------------------
  check("conditioning_intensity_levels == c('MAC','RIC','NMA')",
        identical(conditioning_intensity_levels, c("MAC", "RIC", "NMA")))
  check("conditioning_tbi in binary_outcome_cols",
        "conditioning_tbi" %in% binary_outcome_cols)
  check("conditioning_serotherapy in binary_outcome_cols",
        "conditioning_serotherapy" %in% binary_outcome_cols)
  check("conditioning block placed after sample_day_rel_transplant and before gvhd_prophylaxis",
        {
          idx <- match(c("sample_day_rel_transplant",
                         "conditioning_intensity", "conditioning_regimen",
                         "conditioning_tbi", "conditioning_serotherapy",
                         "gvhd_prophylaxis"),
                       target_cols)
          all(!is.na(idx)) && all(diff(idx) == 1L)
        })

  # --- QA tables --------------------------------------------------------------
  check("QA noncanonical_conditioning_intensity_values is empty",
        nrow(qa$noncanonical_conditioning_intensity_values) == 0)
  if (nrow(qa$noncanonical_conditioning_intensity_values) > 0)
    print(as.data.frame(qa$noncanonical_conditioning_intensity_values))

  check("QA conditioning_regimen_forbidden_tokens is empty",
        nrow(qa$conditioning_regimen_forbidden_tokens) == 0)
  if (nrow(qa$conditioning_regimen_forbidden_tokens) > 0)
    print(as.data.frame(qa$conditioning_regimen_forbidden_tokens))

  check("all conditioning_intensity values are canonical",
        all(na.omit(md$conditioning_intensity) %in% conditioning_intensity_levels))

  # --- Studies with no conditioning data: regimen/tbi/sero all NA ------------
  check("Artacho conditioning_regimen is all NA",
        all(is.na(am$conditioning_regimen)))
  check("Artacho conditioning_tbi is all NA",
        all(is.na(am$conditioning_tbi)))
  check("Artacho conditioning_serotherapy is all NA",
        all(is.na(am$conditioning_serotherapy)))
  check("Vallet conditioning_regimen is all NA",
        all(is.na(vm$conditioning_regimen)))
  check("Vallet conditioning_tbi is all NA",
        all(is.na(vm$conditioning_tbi)))
  check("Vallet conditioning_serotherapy is all NA",
        all(is.na(vm$conditioning_serotherapy)))

  # --- DAmico -----------------------------------------------------------------
  check("DAmico all samples are MAC",
        all(dm$conditioning_intensity == "MAC", na.rm = TRUE) &&
          sum(is.na(dm$conditioning_intensity)) == 0)
  check("DAmico 'EDX, FLUDARA, TBI' row has conditioning_tbi == 1",
        {
          tbi_rows <- raw$damico$Conditioning_regimen == "EDX, FLUDARA, TBI"
          all(dm$conditioning_tbi[tbi_rows] == "1")
        })
  check("DAmico 'EDX, FLUDARA, TBI' row has conditioning_regimen == cy/flu (TBI stripped)",
        {
          tbi_rows <- raw$damico$Conditioning_regimen == "EDX, FLUDARA, TBI"
          all(dm$conditioning_regimen[tbi_rows] == "cy/flu")
        })
  check("DAmico non-TBI rows have conditioning_tbi == 0",
        {
          no_tbi <- !grepl("TBI", raw$damico$Conditioning_regimen)
          all(dm$conditioning_tbi[no_tbi] == "0")
        })
  check("DAmico conditioning_serotherapy is all NA",
        all(is.na(dm$conditioning_serotherapy)))

  # --- Fujimoto ---------------------------------------------------------------
  check("Fujimoto conditioning_intensity reproduces source Conditioning_Intensity",
        {
          src <- toupper(trimws(raw$fujimoto$Conditioning_Intensity))
          harm <- md$conditioning_intensity[md$study == study_labels[["fujimoto"]]]
          all(harm[src %in% c("MAC","RIC","NMA")] == src[src %in% c("MAC","RIC","NMA")])
        })
  check("Fujimoto conditioning_tbi == 1 where source Conditioning_TBI == yes",
        {
          yes_rows <- tolower(trimws(raw$fujimoto$Conditioning_TBI)) == "yes"
          all(fm$conditioning_tbi[yes_rows] == "1")
        })
  check("Fujimoto conditioning_tbi == 0 where source Conditioning_TBI == no",
        {
          no_rows <- tolower(trimws(raw$fujimoto$Conditioning_TBI)) == "no"
          all(fm$conditioning_tbi[no_rows] == "0")
        })

  # --- Ingham -----------------------------------------------------------------
  check("Ingham all documented samples (Myeloabl non-NA) are MAC",
        {
          doc <- !is.na(raw$ingham$Myeloabl)
          all(im$conditioning_intensity[doc] == "MAC")
        })
  check("Ingham undocumented sample has NA conditioning_intensity",
        all(is.na(im$conditioning_intensity[is.na(raw$ingham$Myeloabl)])))
  check("Ingham conditioning_tbi == 1 wherever TBI source == 1",
        {
          tbi1 <- !is.na(raw$ingham$TBI) & as.integer(raw$ingham$TBI) == 1L
          all(im$conditioning_tbi[tbi1] == "1")
        })
  check("Ingham conditioning_tbi recovered to 0 where TBI NA but Irrad == 0",
        {
          recovered <- is.na(raw$ingham$TBI) & !is.na(raw$ingham$Irrad) &
            as.integer(raw$ingham$Irrad) == 0L
          all(im$conditioning_tbi[recovered] == "0")
        })
  check("Ingham serotherapy == 1 wherever ATG or anti-CD10 administered",
        {
          sero_yes <- (!is.na(raw$ingham$X197ATGmm) & raw$ingham$X197ATGmm == 1) |
            (!is.na(raw$ingham$X10Ab)     & raw$ingham$X10Ab     == 1)
          all(im$conditioning_serotherapy[sero_yes] == "1")
        })
  check("Ingham conditioning_regimen contains no TBI or ATG tokens",
        !any(grepl("\\btbi\\b|\\batg\\b",
                   na.omit(im$conditioning_regimen), ignore.case = TRUE)))

  cat("\n  --- Ingham conditioning_regimen distribution ---\n")
  print(as.data.frame(
    dplyr::count(md[md$study == study_labels[["ingham"]], ],
                 conditioning_regimen, name = "n_samples")), row.names = FALSE)

  # --- Liu --------------------------------------------------------------------
  check("Liu High conditioning_intensity → MAC",
        {
          high <- grepl("high", tolower(raw$liu$conditioning_intensity))
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(lm$conditioning_intensity[high & !donor_flag] == "MAC")
        })
  check("Liu Intermediate conditioning_intensity → RIC",
        {
          inter <- grepl("intermediate", tolower(raw$liu$conditioning_intensity))
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(lm$conditioning_intensity[inter & !donor_flag] == "RIC")
        })
  check("Liu Low conditioning_intensity → NMA",
        {
          low <- grepl("low", tolower(raw$liu$conditioning_intensity))
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(lm$conditioning_intensity[low & !donor_flag] == "NMA")
        })
  check("Liu donor rows have NA conditioning columns",
        {
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(is.na(lm$conditioning_intensity[donor_flag])) &&
            all(is.na(lm$conditioning_regimen[donor_flag])) &&
            all(is.na(lm$conditioning_tbi[donor_flag])) &&
            all(is.na(lm$conditioning_serotherapy[donor_flag]))
        })
  check("Liu conditioning_regimen contains no TBI or ATG tokens",
        !any(grepl("\\btbi\\b|\\batg\\b",
                   na.omit(lm$conditioning_regimen), ignore.case = TRUE)))
  check("Liu ATG rows have conditioning_serotherapy == 1",
        {
          atg_rows <- grepl("\\bATG\\b", raw$liu$chemotherapy_regimen)
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(lm$conditioning_serotherapy[atg_rows & !donor_flag] == "1")
        })
  check("Liu TBI rows have conditioning_tbi == 1",
        {
          tbi_rows <- grepl("\\bTBI\\b", raw$liu$chemotherapy_regimen)
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(lm$conditioning_tbi[tbi_rows & !donor_flag] == "1")
        })

  cat("\n  --- Liu conditioning_regimen distribution ---\n")
  print(as.data.frame(
    dplyr::count(md[md$study == study_labels[["liu"]], ],
                 conditioning_regimen, name = "n_samples")), row.names = FALSE)

  # --- Vallet -----------------------------------------------------------------
  check("Vallet myeloablative → MAC",
        all(vm$conditioning_intensity[
              tolower(raw$vallet$conditioning) == "myeloablative"
            ] == "MAC"))
  check("Vallet non myeloablative → NMA",
        all(vm$conditioning_intensity[
              tolower(raw$vallet$conditioning) == "non myeloablative"
            ] == "NMA"))
  check("Vallet conditioning_intensity has no NAs",
        sum(is.na(vm$conditioning_intensity)) == 0)

  cat("\n  --- conditioning coverage by study ---\n")
  print(as.data.frame(qa$conditioning_coverage), row.names = FALSE)
  cat("\n  --- conditioning regimen strings by study ---\n")
  print(as.data.frame(qa$conditioning_regimen_by_study), row.names = FALSE)

  # ==========================================================================
  # Secondary post-transplant outcomes
  # ==========================================================================

  # --- QA tables --------------------------------------------------------------
  check("QA liu_bsi_unrecognized is empty (all source strings in lookup)",
        nrow(qa$liu_bsi_unrecognized) == 0)
  if (nrow(qa$liu_bsi_unrecognized) > 0) print(as.data.frame(qa$liu_bsi_unrecognized))

  check("QA invalid_binary_values remains empty after secondary outcome cols",
        nrow(qa$invalid_binary_values) == 0)

  # --- Artacho ----------------------------------------------------------------
  check("Artacho Myelosuppression=1 → myelosuppression='1'",
        all(am$myelosuppression[raw$artacho$Myelosuppression == 1] == "1"))
  check("Artacho Myelosuppression=0 → myelosuppression='0'",
        all(am$myelosuppression[raw$artacho$Myelosuppression == 0] == "0"))
  check("Artacho myelosuppression has no NAs",
        sum(is.na(am$myelosuppression)) == 0)
  check("Artacho Mucositis Yes → mucositis='1'",
        all(am$mucositis[raw$artacho$Mucositis == "Yes"] == "1"))
  check("Artacho Mucositis No → mucositis='0'",
        all(am$mucositis[raw$artacho$Mucositis == "No"] == "0"))
  check("Artacho mucositis has no NAs",
        sum(is.na(am$mucositis)) == 0)
  check("Artacho bloodstream_infection is all NA",
        all(is.na(am$bloodstream_infection)))
  check("Artacho bronchiolitis_obliterans is all NA",
        all(is.na(am$bronchiolitis_obliterans)))

  # --- DAmico -----------------------------------------------------------------
  check("DAmico Mucositis_grade I/II/III → mucositis='1'",
        {
          graded <- raw$damico$Mucositis_grade %in% c("I", "II", "III")
          all(dm$mucositis[graded] == "1")
        })
  check("DAmico Mucositis_grade '/' → mucositis='0'",
        all(dm$mucositis[raw$damico$Mucositis_grade %in% "/"] == "0"))
  check("DAmico Mucositis_grade NA → mucositis='0'",
        all(dm$mucositis[is.na(raw$damico$Mucositis_grade)] == "0"))
  check("DAmico mucositis count: 94 yes / 10 no",
        sum(dm$mucositis == "1") == 94 && sum(dm$mucositis == "0") == 10)
  check("DAmico BSI non-NA → bloodstream_infection='1'",
        all(dm$bloodstream_infection[!is.na(raw$damico$BSI)] == "1"))
  check("DAmico BSI NA → bloodstream_infection='0'",
        all(dm$bloodstream_infection[is.na(raw$damico$BSI)] == "0"))
  check("DAmico bloodstream_infection count: 39 yes / 65 no",
        sum(dm$bloodstream_infection == "1") == 39 &&
          sum(dm$bloodstream_infection == "0") == 65)
  check("DAmico myelosuppression is all NA",
        all(is.na(dm$myelosuppression)))
  check("DAmico bronchiolitis_obliterans is all NA",
        all(is.na(dm$bronchiolitis_obliterans)))

  # --- Fujimoto and Ingham: all four NA ---------------------------------------
  check("Fujimoto all four secondary outcome cols are all NA",
        all(is.na(fm$myelosuppression)) && all(is.na(fm$mucositis)) &&
          all(is.na(fm$bloodstream_infection)) &&
          all(is.na(fm$bronchiolitis_obliterans)))
  check("Ingham all four secondary outcome cols are all NA",
        all(is.na(im$myelosuppression)) && all(is.na(im$mucositis)) &&
          all(is.na(im$bloodstream_infection)) &&
          all(is.na(im$bronchiolitis_obliterans)))

  # --- Liu --------------------------------------------------------------------
  check("Liu donor rows have NA bloodstream_infection",
        {
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          all(is.na(lm$bloodstream_infection[donor_flag]))
        })
  check("Liu myelosuppression, mucositis, bronchiolitis_obliterans all NA",
        all(is.na(lm$myelosuppression)) && all(is.na(lm$mucositis)) &&
          all(is.na(lm$bronchiolitis_obliterans)))
  check("Liu col1 BSI=1 strings yield bloodstream_infection='1'",
        {
          bsi1_strings <- names(liu_bsi_col1_map)[liu_bsi_col1_map == "1"]
          rows <- raw$liu$infection_duringafter_transplant %in% bsi1_strings &
            tolower(raw$liu$donor_or_patient) == "patient"
          all(lm$bloodstream_infection[rows] == "1")
        })
  check("Liu col2 BSI=1 strings yield bloodstream_infection='1'",
        {
          bsi2_strings <- names(liu_bsi_col2_map)[liu_bsi_col2_map == "1"]
          rows <- raw$liu$infection_details %in% bsi2_strings &
            tolower(raw$liu$donor_or_patient) == "patient"
          all(lm$bloodstream_infection[rows] == "1")
        })
  check("Liu recipient rows with both fields NA/empty get bloodstream_infection='0'",
        {
          donor_flag <- tolower(raw$liu$donor_or_patient) == "donor"
          both_empty <- is.na(raw$liu$infection_duringafter_transplant) &
            is.na(raw$liu$infection_details)
          all(lm$bloodstream_infection[both_empty & !donor_flag] == "0")
        })

  cat("\n  --- Liu BSI crosswalk (col1) ---\n")
  cw <- qa$liu_bsi_crosswalk
  print(as.data.frame(cw[cw$column == "infection_duringafter_transplant", ]),
        row.names = FALSE)
  cat("\n  --- Liu BSI crosswalk (col2) ---\n")
  print(as.data.frame(cw[cw$column == "infection_details", ]),
        row.names = FALSE)

  # --- Vallet -----------------------------------------------------------------
  check("Vallet bos='yes' → bronchiolitis_obliterans='1'",
        {
          yes_rows <- !is.na(raw$vallet$bos) & tolower(raw$vallet$bos) == "yes"
          all(vm$bronchiolitis_obliterans[yes_rows] == "1")
        })
  check("Vallet bos=NA → bronchiolitis_obliterans='0'",
        all(vm$bronchiolitis_obliterans[is.na(raw$vallet$bos)] == "0"))
  check("Vallet bronchiolitis_obliterans count: 2 yes / 116 no",
        sum(vm$bronchiolitis_obliterans == "1") == 2 &&
          sum(vm$bronchiolitis_obliterans == "0") == 116)
  check("Vallet myelosuppression is all NA",
        all(is.na(vm$myelosuppression)))
  check("Vallet mucositis is all NA",
        all(is.na(vm$mucositis)))
  check("Vallet bloodstream_infection is all NA",
        all(is.na(vm$bloodstream_infection)))

  cat("\n  --- secondary outcomes coverage by study ---\n")
  print(as.data.frame(qa$secondary_outcomes_coverage), row.names = FALSE)

  cat("\n  --- outcome coverage by study ---\n")
  print(as.data.frame(qa$outcome_coverage), row.names = FALSE)
  cat("\n  --- end_observation coverage by study ---\n")
  print(as.data.frame(qa$end_observation_coverage), row.names = FALSE)
  cat("\n  --- timepoint by study ---\n")
  print(as.data.frame(qa$timepoint_by_study), row.names = FALSE)
}

cat(sprintf("\n%s (%d failure%s)\n",
            if (failures == 0L) "ALL TESTS PASSED" else "TESTS FAILED",
            failures, if (failures == 1L) "" else "s"))
if (failures > 0L) quit(status = 1L)
