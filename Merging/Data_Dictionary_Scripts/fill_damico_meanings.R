
# fill_damico_meanings.R
#
# Writes meaning (col 8) and notes (col 11) into the DAmico sheet of
# data_dictionaries.xlsx using readxl + writexl.  Only fills rows where
# meaning is currently empty/NA.  Keyed by column_name (col 1).
#
# Sources used (in priority order):
#   1. DAmico2019/Metadata/Parsing_metadata.qmd — derivation logic
#   2. DAmico2019/Manuscript/Manuscript.pdf + Supplementary Table 2 — clinical definitions
#   3. DAmico2019/Metadata/Raw_metadata/meta_clinical.csv — raw column names and values
#   4. DAmico2019/Metadata/damico_meta_qiime.tsv — full value distributions

library(readxl)
library(writexl)

FILE_PATH  <- "Merging/data_dictionaries.xlsx"
SHEET_NAME <- "DAmico"

# ---------------------------------------------------------------------------
# Meanings dictionary
# ---------------------------------------------------------------------------

MEANINGS <- list(

  # ---- SRA technical fields ------------------------------------------------

  "AvgSpotLen" = list(
    meaning = "Average sequencing spot (paired-end insert) length in base pairs, as reported by SRA. For this study, paired-end 16S amplicon reads; observed range 444–464 bp.",
    notes   = "SRA-generated technical field; not a study variable. Redundant with LibraryLayout (PAIRED) and Instrument (Illumina MiSeq) for characterising the sequencing run."
  ),

  "DATASTORE filetype" = list(
    meaning = "Comma-separated list of file formats available for download from the SRA DataStore for this run. Values observed: combinations of fastq, sra, and run.zq.",
    notes   = "SRA infrastructure field; not a study variable. Order of formats within the string varies by row (same formats, different precedence)."
  ),

  "DATASTORE provider" = list(
    meaning = "Comma-separated list of cloud/hosting providers where the SRA data files are stored. Values: ncbi (NCBI FTP), s3 (AWS S3), gs (Google Cloud Storage).",
    notes   = "SRA infrastructure field; not a study variable."
  ),

  "DATASTORE region" = list(
    meaning = "Comma-separated list of specific storage regions corresponding to each provider in DATASTORE provider. Values: s3.us-east-1, gs.us-east1, ncbi.public.",
    notes   = "SRA infrastructure field; not a study variable."
  ),

  "ReleaseDate" = list(
    meaning = "Date and time (UTC) when the SRA run record was made publicly available. All runs released 2019-12-03.",
    notes   = "SRA-generated administrative field; not a study variable."
  ),

  "create_date" = list(
    meaning = "Date and time (UTC) when the SRA run record was created/submitted. All records created 2019-12-02 17:02:00 UTC.",
    notes   = "SRA-generated administrative field; not a study variable. Redundant with ReleaseDate for distinguishing sample timing."
  ),

  # ---- Derived parsing variables -------------------------------------------

  "Patient" = list(
    meaning = "Study patient identifier, extracted from HostID in Parsing_metadata.qmd (regex: letter + digits after the first character). Values: E1–E10 = enteral nutrition (EN) group; P1–P10 = parenteral nutrition (PN) group. One patient may contribute multiple samples across timepoints.",
    notes   = NA_character_
  ),

  "second_num" = list(
    meaning = "Second numeric sequence extracted from HostID during parsing (e.g., 'BP5P74' -> 74; 'BE1P68' -> 68). For non-PRE samples this equals the raw day-from-transplant encoded in the SRA sample label.",
    notes   = "Intermediate parsing variable — opaque to downstream users. Redundant with Timepoint for non-PRE samples. For PRE samples, second_num is absent (HostID contains 'PRE' with no second number) and Timepoint is filled instead with a per-patient estimated pre-transplant day. Prefer Timepoint for analysis; second_num is retained as audit trail."
  ),

  "Timepoint" = list(
    meaning = "Days from transplant to stool sample collection (day 0 = transplant date). Negative values = pre-transplant. For samples labelled 'PRE' in HostID, Timepoint is substituted with a per-patient estimated pre-transplant day (range –18 to –1.5) derived from study design in Parsing_metadata.qmd; for all other samples, Timepoint = second_num.",
    notes   = NA_character_
  ),

  # ---- Clinical variables from meta_clinical.csv ---------------------------

  "Nutritional_Regimen" = list(
    meaning = "Assigned post-transplant nutritional support regimen and its window. Format: 'TYPE (+start/+end)' where TYPE is EN (enteral nutrition, administered via nasogastric tube) or PN (parenteral nutrition, administered intravenously), and start/end are days relative to transplant day 0. E.g., 'EN (+0/+18)' = enteral from day 0 through day +18. Some patients had sequential EN then PN regimens (semicolon-separated). This is the primary study intervention (RCT allocation).",
    notes   = "Study randomisation variable — the two arms of the trial are EN vs PN. Patients with mixed regimens (e.g., 'EN (+1/+10); PN (+10/+13)') crossed over mid-course. The E/P prefix in Patient IDs encodes the primary assignment: E = EN arm, P = PN arm."
  ),

  "Sex" = list(
    meaning = "Patient biological sex. F = female, M = male.",
    notes   = NA_character_
  ),

  "Age" = list(
    meaning = "Patient age in years (integer) at time of transplant. Pediatric cohort; range 1–18 years.",
    notes   = "UNCERTAIN: manuscript states 'Sex/Age(yr)' in Supplementary Table 2 but does not explicitly say 'age at transplant' vs 'age at diagnosis'. Inferred as age at transplant from study context (all patients characterised at time of HSCT enrolment)."
  ),

  "Diagnosis" = list(
    meaning = "Primary hematologic or non-malignant diagnosis for which HSCT was performed. Values from manuscript Supplementary Table 2: ALL B = B-cell acute lymphoblastic leukemia; ALL T = T-cell acute lymphoblastic leukemia; AML = acute myeloid leukemia; CGD = chronic granulomatous disease; HLH = hemophagocytic lymphohistiocytosis; JMML = juvenile myelomonocytic leukemia; MDS = myelodysplastic syndrome; RCC = refractory cytopenia of childhood (pediatric MDS variant); TM = thalassemia major.",
    notes   = NA_character_
  ),

  "Donor_Type" = list(
    meaning = "HLA match category and donor relationship. Values and definitions from manuscript Supplementary Table 2 footnote: MFD = Matched Familiar (related) Donor; MMFD = Mismatched Familiar (related) Donor; MMUD = Mismatched Unrelated Donor; MUD = Matched Unrelated Donor; Haploidentical = 5/10 HLA-matched related donor (not expanded in manuscript footnote, standard usage).",
    notes   = "UNCERTAIN: 'Haploidentical' definition (5/10 vs 6/10 HLA match) not explicitly stated in the manuscript — standard haploidentical definition (one haplotype shared, ~5/10 match) assumed."
  ),

  "Stem_cell_source" = list(
    meaning = "Source of hematopoietic stem cells. From manuscript: BM = bone marrow; PBSC = peripheral blood stem cells. All patients except E2 and P9 received BM grafts.",
    notes   = NA_character_
  ),

  "Conditioning_regimen" = list(
    meaning = "Myeloablative conditioning regimen as a comma-separated list of drug abbreviations. From manuscript Supplementary Table 2 footnote: BU = busulfan; TT = thiotepa; FLUDARA = fludarabine; TREO = treosulfan; EDX = cyclophosphamide (endoxan); L-PAM = melphalan; TBI = total body irradiation. Observed regimens: BU+TT+FLUDARA, BU+TT+EDX, BU+EDX+L-PAM, TREO+TT+FLUDARA, TREO+TT+EDX, EDX+FLUDARA+TBI.",
    notes   = NA_character_
  ),

  "PMN_day" = list(
    meaning = "Day from transplant (day 0) to neutrophil (PMN = polymorphonuclear) engraftment. From manuscript: 'PMN = Polymorphonuclear Neutrophil'. Observed range: 11–29 days.",
    notes   = "UNCERTAIN: the ANC engraftment threshold is not stated in the manuscript or Supplementary Table 2. The standard HSCT definition (ANC >= 0.5x10^9/L on 3 consecutive days) is assumed but not confirmed in this paper."
  ),

  "PLT_over_20000_day" = list(
    meaning = "Day from transplant (day 0) when platelet count first exceeded 20,000/uL without transfusion support. Threshold (>20,000) is encoded in the column name and confirmed by the manuscript column header 'PLT > 20000 (day)'. Missing (n=4) for patients who did not reach this milestone within the observation window (E10 missing; 3 others).",
    notes   = NA_character_
  ),

  "Skin_gvhd_grade" = list(
    meaning = "Acute GVHD skin organ stage, 0–3. From manuscript Supplementary Table 2: 0 = no skin involvement; 1–3 = increasing severity using '+' notation ('+' = 1, '++' = 2, '+++' = 3). Standard Glucksberg skin staging: 1 = rash <25% BSA; 2 = rash 25–50% BSA; 3 = generalized erythroderma >50% BSA.",
    notes   = "UNCERTAIN: manuscript states severity is 'from 1 to 4' per organ but maximum observed skin stage is 3 (no patient had stage 4 skin). Standard Glucksberg skin stage 4 (desquamation/bullae) would be '++++'; absent here. The paper does not cite Glucksberg by name — staging criteria assumed from standard aGVHD literature. One of three organ-specific aGVHD stage columns (see also gut_gvhd_grade, liver_gvhd_grade); together they determine overall Glucksberg grade."
  ),

  "gut_gvhd_grade" = list(
    meaning = "Acute GVHD gut (gastrointestinal) organ stage, 0–4. From manuscript: 0 = no GI involvement; 1–4 = increasing GI severity. Standard Glucksberg gut staging: 1 = diarrhea 500–1000 mL/day; 2 = diarrhea 1000–1500 mL/day; 3 = diarrhea >1500 mL/day; 4 = severe abdominal pain ± ileus.",
    notes   = "UNCERTAIN: paper does not explicitly define Glucksberg gut thresholds — standard staging assumed. One of three organ-specific aGVHD stage columns (see also Skin_gvhd_grade, liver_gvhd_grade)."
  ),

  "liver_gvhd_grade" = list(
    meaning = "Acute GVHD liver organ stage, 0–3 (observed range). From manuscript: 0 = no liver involvement; 1–3 = increasing bilirubin elevation. Standard Glucksberg liver staging: 1 = bilirubin 2–3 mg/dL; 2 = bilirubin 3–6 mg/dL; 3 = bilirubin 6–15 mg/dL; 4 = bilirubin >15 mg/dL (stage 4 not observed in this dataset).",
    notes   = "UNCERTAIN: paper does not explicitly define Glucksberg liver thresholds — standard staging assumed. One of three organ-specific aGVHD stage columns (see also Skin_gvhd_grade, gut_gvhd_grade)."
  ),

  "gvhd_day" = list(
    meaning = "Day from transplant (day 0) to onset of acute GVHD. Integer; positive (GVHD always occurs post-transplant). From manuscript Supplementary Table 2 column header 'Day'. Observed range: 14–60 days. Missing (n=45) for patients without aGVHD (i.e., all three organ stages = 0).",
    notes   = NA_character_
  ),

  "gvhd_steroid_resistant" = list(
    meaning = "Whether acute GVHD was steroid-resistant. From manuscript Supplementary Table 2 footnote: y = yes (steroid-resistant aGVHD); n = no (steroid-sensitive aGVHD). Missing (n=45) for patients without aGVHD.",
    notes   = NA_character_
  ),

  "Mucositis_grade" = list(
    meaning = "Clinical grade of oral/GI mucositis during conditioning and early post-transplant period. Values observed: I = mild; II = moderate; III = severe; / = not assessed or not graded (5 patients use this symbol); NA (5 patients). The grading system (WHO or NCI-CTCAE) is not stated in the manuscript.",
    notes   = "UNCERTAIN: '/' is not defined in the manuscript or Supplementary Table 2 footnote. Likely means 'not assessed' or 'data unavailable' rather than grade 0 (no mucositis), based on context — patients with no mucositis are expected to receive a grade 0 designation, not a slash. Treat '/' as NA for analysis. Grading scale (WHO vs NCI-CTCAE) not specified in paper."
  ),

  "BSI" = list(
    meaning = "Bloodstream infection(s) (bacteremia) occurring during the early post-transplant period. From manuscript Supplementary Table 2: free text with organism name and day of event in parentheses, e.g., 'S.aureus (+7)'. Multiple BSI events separated by semicolons. NA = no BSI documented. Per the manuscript, all BSI events occurred in the PN group (patients P1–P10); the EN group (E1–E10) had zero events.",
    notes   = NA_character_
  ),

  "Outcome_at_100" = list(
    meaning = "Patient vital status at day +100 post-transplant. From manuscript Supplementary Table 2 footnote: a = alive; d = deceased. Observed: 99 alive, 5 deceased across all samples (patient P6, F/1 yr, ALL B, MMUD, was the only death in this study).",
    notes   = NA_character_
  )
)

# ---------------------------------------------------------------------------
# Read all sheets
# ---------------------------------------------------------------------------

all_sheets  <- readxl::excel_sheets(FILE_PATH)
sheets_data <- lapply(all_sheets, function(s) readxl::read_excel(FILE_PATH, sheet = s))
names(sheets_data) <- all_sheets

# ---------------------------------------------------------------------------
# Modify the DAmico sheet
# ---------------------------------------------------------------------------

df <- sheets_data[[SHEET_NAME]]

updated          <- 0L
skipped_nonempty <- 0L
skipped_notfound <- 0L
matched_keys     <- character(0)

for (i in seq_len(nrow(df))) {
  col_name <- df$column_name[i]
  if (is.na(col_name)) next

  if (!col_name %in% names(MEANINGS)) {
    skipped_notfound <- skipped_notfound + 1L
    next
  }

  matched_keys <- c(matched_keys, col_name)

  current_meaning <- df$meaning[i]
  if (!is.na(current_meaning) && nzchar(trimws(current_meaning))) {
    skipped_nonempty <- skipped_nonempty + 1L
    next
  }

  entry         <- MEANINGS[[col_name]]
  df$meaning[i] <- entry$meaning
  df$notes[i]   <- entry$notes
  updated       <- updated + 1L
}

sheets_data[[SHEET_NAME]] <- df

# ---------------------------------------------------------------------------
# Write back
# ---------------------------------------------------------------------------

writexl::write_xlsx(sheets_data, FILE_PATH)

cat("Done. Rows updated:", updated, "\n")
cat("      Rows skipped (meaning already present):", skipped_nonempty, "\n")
cat("      Rows skipped (column_name not in MEANINGS):", skipped_notfound, "\n")

unmatched_keys <- setdiff(names(MEANINGS), matched_keys)
if (length(unmatched_keys) > 0) {
  cat("\nWARNING: these keys in MEANINGS were not found in the sheet:\n")
  cat(paste("  ", sort(unmatched_keys), collapse = "\n"), "\n")
} else {
  cat("\nAll MEANINGS keys matched a row in the sheet.\n")
}
