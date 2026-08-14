library(readxl)
library(writexl)

path <- "/Users/sophiehuebler/Documents/ODSi/ODSiData/Merging/data_dictionaries.xlsx"

sheets <- excel_sheets(path)
all_data <- lapply(sheets, function(s) read_excel(path, sheet = s))
names(all_data) <- sheets

df <- all_data[["Liu"]]

# Helper: only write if meaning is currently NA (skip already-filled rows)
fill <- function(df, col_name, meaning, notes = NA_character_) {
  idx <- which(df$column_name == col_name)
  if (length(idx) == 0) stop(paste("column not found:", col_name))
  if (!is.na(df$meaning[idx])) return(df)  # already filled — skip
  df$meaning[idx] <- meaning
  df$notes[idx]   <- notes
  df
}

# ── donor_or_patient ──────────────────────────────────────────────────────────
df <- fill(df, "donor_or_patient",
  paste0("Whether the sample is from the transplant recipient or the matched sibling stem cell donor. ",
         "The study enrolled N=57 recipients and N=22 of their paired HLA-matched sibling donors. ",
         "Values: Patient | Donor."),
  paste0("All clinical outcome columns (disease, GvHD, engraftment, survival) are NA for Donor rows; ",
         "demographic columns (sex, aborh) are populated for both Donors and Patients.")
)

# ── age ───────────────────────────────────────────────────────────────────────
df <- fill(df, "age",
  paste0("Recipient age at transplant. Units: years (integer). Range in data: 22-76. ",
         "NA for all Donor rows (not collected from donors).")
)

# ── race ──────────────────────────────────────────────────────────────────────
df <- fill(df, "race",
  paste0("Self-reported race of the transplant recipient. ",
         "Values: white | asian | hispanic | black. NA for Donor rows.")
)

# ── sex ───────────────────────────────────────────────────────────────────────
df <- fill(df, "sex",
  "Biological sex of the participant (recipient or donor). Values: male | female. Available for both patients and donors."
)

# ── aborh ─────────────────────────────────────────────────────────────────────
df <- fill(df, "aborh",
  paste0("ABO blood group and Rh factor of the participant (recipient or donor). ",
         "Combined blood type string. Values observed: A+ | A- | B+ | B- | O+ | O- | AB+.")
)

# ── BMI ───────────────────────────────────────────────────────────────────────
df <- fill(df, "BMI",
  paste0("Body mass index of the transplant recipient at or near the time of transplant. ",
         "Units: kg/m\u00b2 (integer). Range in data: 18-42. NA for Donor rows."),
  "Paper Table 1 defines obesity as BMI >= 30; 18 of 57 recipients (31.6%) were obese."
)

# ── disease ───────────────────────────────────────────────────────────────────
df <- fill(df, "disease",
  paste0("Primary hematologic diagnosis for which the transplant was performed, abbreviated. ",
         "Values: AML = acute myeloid leukemia; ALL = acute lymphoblastic leukemia; ",
         "MDS = myelodysplastic syndrome; NHL = non-Hodgkin's lymphoma; ",
         "CLL = chronic lymphocytic leukemia; TCL = T-cell leukemia/lymphoma; ",
         "CML = chronic myeloid leukemia; HD = Hodgkin's disease; AA = aplastic anemia. ",
         "NA for Donor rows."),
  "Paper Table 1 lists all nine diagnoses with counts. AML most common (N=24, 42.1%)."
)

# ── disease_status_at_transplant ──────────────────────────────────────────────
df <- fill(df, "disease_status_at_transplant",
  paste0("Disease status of the recipient at the time of transplant. ",
         "Values: remission (disease responding to prior treatment) | ",
         "refractory (disease not responding to treatment; also covers non-malignant diagnoses like AA). ",
         "NA for Donor rows."),
  "Paper Table 1: Remission=28 (49.1%), Refractory/not applicable=29 (50.9%)."
)

# ── infection_prior_to_transplant ─────────────────────────────────────────────
df <- fill(df, "infection_prior_to_transplant",
  paste0("Whether the recipient had a clinically documented infection in the period prior to transplant. ",
         "Does not include viral seropositivity (see other_viruses). Values: yes | no. NA for Donor rows.")
)

# ── other_viruses ─────────────────────────────────────────────────────────────
df <- fill(df, "other_viruses",
  paste0("Free-text list of prior viral seropositivity or known viral exposures for the recipient, ",
         "documented before transplant (e.g., VZV, HSV, EBV, CMV, Hepatitis B, Hepatitis C, BK virus, Rhinovirus). ",
         "Not a structured categorical."),
  paste0("UNCERTAIN: the paper does not formally define this field. Values are consistent with seropositive ",
         "viral exposure history (not necessarily active infection at transplant). The paper adjusts for CMV ",
         "seropositivity as a statistical covariate (Methods), but there is no separate cmv_status column in ",
         "liu_meta_qiime.tsv; CMV status is in the raw meta_samples.csv but was excluded in Parsing_metadata.qmd. ",
         "Checked: paper Methods, Parsing_metadata.qmd.")
)

# ── gi_history_details ────────────────────────────────────────────────────────
df <- fill(df, "gi_history_details",
  paste0("Free-text description of prior gastrointestinal medical history for the recipient, including past GI ",
         "surgeries, diagnoses, and conditions (e.g., appendectomy, GERD, cholecystectomy, bowel resection, IBD, ",
         "Crohn's disease). Not a structured categorical. NA for Donor rows."),
  paste0("This was one of the co-morbidity variables associated with recipient microbiome diversity in the paper ",
         "(Supplementary File 4; P=0.004 for GI/hepatic conditions). 45.6% missing (recipients with no documented ",
         "GI history record NA, not an empty string).")
)

# ── donor_source ──────────────────────────────────────────────────────────────
df <- fill(df, "donor_source",
  paste0("Source of hematopoietic stem cells for the transplant. ",
         "Values: pbsc = peripheral blood stem cells; marrow = bone marrow; ",
         "cord+cord = double umbilical cord blood unit transplant. NA for Donor rows."),
  paste0("Paper Table 1: PBSC=33 (57.9%), Marrow=3 (5.3%), Cord/Cord=21 (36.8%). ",
         "For cord+cord transplants, donor_type=cord and no individual living donor was enrolled.")
)

# ── donor_type ────────────────────────────────────────────────────────────────
df <- fill(df, "donor_type",
  paste0("Relationship of the stem cell donor to the recipient. ",
         "Values: related = HLA-matched related donor (typically sibling); ",
         "unrelated = HLA-matched unrelated donor (National Marrow Donor Program); ",
         "cord = umbilical cord blood unit (no living individual donor). NA for Donor rows."),
  paste0("For cord+cord transplants (donor_source=cord+cord), donor_type is always cord. ",
         "The study's sub-cohort with paired donor microbiome samples (N=22) consists exclusively ",
         "of recipients with related PBSC donors.")
)

# ── chemotherapy_regimen ──────────────────────────────────────────────────────
df <- fill(df, "chemotherapy_regimen",
  paste0("Conditioning chemotherapy regimen administered to the recipient before transplant. ",
         "Drug abbreviations: Flu=fludarabine; Mel=melphalan; TBI=total body irradiation; ",
         "Bu=busulfan; Cy=cyclophosphamide; Thio=thiotepa; Treo=treosulfan; ATG=anti-thymocyte globulin. ",
         "Dose notations: TBI(12)=12 Gy, TBI(13G)=13 Gy. ",
         "Values: Flu/Mel | Flu/TBI | Bu/Cy | Cy/TBI(12) | Flu/Cy/Thio/TBI | Flu/Cy/TBI | ",
         "Flu/Cy/TBI(13G) | Flu/Treo/TBI | Cy/ATG. NA for Donor rows."),
  paste0("Correlated with conditioning_intensity: myeloablative regimens = Bu/Cy or Cy/TBI; ",
         "reduced-intensity = Flu-based; Cy/ATG = aplastic anemia non-myeloablative conditioning. ",
         "The paper did not explicitly adjust for this due to collinearity with prophylaxis regimen.")
)

# ── conditioning_intensity ────────────────────────────────────────────────────
df <- fill(df, "conditioning_intensity",
  paste0("Intensity classification of the conditioning regimen. ",
         "Values: Low intensity (reduced-intensity conditioning, RIC); ",
         "Intermediate intensity; High intensity (myeloablative conditioning, MAC). NA for Donor rows."),
  "Paper Table 1: Low=24 (42.1%), Intermediate=24 (42.1%), High=9 (15.8%)."
)

# ── cyclosporine ──────────────────────────────────────────────────────────────
df <- fill(df, "cyclosporine",
  paste0("Binary indicator: whether the recipient received cyclosporine as part of GvHD prophylaxis. ",
         "Values: yes | no. NA for Donor rows."),
  paste0("One of five GvHD-prophylaxis indicator columns (cyclosporine, methotrexate, mmf, sirolimus, tacrolimus). ",
         "These five columns are one-hot expansions of the prophylaxis regimen. The four regimens used in this ",
         "cohort: cyclosporine/methotrexate (N=2), cyclosporine/MMF (N=21), tacrolimus/methotrexate (N=21), ",
         "tacrolimus/MMF (N=13) per Table 1. The underlying variable is the two-drug prophylaxis regimen.")
)

# ── cytogenetics ──────────────────────────────────────────────────────────────
df <- fill(df, "cytogenetics",
  paste0("Cytogenetic risk classification of the recipient's hematologic malignancy based on karyotype analysis. ",
         "Values: normal (normal karyotype) | abnormal (abnormal karyotype, higher cytogenetic risk). ",
         "NA for Donor rows."),
  paste0("UNCERTAIN: the paper does not define or describe cytogenetics in the Methods section or Table 1. ",
         "Column name and binary values (normal/abnormal) are consistent with standard cytogenetic risk ",
         "classification at diagnosis, but this is not confirmed by the manuscript. ",
         "Checked: Parsing_metadata.qmd (passed through from meta_clinical.xlsx without annotation), ",
         "paper Methods, Table 1.")
)

# ── methotrexate ──────────────────────────────────────────────────────────────
df <- fill(df, "methotrexate",
  paste0("Binary indicator: whether the recipient received methotrexate as part of GvHD prophylaxis. ",
         "Values: yes | no. NA for Donor rows."),
  "One of five GvHD-prophylaxis indicator columns. See notes on cyclosporine for the full prophylaxis regimen group."
)

# ── mmf ───────────────────────────────────────────────────────────────────────
df <- fill(df, "mmf",
  paste0("Binary indicator: whether the recipient received mycophenolate mofetil (MMF) as part of GvHD prophylaxis. ",
         "Values: yes | no. NA for Donor rows."),
  "One of five GvHD-prophylaxis indicator columns. See notes on cyclosporine for the full prophylaxis regimen group."
)

# ── sirolimus: already filled — skip ─────────────────────────────────────────

# ── tacrolimus ────────────────────────────────────────────────────────────────
df <- fill(df, "tacrolimus",
  paste0("Binary indicator: whether the recipient received tacrolimus as part of GvHD prophylaxis. ",
         "Values: yes | no. NA for Donor rows."),
  "One of five GvHD-prophylaxis indicator columns. See notes on cyclosporine for the full prophylaxis regimen group."
)

# ── right_censor_time ─────────────────────────────────────────────────────────
df <- fill(df, "right_censor_time",
  paste0("Administrative follow-up time (right-censoring time) for survival analysis, in days from transplant. ",
         "For recipients who did not die, this is the duration of documented follow-up (administrative censoring). ",
         "For deceased recipients, this equals or approximates time_to_death. Time origin: transplant date. ",
         "Units: days. NA for Donor rows."),
  paste0("UNCERTAIN: the paper does not explicitly define right_censor_time. Interpretation as days-from-transplant ",
         "censoring time is consistent with the paper's Cox proportional hazards model for overall mortality and with ",
         "values ranging 61-723 days (Table 1 mean follow-up 145 [121] days). One anomalous record (SAMEA4506982) ",
         "has right_censor_time=365 but time_to_death=345 with deceased=1, suggesting occasional discrepancy. ",
         "Checked: Parsing_metadata.qmd (passed through from meta_clinical.xlsx), paper Methods.")
)

# ── deceased ──────────────────────────────────────────────────────────────────
df <- fill(df, "deceased",
  paste0("Binary indicator of whether the recipient died during the follow-up period. ",
         "Values: 0 = alive at last follow-up; 1 = deceased. Time origin: transplant date. NA for Donor rows."),
  "Paper Table 1: 18 recipients (31.6%) known to be deceased."
)

# ── etiology_of_death ────────────────────────────────────────────────────────
df <- fill(df, "etiology_of_death",
  paste0("Free-text cause of death for recipients with deceased=1. Values observed: Relapse; Relapse/Respiratory; ",
         "Sepsis; Sepsis/ARDS/GVHD; aGVHD/Infection; Respiratory failure; ARDS/Respiratory failure; septic shock. ",
         "NA if deceased=0, cause unknown, or Donor rows."),
  paste0("Causes of death are non-exclusive per Table 1 (one death may count in multiple categories): ",
         "GvHD=11.1%, Infection/Sepsis=44.4%, Relapse=44.4%, Respiratory failure=22.2%.")
)

# ── time_to_death ─────────────────────────────────────────────────────────────
df <- fill(df, "time_to_death",
  paste0("Days from transplant to death for recipients with deceased=1. ",
         "Time origin: transplant date. Event: death. Units: days. NA if deceased=0 or for Donor rows."),
  "Paper Table 1: mean time to death 272 (207) days for all recipients, 181 (147) for sub-cohort."
)

# ── relapsed ──────────────────────────────────────────────────────────────────
df <- fill(df, "relapsed",
  paste0("Whether the recipient experienced disease relapse after transplant. ",
         "Values: yes | no. NA for Donor rows."),
  "Paper Table 1: 18 recipients (31.6%) relapsed."
)

# ── days_at_relapse ───────────────────────────────────────────────────────────
df <- fill(df, "days_at_relapse",
  paste0("Days from transplant to first disease relapse for recipients with relapsed=yes. ",
         "Time origin: transplant date. Event: disease relapse. Units: days. NA if relapsed=no or Donor rows."),
  "83.5% missing (structural: NA for all non-relapsed patients and donors)."
)

# ── platelet_engrafment ───────────────────────────────────────────────────────
df <- fill(df, "platelet_engrafment",
  paste0("Whether the recipient achieved platelet engraftment after transplant. ",
         "Values: yes | no. NA for Donor rows."),
  paste0("Two recipients did not achieve platelet engraftment (platelet_engrafment=no, ",
         "days_to_platelet_engrafment=NA): SAMEA4506991 and SAMEA4507002.")
)

# ── days_to_platelet_engrafment ───────────────────────────────────────────────
df <- fill(df, "days_to_platelet_engrafment",
  paste0("Days from transplant to platelet engraftment. Time origin: transplant date. ",
         "Event: platelet count >=20,000/\u03bcL independent of transfusion support ",
         "(standard engraftment criterion). Units: days. ",
         "NA if engraftment not achieved or for Donor rows."),
  "Paper Table 1: mean 20.3 (7.37) days for all recipients, 18.5 (6.45) for sub-cohort."
)

# ── anc_engrafment ────────────────────────────────────────────────────────────
df <- fill(df, "anc_engrafment",
  paste0("Whether the recipient achieved absolute neutrophil count (ANC) engraftment after transplant. ",
         "Values: yes | no. NA for Donor rows."),
  "Two recipients did not achieve ANC engraftment (SAMEA4506991, SAMEA4507002); same as those lacking platelet engraftment."
)

# ── days_to_anc_engrafment ────────────────────────────────────────────────────
df <- fill(df, "days_to_anc_engrafment",
  paste0("Days from transplant to ANC engraftment. Time origin: transplant date. ",
         "Event: ANC >=500/\u03bcL for three consecutive days (standard engraftment criterion). Units: days. ",
         "NA if engraftment not achieved or for Donor rows."),
  "Paper Table 1: mean 20.2 (11.1) days for all recipients, 12.9 (4.41) for sub-cohort."
)

# ── agvhd_organ ───────────────────────────────────────────────────────────────
df <- fill(df, "agvhd_organ",
  paste0("Organ system(s) affected by acute GvHD in the recipient, as a comma-separated free-text list. ",
         "Values: 'None documented' (no agGVHD observed); or one or more of: skin, gut, upper gut, liver, oral. ",
         "NA for Donor rows (outcome not applicable)."),
  paste0("Source variable for two derived columns: agvhd (binary, Parsing_metadata.qmd: ",
         "agvhd_organ=='None documented' -> 0, else 1) and agvhd_gut (positive if gut/upper gut in organ list). ",
         "I would keep agvhd_organ as the authoritative source; agvhd and agvhd_gut are derivable from it. ",
         "Note: 'None documented' (not NA) means no agGVHD was observed; NA means the row is a Donor.")
)

# ── agvhd_severity ────────────────────────────────────────────────────────────
df <- fill(df, "agvhd_severity",
  paste0("Severity grade of acute GvHD per the International Bone Marrow Transplant Registry (IBMTR) Severity ",
         "Index (Rowlings et al., BMT 1997). Values: no (no agGVHD); Grade I (mild); Grade II (moderate); ",
         "Grade III (severe); Grade IV (life-threatening); yes (agGVHD documented but not formally graded); ",
         "suspected (clinical suspicion without confirmed diagnosis). NA for Donor rows."),
  paste0("UNCERTAIN: values 'yes' and 'suspected' do not map to a standard IBMTR grade. 'Yes' appears when ",
         "agvhd_organ documents organ involvement but a formal grade is absent; 'suspected' appears in at least ",
         "one record (SAMEA4507001, agvhd_organ=gut). The paper states grading per IBMTR criteria but these ",
         "non-standard values are in the raw clinical data. Paper Table 1 reports Glucksberg grades 0/1-2/3-5, ",
         "which may differ from IBMTR staging terminology. Checked: Parsing_metadata.qmd (passed through from ",
         "meta_clinical.xlsx), paper Methods.")
)

# ── agvhd_gut ─────────────────────────────────────────────────────────────────
df <- fill(df, "agvhd_gut",
  paste0("Binary indicator of gut (GI tract) involvement in acute GvHD. ",
         "Values: positive (gut or upper gut involved) | negative (gut not involved or no agGVHD). ",
         "NA for Donor rows."),
  paste0("Derivable from agvhd_organ: positive corresponds to agvhd_organ containing 'gut' or 'upper gut'. ",
         "One-hot extraction of gut involvement from the multi-organ agvhd_organ field. ",
         "Redundant with agvhd_organ; I would keep agvhd_organ as the source. ",
         "Gut agGVHD was the primary outcome studied in this paper.")
)

# ── time_to_agvhd ─────────────────────────────────────────────────────────────
df <- fill(df, "time_to_agvhd",
  paste0("Days from transplant to onset of acute GvHD. Time origin: transplant date. ",
         "Event: first confirmed or clinically suspected agGVHD. Units: days. ",
         "NA if agvhd=0 (no agGVHD documented) or for Donor rows."),
  "63.3% missing (structural: NA for all agGVHD-negative patients and donors)."
)

# ── cgvhd_severity ────────────────────────────────────────────────────────────
df <- fill(df, "cgvhd_severity",
  paste0("Severity stage of chronic GvHD (cGVHD). ",
         "Values: none (no cGVHD); Stage 1 (mild); Stage 2 (moderate); Stage 3 (severe). ",
         "NA for Donor rows or recipients without cGVHD follow-up."),
  paste0("UNCERTAIN: staging system (NIH consensus criteria vs. older Shulman/Sullivan clinical staging) is not ",
         "specified in the paper. Values Stage 1/2/3 are consistent with NIH cGVHD global severity staging ",
         "(mild/moderate/severe) but could also reflect older staging. Chronic GvHD is not the primary outcome ",
         "and its grading is not described in the Methods. Checked: Parsing_metadata.qmd, paper Methods. ",
         "75.9% missing.")
)

# ── time_to_cgvhd ─────────────────────────────────────────────────────────────
df <- fill(df, "time_to_cgvhd",
  paste0("Days from transplant to onset of chronic GvHD. Time origin: transplant date. ",
         "Event: first confirmed cGVHD. Units: days. ",
         "NA if cgvhd_severity=none, missing cGVHD data, or Donor rows."),
  "62.0% missing (structural for patients without cGVHD and donors)."
)

# ── infection_duringafter_transplant ──────────────────────────────────────────
df <- fill(df, "infection_duringafter_transplant",
  paste0("Free-text list of clinically significant infections occurring during or after the transplant course. ",
         "Records organism names and infection types (e.g., 'C difficile, CMV viremia, VRE bacteremia, pneumonia'). ",
         "NA if no documented infections or for Donor rows."),
  paste0("UNCERTAIN: the distinction between infection_duringafter_transplant and infection_details is not defined ",
         "in the paper or Parsing_metadata.qmd. Both are free-text infection fields; in the data, this column ",
         "appears to capture the primary infection list while infection_details captures supplementary or ancillary ",
         "infections, but the split is inconsistent across records (some rows have data in one field only, some in ",
         "both, with no clear rule). Checked: Parsing_metadata.qmd, paper Methods. ",
         "I would treat this column as primary and infection_details as supplementary.")
)

# ── infection_details ─────────────────────────────────────────────────────────
df <- fill(df, "infection_details",
  paste0("Additional free-text details about post-transplant infections, supplementing infection_duringafter_transplant. ",
         "May contain secondary organisms, additional diagnoses, or context not captured in the primary infection field."),
  paste0("UNCERTAIN: distinction from infection_duringafter_transplant is not defined. See notes on ",
         "infection_duringafter_transplant. The two columns are partially redundant: 41.8% and 63.3% missing ",
         "respectively, with different subsets of patients contributing data to each. ",
         "Checked: Parsing_metadata.qmd, paper Methods.")
)

# ── agvhd ─────────────────────────────────────────────────────────────────────
df <- fill(df, "agvhd",
  paste0("Binary indicator of any acute GvHD occurrence, derived in Parsing_metadata.qmd from agvhd_organ. ",
         "Values: 0 = no agGVHD (agvhd_organ == 'None documented'); ",
         "1 = agGVHD documented in at least one organ system. ",
         "NA for Donor rows (agvhd_organ is NA)."),
  paste0("Derived column: case_when(is.na(agvhd_organ) ~ NA, agvhd_organ == 'None documented' ~ 0, TRUE ~ 1). ",
         "Redundant with agvhd_organ (source) and partially with agvhd_gut (binary for gut involvement only). ",
         "I would keep agvhd as the primary binary endpoint for analysis (it is the outcome in the paper's ",
         "logistic regression models) and agvhd_organ for organ-level detail. ",
         "See agvhd_organ notes for the full redundancy group (agvhd_organ, agvhd, agvhd_gut).")
)

# Verify all rows now filled
n_filled <- sum(!is.na(df$meaning))
message("Liu sheet: ", n_filled, " of ", nrow(df), " meanings filled.")
stopifnot(n_filled == nrow(df))

all_data[["Liu"]] <- df
write_xlsx(all_data, path)
message("Done. Wrote Liu sheet to ", path)
