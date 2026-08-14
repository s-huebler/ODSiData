library(readxl)
library(writexl)

path <- "/Users/sophiehuebler/Documents/ODSi/ODSiData/Merging/data_dictionaries.xlsx"

# Read all sheets
sheets <- excel_sheets(path)
all_data <- lapply(sheets, function(s) read_excel(path, sheet = s))
names(all_data) <- sheets

df <- all_data[["Artacho"]]

# ── Meanings (skip rows 1-4, already filled) ──────────────────────────────────

meanings <- c(
  # 5  Patient
  paste0("Study-assigned patient identifier (integer, 1\u2013105). One value per patient; ",
         "each patient contributes one pre- and one post-transplant sample row. ",
         "Not a clinical record number \u2014 assigned during data curation."),
  # 6  Timepoint_Class
  paste0("Categorical indicator of sampling timepoint relative to transplant. ",
         "Values: pre = sample collected before transplant; post = sample collected after transplant. ",
         "Derived from Library Name by regex extraction in Parsing_metadata.qmd."),
  # 7  Age
  paste0("Patient age at transplant, in decimal years (range 18.3\u201370.5). ",
         "Fractional values are consistent with computation from birth date and transplant date. ",
         "Units: years."),
  # 8  Gender
  "Patient sex/gender. Values: F = female; M = male.",
  # 9  Disease
  paste0("Primary hematological malignancy for which allogeneic stem cell transplantation was performed, ",
         "as an abbreviation. Values: ALL = acute lymphoblastic leukemia; AML = acute myeloid leukemia; ",
         "CML = chronic myeloid leukemia; HD = Hodgkin's disease; MDS = myelodysplastic syndrome; ",
         "MDS/MPS = myelodysplastic/myeloproliferative overlap syndrome; MM = multiple myeloma; ",
         "MPS = myeloproliferative syndrome; NHL = non-Hodgkin lymphoma; ",
         "SAL = secondary acute leukemia; OAL = other acute leukemia (inferred); ",
         "BMA = bone marrow aplasia / aplastic anemia (inferred)."),
  # 10 Type.of.tranplant
  paste0("Donor relationship and HLA matching for the stem cell transplant, as a numeric code ",
         "from the source clinical file (meta_clinical.xlsx). ",
         "Values: 2 = family member, HLA identical; 4 = family member, haploidentical; ",
         "5 = unrelated donor, HLA compatible; 6 = unrelated donor, HLA incompatible. ",
         "Decode key is defined in Parsing_metadata.qmd."),
  # 11 Transplant.source
  paste0("Source tissue of the stem cell graft, as a numeric code from the source clinical file. ",
         "Values: 1 = bone marrow (BM); 2 = umbilical cord blood (UC); ",
         "3 = peripheral blood stem cells (PBSC). Decode key defined in Parsing_metadata.qmd."),
  # 12 Myelosuppression
  paste0("Binary indicator of myelosuppression during the transplant course. ",
         "Values: 0 = absent; 1 = present."),
  # 13 Parenteral.Nutrition
  paste0("Binary indicator of whether the patient received total parenteral nutrition (TPN) ",
         "during the transplant course. Values: No = not received; Yes = received."),
  # 14 Mucositis
  paste0("Binary indicator of whether the patient developed mucositis ",
         "(inflammation and ulceration of mucous membranes, typically oral/gastrointestinal) ",
         "during the transplant course. Values: No = absent; Yes = present."),
  # 15 date.of.transplant
  paste0("Calendar date of stem cell infusion (day 0 of transplant). ",
         "Serves as the time origin for sample.pre, sample.post, and Timepoint. ",
         "Stored as ISO 8601 datetime with UTC timezone marker. ",
         "Range: 2013-11-26 to 2017-12-11."),
  # 16 sample.pre
  paste0("Day of pre-transplant sample collection relative to transplant date (day 0). ",
         "Negative values = days before transplant; 0 = day of transplant. ",
         "Range: \u221212 to 0 days. Units: days from transplant date. ",
         "For pre-transplant rows, Timepoint equals this value."),
  # 17 sample.post
  paste0("Day of post-transplant sample collection relative to transplant date (day 0). ",
         "Positive values = days after transplant. Range: 11 to 17 days. Units: days from transplant date. ",
         "NA for 35 of 105 patients (33%) who did not contribute a post-transplant sample. ",
         "For post-transplant rows, Timepoint equals this value."),
  # 18 Omic.analysis.pre
  paste0("Omics data types assayed on the pre-transplant sample, encoded as a period-delimited ",
         "combination string. Inferred key: A = 16S amplicon sequencing; S = metagenomic shotgun ",
         "sequencing; M = metabolomics. Codes combine additively ",
         "(e.g., A.S.M = amplicon + shotgun + metabolomics). ",
         "'A.' with trailing period appears to be a data-entry artifact equivalent to 'A'."),
  # 19 Omic.analysis.post
  paste0("Omics data types assayed on the post-transplant sample, encoded as a period-delimited ",
         "combination string. Inferred key: A = 16S amplicon sequencing; S = metagenomic shotgun ",
         "sequencing; M = metabolomics. 'A..M' (double period) appears to be a data-entry artifact ",
         "equivalent to 'A.M'. NA for 35 patients without a post-transplant sample."),
  # 20 GVHD_grade
  paste0("Overall (global) acute graft-versus-host disease severity grade, Glucksberg scale. ",
         "Values: 0 = no GVHD; 1 = grade I; 2 = grade II; 3 = grade III; 4 = grade IV. ",
         "Patient-level; likely reflects peak grade during observation."),
  # 21 gut_gvhd_grade
  paste0("Lower gastrointestinal (gut) acute GVHD organ-stage grade. ",
         "Organ-stage component of the overall Glucksberg acute GVHD grading. ",
         "Values: 0 = none; 1 = stage I; 2 = stage II; 3 = stage III; 4 = stage IV. ",
         "Renamed from LGI_GVHD_grade in Parsing_metadata.qmd."),
  # 22 skin_gvhd_grade
  paste0("Cutaneous (skin) acute GVHD organ-stage grade. ",
         "Organ-stage component of the overall Glucksberg acute GVHD grading. ",
         "Values: 0 = none; 1 = stage I; 2 = stage II; 3 = stage III (no stage IV in this dataset). ",
         "Renamed from Skin_GVHD_grade in Parsing_metadata.qmd."),
  # 23 liver_GVHD_grade
  paste0("Hepatic (liver) acute GVHD organ-stage grade. ",
         "Organ-stage component of the overall Glucksberg acute GVHD grading. ",
         "Values: 0 = none; 1 = stage I; 2 = stage II; 3 = stage III; 4 = stage IV. ",
         "Renamed from Liver_GVHD_grade in Parsing_metadata.qmd."),
  # 24 Donor_Type
  paste0("Donor relationship and HLA matching for the stem cell transplant, as a decoded label. ",
         "Values: 'Family, HLA identical' = HLA-matched sibling or family member; ",
         "'Family, Haplo identical' = haploidentical family member; ",
         "'Unrelated, HLA compatible' = matched unrelated donor (MUD); ",
         "'Unrelated, HLA incompatible' = mismatched unrelated donor (MMUD). ",
         "Derived by recoding Type.of.tranplant in Parsing_metadata.qmd."),
  # 25 Tranplant_Type
  paste0("Source tissue of the stem cell graft, as a decoded label. ",
         "Values: BM = bone marrow; PBSC = peripheral blood stem cells; UC = umbilical cord blood. ",
         "Derived by recoding Transplant.source in Parsing_metadata.qmd."),
  # 26 Timepoint
  paste0("Day of sample collection relative to transplant date (day 0). ",
         "Derived in Parsing_metadata.qmd: equals sample.pre for Timepoint_Class == 'pre'; ",
         "equals sample.post for Timepoint_Class == 'post'. ",
         "Negative = days before transplant; positive = days after; 0 = day of transplant. ",
         "Range: \u221212 to 17 days. Units: days from transplant date.")
)

# ── Notes ──────────────────────────────────────────────────────────────────────

notes <- c(
  # 5  Patient
  NA_character_,
  # 6  Timepoint_Class
  NA_character_,
  # 7  Age
  paste0("UNCERTAIN: age reference point not documented. ",
         "Basis: patient-level variable with fractional-year values consistent with ",
         "(transplant date \u2212 birth date) / 365.25; transplant date is the most likely reference. ",
         "Checked Parsing_metadata.qmd \u2014 column passed through from clinical source without annotation."),
  # 8  Gender
  NA_character_,
  # 9  Disease
  paste0("UNCERTAIN: codes OAL and BMA not defined in Parsing_metadata.qmd or available manuscript text. ",
         "Basis: OAL inferred as 'other acute leukemia' by analogy with SAL; ",
         "BMA inferred as 'bone marrow aplasia' (aplastic anemia) from Spanish hematology conventions ",
         "(this is a Spanish cohort, Valencia). ",
         "Checked Parsing_metadata.qmd \u2014 column renamed from 'Haematological malignency' ",
         "but values passed through without a decode key."),
  # 10 Type.of.tranplant
  paste0("Redundant with Donor_Type (col 24), which is the decoded string version created in Parsing_metadata.qmd. ",
         "Recommend keeping Donor_Type for harmonization as it is self-documenting; ",
         "this column retains the original numeric source codes. ",
         "Column name is misspelled ('tranplant') matching the source clinical file."),
  # 11 Transplant.source
  paste0("Redundant with Tranplant_Type (col 25), which is the decoded string version created in Parsing_metadata.qmd. ",
         "Recommend keeping Tranplant_Type for harmonization as it is self-documenting; ",
         "this column retains the original numeric source codes."),
  # 12 Myelosuppression
  paste0("UNCERTAIN: timing window (conditioning phase vs. post-transplant engraftment period) and ",
         "clinical threshold for classification not defined in source clinical file or Parsing_metadata.qmd. ",
         "Checked Parsing_metadata.qmd \u2014 column passed through without recoding or documentation."),
  # 13 Parenteral.Nutrition
  paste0("UNCERTAIN: timing window (which portion of the transplant course) not specified in source. ",
         "Checked Parsing_metadata.qmd \u2014 column passed through without modification."),
  # 14 Mucositis
  paste0("UNCERTAIN: timing and severity threshold for classification (any grade vs. grade \u22652?) ",
         "not specified in source clinical file or Parsing_metadata.qmd."),
  # 15 date.of.transplant
  NA_character_,
  # 16 sample.pre
  paste0("Paired patient-level variable. Together with sample.post, Omic.analysis.pre, and Omic.analysis.post, ",
         "this forms a four-column patient-level description of both longitudinal timepoints. ",
         "The sample-level equivalent is Timepoint (derived)."),
  # 17 sample.post
  paste0("35 patients (33%) have no post-transplant sample (NA). ",
         "Paired patient-level variable \u2014 see sample.pre notes."),
  # 18 Omic.analysis.pre
  paste0("UNCERTAIN: decode key (A, S, M) inferred from multimodal study design and paper title ",
         "('Multimodal analysis identifies microbiome changes...') but not explicitly defined in ",
         "source clinical file or Parsing_metadata.qmd. ",
         "'A.' (trailing period) is likely a data-entry artifact of 'A' alone. ",
         "Part of the pre/post paired omic-analysis column group (see sample.pre notes)."),
  # 19 Omic.analysis.post
  paste0("UNCERTAIN: same decode uncertainty as Omic.analysis.pre. ",
         "'A..M' (double period) is likely a data-entry artifact equivalent to 'A.M'. ",
         "Paired with Omic.analysis.pre."),
  # 20 GVHD_grade
  paste0("UNCERTAIN: whether grade reflects peak, discharge assessment, or a specific timepoint is not ",
         "stated in the source clinical file. Acute GVHD is the most likely context given the ",
         "short post-transplant sampling window (days 11\u201317). ",
         "Checked Parsing_metadata.qmd \u2014 column passed through unchanged from clinical source."),
  # 21 gut_gvhd_grade
  paste0("UNCERTAIN: exact organ-staging criteria and whether stage maps 1:1 to grade ",
         "not confirmed from source. Glucksberg staging assumed based on study context."),
  # 22 skin_gvhd_grade
  paste0("UNCERTAIN: exact organ-staging criteria not confirmed from source. ",
         "Glucksberg staging assumed. No stage IV observed in this dataset."),
  # 23 liver_GVHD_grade
  paste0("UNCERTAIN: exact organ-staging criteria (bilirubin thresholds) not confirmed from source. ",
         "Glucksberg staging assumed based on study context."),
  # 24 Donor_Type
  paste0("Redundant with Type.of.tranplant (col 10), which contains the original numeric codes. ",
         "Recommend keeping this column for harmonization as it is self-documenting. ",
         "Column name for col 25 (Tranplant_Type) shares the same 'tranplant' misspelling."),
  # 25 Tranplant_Type
  paste0("Redundant with Transplant.source (col 11), which contains the original numeric codes. ",
         "Recommend keeping this column for harmonization as it is self-documenting. ",
         "Column name misspelled ('Tranplant') matching source clinical file."),
  # 26 Timepoint
  paste0("Sample-level derived variable combining sample.pre and sample.post via Timepoint_Class. ",
         "This is the primary sample-level time variable for analysis.")
)

stopifnot(length(meanings) == 22L, length(notes) == 22L)

# Fill rows 5-26 (index 5:26) — leave rows 1-4 untouched
df$meaning[5:26] <- meanings
df$notes[5:26]   <- notes

all_data[["Artacho"]] <- df
write_xlsx(all_data, path)
message("Done. Wrote ", nrow(df), " rows to Artacho sheet.")
