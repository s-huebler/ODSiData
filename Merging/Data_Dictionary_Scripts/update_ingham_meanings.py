"""
update_ingham_meanings.py

Writes meaning (col 8) and notes (col 11) into the Ingham sheet of
data_dictionaries.xlsx using openpyxl.  Only fills rows where meaning
is currently empty/None.  Keyed by column_name (col 1).
"""

import openpyxl

FILE_PATH = "/Users/sophiehuebler/Documents/ODSi/ODSiData/Merging/data_dictionaries.xlsx"
SHEET_NAME = "Ingham"

MEANINGS = {
    "patient": {
        "meaning": "Study-specific patient identifier (P01–P30); one patient may contribute multiple samples across timepoints.",
        "notes": None,
    },
    "timepoint": {
        "meaning": "Days from transplant to stool sample collection (day 0 = transplant date). Integer; negative = pre-transplant. Renamed from days_posttransplant.",
        "notes": None,
    },
    "sampling_date": {
        "meaning": "Calendar date of stool sample collection (dd-mm-yyyy).",
        "notes": None,
    },
    "transplant_date": {
        "meaning": "Calendar date of allogeneic stem cell transplant/BMT (dd-mm-yyyy). This is the time origin (day 0) for the timepoint column. Renamed from Date.of.BMT..dd.mm.yyyy.",
        "notes": None,
    },
    "BMT.No": {
        "meaning": "Transplant number for this patient: 1 = first allogeneic transplant, 2 = second allogeneic transplant.",
        "notes": "UNCERTAIN: inferred from values (1 and 2 only) and standard EBMT registry field meaning. Checked manuscript and raw file headers; no explicit legend found.",
    },
    "DX": {
        "meaning": "Numeric IBMTR disease code corresponding to the primary diagnosis. Text labels are in the disease column.",
        "notes": "Redundant with disease (numeric code vs text label). Prefer disease for harmonisation. UNCERTAIN: full IBMTR code table not reproduced in manuscript; codes inferred from paired disease text (e.g. DX=10 → AML, DX=24 → cALL, DX=300 → aplastic anaemia).",
    },
    "disease": {
        "meaning": "Full IBMTR disease name for the primary diagnosis (free text from registry). E.g. 'cALL (pre-B)', 'Severe aplastic anemia', 'AML or ANLL, not otherwise specified'.",
        "notes": "Redundant with DX (text version). Prefer this column over DX for harmonisation because the text is self-documenting. Renamed from DiseaseNameIBMTR.",
    },
    "diagnosis_date": {
        "meaning": "Calendar date of initial diagnosis (dd-mm-yyyy). Renamed from Date.of.diagnosis..dd.mm.yyyy.",
        "notes": None,
    },
    "Donor.sex": {
        "meaning": "Donor sex (integer coded). By analogy with Sex (1=male, 2=female used in Parsing_metadata.qmd): 1 = male, 2 = female.",
        "notes": "UNCERTAIN: coding 1=male/2=female is inferred from the Sex recoding in Parsing_metadata.qmd (case_when(Sex==1~'male', Sex==2~'female')). Donor.sex is not independently recoded in the script; checked manuscript — no explicit coding legend for Donor.sex.",
    },
    "age": {
        "meaning": "Recipient (patient) age at transplant in decimal years. Renamed from Rec.age.in.y.",
        "notes": None,
    },
    "weight": {
        "meaning": "Patient body weight in kg (integer values). Reference point is pre-transplant (at time of conditioning).",
        "notes": "UNCERTAIN: timepoint of weight measurement (pre-conditioning vs. transplant day) not stated explicitly in the manuscript. Inferred as pre-transplant from registry context.",
    },
    "Donor.age.in.y": {
        "meaning": "Donor age at time of donation in decimal years.",
        "notes": None,
    },
    "Bone.marrow": {
        "meaning": "One-hot indicator: 1 = graft source is bone marrow (BM), 0 = not BM. Part of a one-hot graft-source group.",
        "notes": "One-hot group: Bone.marrow / Peripheral.blood / Ubilical.cord (note: misspelled 'Ubilical' in original) encode a single underlying variable transplant_type. One patient (ERR2666891, P12) has both Bone.marrow=1 and Ubilical.cord=1, coded as BM_UC in transplant_type. Keep transplant_type for harmonisation; these three columns are the raw source.",
    },
    "Peripheral.blood": {
        "meaning": "One-hot indicator: 1 = graft source is peripheral blood stem cells (PBSC), 0 = not PBSC. Part of a one-hot graft-source group.",
        "notes": "One-hot group: see Bone.marrow notes. Underlying variable: transplant_type.",
    },
    "Ubilical.cord": {
        "meaning": "One-hot indicator: 1 = graft source is umbilical cord blood (UC), 0 = not UC. Part of a one-hot graft-source group. Column name misspells 'umbilical' as 'ubilical' — preserved from original data.",
        "notes": "One-hot group: see Bone.marrow notes. Underlying variable: transplant_type.",
    },
    "match": {
        "meaning": "Donor–recipient HLA match classification. Values: matched_unrelated = fully HLA-matched unrelated donor; sibling_donor = HLA-identical sibling; 1HLA_mismatch = 1 antigen/allele mismatch; 2HLA_mismatch = 2 antigen/allele mismatches. Renamed from DonorMatch.",
        "notes": None,
    },
    "donor": {
        "meaning": "Donor type. Values: unrelated = volunteer unrelated donor; sibling = related sibling donor. Renamed from Donor.",
        "notes": None,
    },
    "CMVab": {
        "meaning": "CMV (cytomegalovirus) serostatus of donor–recipient pair. Values appear to be 1, 2, 3.",
        "notes": "UNCERTAIN: exact coding not defined in manuscript or raw file headers. Common EBMT coding: 1 = R−/D− or D+/R−, 2 = R+ (recipient seropositive), 3 = mixed or indeterminate; however three-level coding may differ. Checked Data_matrix_37_patients.txt and Data_matrix_30_patients_additional.txt headers — no legend. Needs EBMT ProMISe codebook lookup.",
    },
    "agvhd": {
        "meaning": "Binary indicator: acute GVHD occurred. 0 = no aGVHD, 1 = aGVHD occurred. Derived from EBMT field X541GVHDoccur.",
        "notes": None,
    },
    "agvhd_grade": {
        "meaning": "Maximum acute GVHD grade (Glucksberg scale 0–IV). 0 = no aGVHD; 1 = grade I; 2 = grade II; 3 = grade III; 4 = grade IV. Derived from EBMT field X542MaxAGVHD.",
        "notes": None,
    },
    "agvhd_date": {
        "meaning": "Calendar date of acute GVHD onset (dd-mm-yyyy). Missing for patients without aGVHD. Derived from EBMT field X549Date.",
        "notes": None,
    },
    "cause_of_death": {
        "meaning": "Coded primary cause of death. Values observed: 10, 22, 70, 900. Derived from Primary.cause.of.death.",
        "notes": "UNCERTAIN: coding legend not reproduced in manuscript. Values look like EBMT ProMISe cause-of-death codes (e.g. 70 may = GVHD, 10 = relapse/progression, 22 = infection, 900 = other/unknown). Checked raw file headers — no legend. Needs EBMT ProMISe codebook lookup.",
    },
    "tte_death": {
        "meaning": "Time from transplant (day 0) to death or last follow-up (days). Event = death (see death column). Censored observations have tte_death equal to administrative follow-up time. Derived from EBMT field X.Alle..Survival.all.patients..to.death._Surv.",
        "notes": None,
    },
    "Sens.death.0.": {
        "meaning": "Overall survival censoring indicator (complement of death). 1 = alive/censored at tte_death; 0 = died. Equivalent to the original Alive...1.yes..0.no. column that was dropped during parsing.",
        "notes": "Redundant with death (Sens.death.0. = 1 − death). The Parsing_metadata.qmd script intended to drop it (the -Sens.death.0. inside the select(-c(...)) call is a double-negative that accidentally preserved the column). Prefer death for harmonisation. UNCERTAIN: the double-negative in select() is ambiguous — confirm intended behaviour.",
    },
    "tte_tx_death": {
        "meaning": "Time from transplant (day 0) to treatment-related death (death in remission) or competing-event censoring (days). Event = tx_death. Competing events (relapse) are censored at the time of the competing event. Derived from EBMT field X.Alle..Death.in.remiss_Surv.",
        "notes": None,
    },
    "tte_relapse": {
        "meaning": "Time from transplant (day 0) to relapse or competing-event censoring (days). Event = relapse. Competing events (treatment-related death) are censored at the time of the competing event. Derived from EBMT field X.Alle..Relapse_Surv.",
        "notes": None,
    },
    "censor": {
        "meaning": "Administrative censoring time: days from transplant to database closure or end of observation window (Surv.to.now). This is the maximum observable follow-up time for each patient, irrespective of event status. Renamed from Surv.to.now.",
        "notes": "Not the time-to-event for any specific outcome — it is the ceiling follow-up time applied across all endpoints. For alive patients, tte_death = censor.",
    },
    "Cell.dose.kg": {
        "meaning": "Infused cell dose per kg recipient body weight (×10^6/kg). Unit of cells not specified in the source file.",
        "notes": "UNCERTAIN: numerator cell type (total mononuclear cells, CD34+ cells, or nucleated cells) not stated in raw data headers or manuscript methods. Checked Data_matrix_37_patients.txt and Data_matrix_30_patients_additional.txt — column name is Cell.dose.kg with no further annotation.",
    },
    "Irrad": {
        "meaning": "Binary indicator: irradiation was included in the conditioning regimen. 0 = no irradiation, 1 = irradiation given (includes TBI and/or other targeted irradiation).",
        "notes": None,
    },
    "TBI": {
        "meaning": "Binary indicator: total body irradiation (TBI) specifically was used in conditioning. 0 = no TBI, 1 = TBI given. Subset of Irrad.",
        "notes": None,
    },
    "Total.dose.of.TBI.in.cGy": {
        "meaning": "Total TBI dose in centigray (cGy). Missing for patients who did not receive TBI.",
        "notes": None,
    },
    "FracTBI": {
        "meaning": "Binary indicator: TBI was delivered as fractionated (split) doses. 1 = fractionated TBI; 0 = single-dose (hyperfractionated or single-fraction) TBI.",
        "notes": None,
    },
    "Dose.frac": {
        "meaning": "Dose per TBI fraction in centigray (cGy). Missing for patients who did not receive fractionated TBI.",
        "notes": None,
    },
    "X197ATGmm": {
        "meaning": "Binary indicator: anti-thymocyte globulin (ATG) was included in the conditioning regimen. 0 = no ATG, 1 = ATG given. Original column name in Data_matrix_37_patients.txt: ATGmm; prefixed X197 from EBMT ProMISe field numbering in the additional export.",
        "notes": "UNCERTAIN: the 'mm' suffix in ATGmm is unexplained — may denote route, formulation (e.g. Micromet), or be an artefact of the EBMT field code. Exact EBMT field 197 definition not confirmed; inferred from paired column Total.dose.Busulfan..mg. context and binary values. Needs EBMT ProMISe codebook lookup.",
    },
    "X233Bu": {
        "meaning": "Busulfan (Bu) use in conditioning. Original column: Bu in Data_matrix_37_patients.txt; EBMT field 233 in the additional export. Values: 0 = no busulfan; 1 = IV busulfan; 2 = oral busulfan (or alternative ordinal).",
        "notes": "UNCERTAIN: coding 0/1/2 not defined in manuscript or raw headers. Three observed levels (0, 1, 2) suggest ordinal (route or dose tier) rather than binary. Needs EBMT ProMISe codebook lookup.",
    },
    "Total.dose.Busulfan..mg.": {
        "meaning": "Total busulfan dose in mg administered as part of conditioning. Missing for patients not receiving busulfan.",
        "notes": None,
    },
    "X270Cyclo": {
        "meaning": "Binary indicator: cyclophosphamide (Cyclo) included in conditioning. Original column: Cyclo in Data_matrix_37_patients.txt; EBMT field 270. 0 = no cyclophosphamide, 1 = cyclophosphamide given.",
        "notes": None,
    },
    "Total.dose.cyclophosphamide..mg.": {
        "meaning": "Total cyclophosphamide dose in mg administered as part of conditioning. Missing for patients not receiving cyclophosphamide.",
        "notes": None,
    },
    "Total.dose.VP16..mg.": {
        "meaning": "Total etoposide (VP-16) dose in mg administered as part of conditioning. Missing for patients not receiving etoposide.",
        "notes": None,
    },
    "Total.dose.melphalan..mg.": {
        "meaning": "Total melphalan dose in mg administered as part of conditioning. Missing for patients not receiving melphalan.",
        "notes": None,
    },
    "X284.2Fludarab": {
        "meaning": "Binary indicator: fludarabine included in conditioning. Original column: Fludarab in Data_matrix_37_patients.txt; EBMT field 284.2. 0 = no fludarabine, 1 = fludarabine given.",
        "notes": None,
    },
    "X284.3TotalDose": {
        "meaning": "Total fludarabine dose in mg as part of conditioning. Original column: TotalDoseFludarab in Data_matrix_37_patients.txt; EBMT field 284.3. Missing for patients not receiving fludarabine.",
        "notes": "UNCERTAIN: unit (mg or mg/m²) not specified in raw headers. Inferred as mg from column name pattern matching Total.dose.Busulfan..mg. etc. Needs EBMT ProMISe codebook lookup.",
    },
    "X10Ab": {
        "meaning": "Binary indicator: antibody-based conditioning agent included (e.g. Alemtuzumab/Campath or Rituximab). EBMT field 10; 'Ab' suffix = antibody. 0 = not given, 1 = given.",
        "notes": "UNCERTAIN: specific antibody not identified. Not present in Data_matrix_37_patients.txt (only in the 30-patient additional EBMT export). Checked manuscript methods — no explicit mention of EBMT field 10. Needs EBMT ProMISe codebook lookup.",
    },
    "Karnofsky.bef.condt": {
        "meaning": "Karnofsky performance status score before start of conditioning. Scale 0–100 in 10-point increments; 100 = fully normal function, 0 = dead. Observed values: 50, 80, 90, 100.",
        "notes": None,
    },
    "Karnofsky.d100": {
        "meaning": "Karnofsky performance status score at day 100 post-transplant. Scale 0–100. Missing for patients who died before day 100.",
        "notes": None,
    },
    "Engraphment": {
        "meaning": "Binary indicator: successful engraftment achieved. 1 = engrafted, 0 = not engrafted. Column name preserves original spelling ('Engraphment' instead of 'Engraftment').",
        "notes": "UNCERTAIN: engraftment definition (ANC >0.5×10^9/L on 3 consecutive days, or other threshold) not stated in the manuscript. Checked raw file headers — no definition. Inferred binary meaning from values (0/1).",
    },
    "transplant_type": {
        "meaning": "Graft source, derived in Parsing_metadata.qmd from Bone.marrow / Peripheral.blood / Ubilical.cord indicators. Values: BM = bone marrow; PBSC = peripheral blood stem cells; UC = umbilical cord blood; BM_UC = both BM and UC (one patient, ERR2666891).",
        "notes": "Derived column — see Bone.marrow, Peripheral.blood, Ubilical.cord for source. BM_UC is a special case hard-coded for ERR2666891.",
    },
    "gvhd_prophylaxis": {
        "meaning": "GVHD prophylaxis regimen, decoded from GVHD.Prophylaxis integer in Parsing_metadata.qmd: 1 → 'Cyclosporine A'; 2 → 'Cyclosporine + Corticosteroids'; 7 → 'Cyclosporine A + Methotrexate'.",
        "notes": None,
    },
    "sex": {
        "meaning": "Recipient sex, decoded from Sex integer in Parsing_metadata.qmd: 1 → 'male'; 2 → 'female'.",
        "notes": None,
    },
    "death": {
        "meaning": "Binary event indicator: patient died. Derived as 1 − Alive...1.yes..0.no. 0 = alive at last follow-up; 1 = died.",
        "notes": None,
    },
    "tx_death": {
        "meaning": "Binary event indicator: treatment-related death (death in remission). Derived as 1 − Sens.1.rel..now.0.death_remiss. 0 = no treatment-related death; 1 = died in remission.",
        "notes": None,
    },
    "relapse": {
        "meaning": "Binary event indicator: disease relapse. Derived as 1 − Sens.0.relapse.1.death.Now. 0 = no relapse; 1 = relapsed.",
        "notes": None,
    },
}

# ---------------------------------------------------------------------------

wb = openpyxl.load_workbook(FILE_PATH)
ws = wb[SHEET_NAME]

updated = 0
skipped_nonempty = 0
skipped_notfound = 0

matched_keys = set()

for row in ws.iter_rows(min_row=2):  # skip header
    col_name_cell = row[0]   # column index 0 → openpyxl col 1
    meaning_cell  = row[7]   # column index 7 → openpyxl col 8
    notes_cell    = row[10]  # column index 10 → openpyxl col 11

    col_name = col_name_cell.value
    if col_name is None:
        continue

    if col_name not in MEANINGS:
        skipped_notfound += 1
        continue

    matched_keys.add(col_name)

    # Skip rows where meaning is already filled
    current_meaning = meaning_cell.value
    if current_meaning is not None and str(current_meaning).strip() != "":
        skipped_nonempty += 1
        continue

    entry = MEANINGS[col_name]
    meaning_cell.value = entry["meaning"]
    notes_cell.value   = entry["notes"]   # may be None — clears the cell
    updated += 1

wb.save(FILE_PATH)

print(f"Done. Rows updated: {updated}")
print(f"      Rows skipped (meaning already present): {skipped_nonempty}")
print(f"      Rows skipped (column_name not in MEANINGS dict): {skipped_notfound}")

unmatched_keys = set(MEANINGS.keys()) - matched_keys
if unmatched_keys:
    print(f"\nWARNING: these keys in MEANINGS were not found in the sheet:")
    for k in sorted(unmatched_keys):
        print(f"  {k}")
else:
    print("\nAll MEANINGS keys matched a row in the sheet.")
