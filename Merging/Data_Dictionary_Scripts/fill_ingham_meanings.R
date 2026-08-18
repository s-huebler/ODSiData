
# fill_ingham_meanings.R
#
# Writes meaning (col 8) and notes (col 11) into the Ingham sheet of
# data_dictionaries.xlsx using readxl + writexl.  Only fills rows where
# meaning is currently empty/NA.  Keyed by column_name (col 1).
#
# Corrections vs update_ingham_meanings.py:
#   - CMVab: coding confirmed from Explanation_of_data.docx (1=positive,
#     2=negative, 3=inconclusive); UNCERTAIN flag removed.
#   - cause_of_death: legend corrected from docx (10=graft rejection/failure,
#     22=fungal infection, 60=chronic GvHD [not seen in data], 70=primary
#     disease recurrence, 900=other).
#   - DX: docx note added ("malignant disease codes <300 and >=700").
#   - Sens.death.0.: docx confirms same encoding as Alive (1=alive, 0=dead),
#     supporting the Python script's interpretation.

library(readxl)
library(writexl)

FILE_PATH <- "Merging/data_dictionaries.xlsx"
SHEET_NAME <- "Ingham"

# ---------------------------------------------------------------------------
# Meanings dictionary — one named list per column_name
# Each element has $meaning (character) and $notes (character or NA)
# ---------------------------------------------------------------------------

MEANINGS <- list(

  "patient" = list(
    meaning = "Study-specific patient identifier (P01–P30); one patient may contribute multiple samples across timepoints.",
    notes   = NA_character_
  ),

  "timepoint" = list(
    meaning = "Days from transplant to stool sample collection (day 0 = transplant date). Integer; negative = pre-transplant. Renamed from days_posttransplant.",
    notes   = NA_character_
  ),

  "sampling_date" = list(
    meaning = "Calendar date of stool sample collection (dd-mm-yyyy).",
    notes   = NA_character_
  ),

  "transplant_date" = list(
    meaning = "Calendar date of allogeneic stem cell transplant/BMT (dd-mm-yyyy). This is the time origin (day 0) for the timepoint column. Renamed from Date.of.BMT..dd.mm.yyyy.",
    notes   = NA_character_
  ),

  "BMT.No" = list(
    meaning = "Transplant number for this patient: 1 = first allogeneic transplant, 2 = second allogeneic transplant. From Explanation_of_data.docx: 'Bone marrow transplantation number (received by that patient)'.",
    notes   = "UNCERTAIN: confirmed as transplant number per docx, but docx does not state explicitly that 1=first and 2=second; inferred from values (only 1 and 2 present, 5 patients with value 2)."
  ),

  "DX" = list(
    meaning = "Numeric IBMTR disease code for the primary diagnosis. Docx notes: 'Malignant disease are diagnoses <300 and >=700'. Text labels are in the disease column.",
    notes   = "Redundant with disease (numeric code vs text label). Prefer disease for harmonisation. UNCERTAIN: full IBMTR code table not reproduced in manuscript or docx; individual codes inferred from paired disease text (e.g. DX=14 -> AMML, DX=24 -> cALL, DX=300 -> aplastic anaemia)."
  ),

  "disease" = list(
    meaning = "Full IBMTR disease name for the primary diagnosis (free text from registry). E.g. 'cALL (pre-B)', 'Severe aplastic anemia', 'AML or ANLL, not otherwise specified'. Renamed from DiseaseNameIBMTR.",
    notes   = "Redundant with DX (text version of the same code). Prefer this column over DX for harmonisation because the text is self-documenting."
  ),

  "diagnosis_date" = list(
    meaning = "Calendar date of initial diagnosis (dd-mm-yyyy). Renamed from Date.of.diagnosis..dd.mm.yyyy.",
    notes   = NA_character_
  ),

  "Donor.sex" = list(
    meaning = "Donor sex (integer coded). By analogy with Sex (1=male, 2=female used in Parsing_metadata.qmd): 1 = male, 2 = female.",
    notes   = "UNCERTAIN: coding 1=male/2=female is inferred from the Sex recoding in Parsing_metadata.qmd (case_when(Sex==1~'male', Sex==2~'female')). Donor.sex is not independently recoded in the script; manuscript and docx do not give an explicit legend for Donor.sex."
  ),

  "age" = list(
    meaning = "Recipient (patient) age at transplant in decimal years. From docx: 'Recipient age in years at the time of transplantation'. Renamed from Rec.age.in.y.",
    notes   = NA_character_
  ),

  "weight" = list(
    meaning = "Patient body weight in kg (integer values observed). Reference point is pre-transplant (at time of conditioning).",
    notes   = "UNCERTAIN: timepoint of weight measurement (pre-conditioning vs. transplant day) not stated explicitly in the manuscript or docx. Inferred as pre-transplant from registry context. Renamed from Weight."
  ),

  "Donor.age.in.y" = list(
    meaning = "Donor age at time of donation in decimal years.",
    notes   = NA_character_
  ),

  "Bone.marrow" = list(
    meaning = "One-hot indicator: 1 = graft source is bone marrow (BM), 0 = not BM. Part of a one-hot graft-source group.",
    notes   = "One-hot group: Bone.marrow / Peripheral.blood / Ubilical.cord encode a single underlying variable transplant_type. One patient (ERR2666891, P12) has both Bone.marrow=1 and Ubilical.cord=1, coded as BM_UC in transplant_type. Keep transplant_type for harmonisation; these three columns are the raw source."
  ),

  "Peripheral.blood" = list(
    meaning = "One-hot indicator: 1 = graft source is peripheral blood stem cells (PBSC), 0 = not PBSC. Part of a one-hot graft-source group.",
    notes   = "One-hot group: see Bone.marrow notes. Underlying variable: transplant_type."
  ),

  "Ubilical.cord" = list(
    meaning = "One-hot indicator: 1 = graft source is umbilical cord blood (UC), 0 = not UC. Part of a one-hot graft-source group. Column name misspells 'umbilical' as 'ubilical' — preserved from original data.",
    notes   = "One-hot group: see Bone.marrow notes. Underlying variable: transplant_type."
  ),

  "match" = list(
    meaning = "Donor-recipient HLA match classification. Values: matched_unrelated = fully HLA-matched unrelated donor; sibling_donor = HLA-identical sibling; 1HLA_mismatch = 1 antigen/allele mismatch; 2HLA_mismatch = 2 antigen/allele mismatches. Renamed from DonorMatch.",
    notes   = NA_character_
  ),

  "donor" = list(
    meaning = "Donor type. Values: unrelated = volunteer unrelated donor; sibling = related sibling donor. Renamed from Donor.",
    notes   = NA_character_
  ),

  "CMVab" = list(
    meaning = "Recipient's cytomegalovirus (CMV) antibody status. From Explanation_of_data.docx: 1 = positive, 2 = negative, 3 = inconclusive. Observed counts: 1=43, 2=39, 3=14.",
    notes   = NA_character_
  ),

  "agvhd" = list(
    meaning = "Binary indicator: acute GVHD occurred. 0 = no aGVHD, 1 = aGVHD occurred. Derived from EBMT field X541GVHDoccur (renamed from GVHDoccur).",
    notes   = NA_character_
  ),

  "agvhd_grade" = list(
    meaning = "Maximum acute GVHD grade (Glucksberg scale 0-IV). 0 = no aGVHD; 1 = grade I; 2 = grade II; 3 = grade III; 4 = grade IV. From docx: 'MaxAGVHD: Maximum aGVHD grade'. Derived from EBMT field X542MaxAGVHD.",
    notes   = NA_character_
  ),

  "agvhd_date" = list(
    meaning = "Calendar date of acute GVHD onset (dd-mm-yyyy). Missing for patients without aGVHD. From docx field GvHDOnsetDate (X549Date in additional export). Derived from EBMT field X549Date.",
    notes   = NA_character_
  ),

  "cause_of_death" = list(
    meaning = "Coded primary cause of death. From Explanation_of_data.docx: 10 = Graft rejection or failure; 22 = Fungal infection; 60 = Chronic GvHD; 70 = Recurrence or persistence of primary disease; 900 = Other. Observed in data: 10 (n=3), 22 (n=1), 70 (n=14), 900 (n=5); code 60 not observed. Missing = 74 (alive or censored). Derived from Primary.cause.of.death.",
    notes   = "Code 60 (Chronic GvHD) is in the docx legend but not observed in this dataset. Verified against Explanation_of_data.docx."
  ),

  "tte_death" = list(
    meaning = "Time from transplant (day 0) to death or last follow-up (days). Event = death (see death column). Censored observations have tte_death equal to administrative follow-up time. From docx: 'Days from transplantation to death'. Derived from EBMT field X.Alle..Survival.all.patients..to.death._Surv.",
    notes   = NA_character_
  ),

  "Sens.death.0." = list(
    meaning = "Overall survival censoring indicator (complement of death). From docx: 1 = alive, 0 = dead. Equivalent to the original Alive...1.yes..0.no. column; same coding, preserved by a double-negative in select() in Parsing_metadata.qmd.",
    notes   = "Redundant with death (which = 1 - Alive...1.yes..0.no. = 0 where Sens.death.0.=1 and vice versa). The Parsing_metadata.qmd select(-c(..., -Sens.death.0.)) is a double-negative that accidentally preserved the column when the intent was to drop it. Prefer death for harmonisation. UNCERTAIN: the double-negative in select() is ambiguous — confirm intended behaviour."
  ),

  "tte_tx_death" = list(
    meaning = "Time from transplant (day 0) to treatment-related death (death in remission) or competing-event censoring (days). Event = tx_death. Competing events (relapse) are censored at the time of the competing event. From docx: 'Days from transplantation to treatment-related death'. Derived from EBMT field X.Alle..Death.in.remiss_Surv.",
    notes   = NA_character_
  ),

  "tte_relapse" = list(
    meaning = "Time from transplant (day 0) to relapse or competing-event censoring (days). Event = relapse. Competing events (treatment-related death) are censored at the time of the competing event. From docx: 'Days from transplantation to treatment-related death or relapse'. Derived from EBMT field X.Alle..Relapse_Surv.",
    notes   = NA_character_
  ),

  "censor" = list(
    meaning = "Administrative censoring time: days from transplant to database closure or end of observation window. From docx: 'Days of survival from transplantation to time point of data extraction'. This is the maximum observable follow-up time for each patient, irrespective of event status. Renamed from Surv.to.now.",
    notes   = "Not the time-to-event for any specific outcome — it is the ceiling follow-up time applied across all endpoints. For alive patients, tte_death = censor."
  ),

  "Cell.dose.kg" = list(
    meaning = "Infused cell dose per kg recipient body weight. From docx: 'Number of cells received / recipient's body weight'. Unit (x10^6/kg or x10^8/kg) not stated.",
    notes   = "UNCERTAIN: numerator cell type (total mononuclear cells, CD34+ cells, or nucleated cells) and exact unit (x10^6/kg vs x10^8/kg) not stated in raw data headers, docx, or manuscript methods."
  ),

  "Irrad" = list(
    meaning = "Binary indicator: irradiation was included in the conditioning regimen. From docx: 'Irrad: Irradiation'. 0 = no irradiation, 1 = irradiation given.",
    notes   = NA_character_
  ),

  "TBI" = list(
    meaning = "Binary indicator: total body irradiation (TBI) specifically was used in conditioning. From docx: 'TBI: Total Body Irradiation'. 0 = no TBI, 1 = TBI given. Subset of Irrad.",
    notes   = NA_character_
  ),

  "Total.dose.of.TBI.in.cGy" = list(
    meaning = "Total TBI dose in centigray (cGy). Missing for patients who did not receive TBI.",
    notes   = NA_character_
  ),

  "FracTBI" = list(
    meaning = "Binary indicator: TBI was delivered as fractionated (split) doses. From docx: 'FracTBI: Treated with fractional TBI or not'. 1 = fractionated TBI; 0 = single-fraction TBI.",
    notes   = NA_character_
  ),

  "Dose.frac" = list(
    meaning = "Dose per TBI fraction in centigray (cGy). From docx: 'Dose.frac: Dose of fractional irradiation in cGy'. Missing for patients who did not receive fractionated TBI.",
    notes   = NA_character_
  ),

  "X197ATGmm" = list(
    meaning = "Binary indicator: anti-thymocyte globulin (ATG) was included in the conditioning regimen. From docx: 'ATGmm: Anti-thymocyte globulin treatment as part of the conditioning (or not)'. 0 = no ATG, 1 = ATG given. Original column ATGmm in Data_matrix_37_patients.txt; prefixed X197 from EBMT ProMISe field numbering in the additional export.",
    notes   = "UNCERTAIN: the 'mm' suffix in ATGmm is unexplained — may denote route, formulation (e.g. Micromet), or be an artefact of the EBMT field code. Exact EBMT field 197 definition not confirmed; docx gives the binary interpretation but does not explain 'mm'."
  ),

  "X233Bu" = list(
    meaning = "Busulfan (Bu) use in conditioning. From docx: 'Bu: Busulfan treatment (or not)'. Original column Bu in Data_matrix_37_patients.txt; EBMT field 233 in the additional export. Observed values: 0 = no busulfan (n=43); 1 = busulfan given, likely IV route (n=47); 2 = busulfan given, likely oral route or alternative dose tier (n=5).",
    notes   = "UNCERTAIN: docx describes Bu as binary ('or not') but three levels (0, 1, 2) are observed. The two non-zero levels likely encode route (IV vs oral) or dose tier; coding not confirmed in docx or manuscript. Needs EBMT ProMISe codebook lookup."
  ),

  "Total.dose.Busulfan..mg." = list(
    meaning = "Total busulfan dose in mg administered as part of conditioning. Missing for patients not receiving busulfan.",
    notes   = NA_character_
  ),

  "X270Cyclo" = list(
    meaning = "Binary indicator: cyclophosphamide (Cyclo) included in conditioning. From docx: 'Cyclo: Cyclophosphamide treatment (or not)'. Original column Cyclo in Data_matrix_37_patients.txt; EBMT field 270. 0 = no cyclophosphamide, 1 = cyclophosphamide given.",
    notes   = NA_character_
  ),

  "Total.dose.cyclophosphamide..mg." = list(
    meaning = "Total cyclophosphamide dose in mg administered as part of conditioning. Missing for patients not receiving cyclophosphamide.",
    notes   = NA_character_
  ),

  "Total.dose.VP16..mg." = list(
    meaning = "Total etoposide (VP-16) dose in mg administered as part of conditioning. Missing for patients not receiving etoposide.",
    notes   = NA_character_
  ),

  "Total.dose.melphalan..mg." = list(
    meaning = "Total melphalan dose in mg administered as part of conditioning. Missing for patients not receiving melphalan.",
    notes   = NA_character_
  ),

  "X284.2Fludarab" = list(
    meaning = "Binary indicator: fludarabine included in conditioning. From docx: 'Fludarab: Fludarabine-based treatment (or not)'. Original column Fludarab in Data_matrix_37_patients.txt; EBMT field 284.2. 0 = no fludarabine, 1 = fludarabine given.",
    notes   = NA_character_
  ),

  "X284.3TotalDose" = list(
    meaning = "Total fludarabine dose in mg as part of conditioning. Original column TotalDoseFludarab in Data_matrix_37_patients.txt; EBMT field 284.3. Missing for patients not receiving fludarabine.",
    notes   = "UNCERTAIN: unit (mg or mg/m2) not specified in raw headers, docx, or manuscript methods. Inferred as mg from column name pattern matching Total.dose.Busulfan..mg. etc."
  ),

  "X10Ab" = list(
    meaning = "Binary indicator: antibody-based conditioning agent included (e.g. Alemtuzumab/Campath or Rituximab). EBMT field 10; 'Ab' suffix = antibody. 0 = not given, 1 = given.",
    notes   = "UNCERTAIN: specific antibody not identified. Not present in Data_matrix_37_patients.txt (only in the 30-patient additional EBMT export). Checked manuscript methods and Explanation_of_data.docx — no explicit mention of EBMT field 10. Needs EBMT ProMISe codebook lookup."
  ),

  "Karnofsky.bef.condt" = list(
    meaning = "Karnofsky performance status score before start of conditioning. From docx: 'Recipient's Karnofsky score before conditioning'. Scale 0-100 in 10-point increments; 100 = fully normal function, 0 = dead. Observed values: 50, 80, 90, 100.",
    notes   = NA_character_
  ),

  "Karnofsky.d100" = list(
    meaning = "Karnofsky performance status score at day 100 post-transplant. From docx: 'Recipient's Karnofsky score at day +100'. Scale 0-100. Missing for patients who died before day 100.",
    notes   = NA_character_
  ),

  "Engraphment" = list(
    meaning = "Binary indicator: successful engraftment achieved. 1 = engrafted, 0 = not engrafted. Column name preserves original spelling ('Engraphment' instead of 'Engraftment').",
    notes   = "UNCERTAIN: engraftment definition (ANC >0.5x10^9/L on 3 consecutive days, or other threshold) not stated in the manuscript or docx. Binary meaning inferred from values (0/1 only)."
  ),

  "transplant_type" = list(
    meaning = "Graft source, derived in Parsing_metadata.qmd from Bone.marrow / Peripheral.blood / Ubilical.cord indicators. Values: BM = bone marrow; PBSC = peripheral blood stem cells; UC = umbilical cord blood; BM_UC = both BM and UC (one patient, ERR2666891).",
    notes   = "Derived column — see Bone.marrow, Peripheral.blood, Ubilical.cord for source. BM_UC is a special case hard-coded for ERR2666891."
  ),

  "gvhd_prophylaxis" = list(
    meaning = "GVHD prophylaxis regimen, decoded from GVHD.Prophylaxis integer in Parsing_metadata.qmd. From docx: 1 = Cyclosporine A; 2 = Cyclosporine + corticosteroids; 7 = Methotrexate + cyclosporine A.",
    notes   = NA_character_
  ),

  "sex" = list(
    meaning = "Recipient sex, decoded from Sex integer in Parsing_metadata.qmd: 1 -> 'male'; 2 -> 'female'.",
    notes   = NA_character_
  ),

  "death" = list(
    meaning = "Binary event indicator: patient died. Derived as 1 - Alive...1.yes..0.no. 0 = alive at last follow-up; 1 = died.",
    notes   = NA_character_
  ),

  "tx_death" = list(
    meaning = "Binary event indicator: treatment-related death (death in remission). Derived as 1 - Sens.1.rel..now.0.death_remiss. 0 = no treatment-related death; 1 = died in remission.",
    notes   = NA_character_
  ),

  "relapse" = list(
    meaning = "Binary event indicator: disease relapse. Derived as 1 - Sens.0.relapse.1.death.Now. 0 = no relapse; 1 = relapsed.",
    notes   = NA_character_
  )
)

# ---------------------------------------------------------------------------
# Read all sheets (to preserve them on write)
# ---------------------------------------------------------------------------

all_sheets <- readxl::excel_sheets(FILE_PATH)
sheets_data <- lapply(all_sheets, function(s) readxl::read_excel(FILE_PATH, sheet = s))
names(sheets_data) <- all_sheets

# ---------------------------------------------------------------------------
# Modify the Ingham sheet
# ---------------------------------------------------------------------------

df <- sheets_data[[SHEET_NAME]]

updated            <- 0L
skipped_nonempty   <- 0L
skipped_notfound   <- 0L
matched_keys       <- character(0)

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

  entry          <- MEANINGS[[col_name]]
  df$meaning[i]  <- entry$meaning
  df$notes[i]    <- entry$notes   # NA clears the cell
  updated        <- updated + 1L
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
