#!/usr/bin/env python3
"""Build Merging/Harmonization/harmonization_provenance.tsv.

One row per target column x study, carrying the 7-level status vocabulary used
by data_dictionaries_harmonized.xlsx (Harmonization_Summary sheet):

  exact        copied verbatim, no modification
  direct       read off a single source column, type coercion only
  recoded      source values mapped or binned onto a canonical vocabulary
  derived      computed or generated from one or more source columns
  limited      populated but with a documented restriction on coverage/meaning
  unsupported  the source records something related that cannot support this
               target column
  unavailable  the study does not record it

Statuses were audited against Merging/Harmonization/harmonize_gvhd_metadata.R
(1946 lines, read 2026-09-17), not against the workbook, which still reflects
the 18-variable first pass.
"""

import csv
import sys

TARGET_COLS = [
    "sample-id", "study", "person", "timepoint", "sex", "age", "disease",
    "nutrition", "transplant_type", "transplant_date", "sample_date",
    "sample_day_rel_transplant",
    "conditioning_intensity", "conditioning_regimen", "conditioning_tbi",
    "conditioning_serotherapy",
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
    "myelosuppression", "mucositis", "bloodstream_infection",
    "bronchiolitis_obliterans",
]

STUDIES = ["Artacho", "DAmico", "Fujimoto", "Ingham", "Jarosch", "Liu", "Vallet"]

# Schema blocks, used to facet the missingness heatmap and to group the
# provenance table. Order matches target_cols.
DOMAINS = [
    ("Identifiers", ["sample-id", "study", "person", "timepoint"]),
    ("Demographics", ["sex", "age", "disease"]),
    ("Transplant context", ["nutrition", "transplant_type", "transplant_date",
                            "sample_date", "sample_day_rel_transplant"]),
    ("Conditioning", ["conditioning_intensity", "conditioning_regimen",
                      "conditioning_tbi", "conditioning_serotherapy"]),
    ("GVHD prophylaxis", ["gvhd_prophylaxis", "gvhd_prophylaxis_cni"]),
    ("Acute GVHD, overall", ["agvhd", "agvhd_grade", "agvhd_day_rel_transplant"]),
    ("Acute GVHD, by organ", ["gut_gvhd", "gut_gvhd_stage", "gut_gvhd_day_rel_transplant",
                              "skin_gvhd", "skin_gvhd_stage", "skin_gvhd_day_rel_transplant",
                              "liver_gvhd", "liver_gvhd_stage", "liver_gvhd_day_rel_transplant"]),
    ("Chronic GVHD", ["cgvhd", "cgvhd_stage", "cgvhd_day_rel_transplant"]),
    ("Engraftment", ["anc_engraftment", "anc_engraftment_day_rel_transplant",
                     "platelet_engraftment", "platelet_engraftment_day_rel_transplant"]),
    ("Survival and relapse", ["death", "death_date", "cause_of_death",
                              "death_day_rel_transplant", "relapse",
                              "relapse_day_rel_transplant"]),
    ("Observation window", ["end_observation_reason",
                            "end_observation_day_rel_transplant"]),
    ("Secondary outcomes", ["myelosuppression", "mucositis",
                            "bloodstream_infection", "bronchiolitis_obliterans"]),
]

DOMAIN_OF = {col: name for name, cols in DOMAINS for col in cols}
DOMAIN_ORDER = {name: i for i, (name, _) in enumerate(DOMAINS, start=1)}

# Default for any target column a study does not populate.
DEFAULT = ("unavailable", "", "Not recorded in the source metadata.")

ARTACHO = {
    "sample-id": ("exact", "sample-id", "Copied as character without modification."),
    "study": ("derived", "constant", 'Set to "Artacho".'),
    "person": ("derived", "Patient", "Natural-sort crosswalk to Artacho_NNN; original code not retained."),
    "timepoint": ("recoded", "Timepoint", "Shared day-bin rule on the numeric day; Timepoint_Class not used."),
    "sex": ("recoded", "Gender", "F -> female; M -> male."),
    "age": ("direct", "Age", "Years, retained unrounded."),
    "disease": ("recoded", "Disease", "Study abbreviations expanded to the shared disease vocabulary."),
    "nutrition": ("recoded", "Parenteral.Nutrition", "Yes -> parenteral; No -> enteral."),
    "transplant_type": ("recoded", "Transplant.source", "1 -> bone marrow; 2 -> umbilical cord blood; 3 -> peripheral blood stem cells."),
    "transplant_date": ("recoded", "date.of.transplant", "Parsed to ISO YYYY-MM-DD."),
    "sample_date": ("derived", "date.of.transplant + Timepoint", "Transplant date advanced by the sample day."),
    "sample_day_rel_transplant": ("direct", "Timepoint", "Day relative to transplant."),
    "agvhd": ("derived", "GVHD_grade", "Composite grade > 0."),
    "agvhd_grade": ("direct", "GVHD_grade", "Overall composite grade."),
    "agvhd_day_rel_transplant": ("unavailable", "", "No aGVHD onset date or day anywhere in the source."),
    "gut_gvhd": ("derived", "gut_gvhd_grade", "Organ stage > 0."),
    "gut_gvhd_stage": ("direct", "gut_gvhd_grade", "True organ stage (grade-per-organ study)."),
    "gut_gvhd_day_rel_transplant": ("unavailable", "", "No aGVHD onset day recorded."),
    "skin_gvhd": ("derived", "skin_gvhd_grade", "Organ stage > 0."),
    "skin_gvhd_stage": ("direct", "skin_gvhd_grade", "True organ stage."),
    "skin_gvhd_day_rel_transplant": ("unavailable", "", "No aGVHD onset day recorded."),
    "liver_gvhd": ("derived", "liver_GVHD_grade", "Organ stage > 0."),
    "liver_gvhd_stage": ("direct", "liver_GVHD_grade", "True organ stage."),
    "liver_gvhd_day_rel_transplant": ("unavailable", "", "No aGVHD onset day recorded."),
    "myelosuppression": ("direct", "Myelosuppression", "Source 0/1 carried through harmonize_binary(); a toxicity outcome, not a conditioning descriptor."),
    "mucositis": ("recoded", "Mucositis", "Yes -> 1; No -> 0."),
}

DAMICO = {
    "sample-id": ("exact", "sample-id", "Copied as character without modification."),
    "study": ("derived", "constant", 'Set to "DAmico".'),
    "person": ("derived", "Patient", "Natural-sort crosswalk to DAmico_NN."),
    "timepoint": ("recoded", "Timepoint", "Shared day-bin rule on the numeric day."),
    "sex": ("recoded", "Sex", "Mapped to female | male."),
    "age": ("direct", "Age", "Years, retained unrounded."),
    "disease": ("recoded", "Diagnosis", "Expanded to the shared disease vocabulary."),
    "nutrition": ("recoded", "Nutritional_Regimen", "Free-text EN/PN windows collapsed to enteral | parenteral | mixed."),
    "transplant_type": ("recoded", "Stem_cell_source", "BM -> bone marrow; PBSC -> peripheral blood stem cells."),
    "sample_day_rel_transplant": ("direct", "Timepoint", "Day relative to transplant."),
    "conditioning_intensity": ("derived", "constant", "Set to MAC for all samples on the data dictionary's assertion (Supplementary Table 2); no intensity column exists. The five paediatric Cy/Flu/TBI samples record no TBI dose, so MAC cannot be independently verified."),
    "conditioning_regimen": ("recoded", "Conditioning_regimen", "Six source strings mapped to canonical sorted token sets; TBI stripped into its own column."),
    "conditioning_tbi": ("derived", "Conditioning_regimen", "TBI token detected in the regimen string."),
    "agvhd": ("derived", "gut/Skin/liver_gvhd_grade", "Maximum organ stage > 0; no composite grade exists."),
    "agvhd_grade": ("unavailable", "", "No overall composite grade recorded."),
    "agvhd_day_rel_transplant": ("derived", "gvhd_day", "Single first-diagnosis day, retained where any organ stage > 0."),
    "gut_gvhd": ("derived", "gut_gvhd_grade", "Organ stage > 0."),
    "gut_gvhd_stage": ("direct", "gut_gvhd_grade", "True organ stage."),
    "gut_gvhd_day_rel_transplant": ("derived", "gvhd_day", "One aGVHD onset day applied to every involved organ; the source does not record which organ presented first."),
    "skin_gvhd": ("derived", "Skin_gvhd_grade", "Organ stage > 0."),
    "skin_gvhd_stage": ("direct", "Skin_gvhd_grade", "True organ stage."),
    "skin_gvhd_day_rel_transplant": ("derived", "gvhd_day", "Shared onset day applied to every involved organ."),
    "liver_gvhd": ("derived", "liver_gvhd_grade", "Organ stage > 0."),
    "liver_gvhd_stage": ("direct", "liver_gvhd_grade", "True organ stage."),
    "liver_gvhd_day_rel_transplant": ("derived", "gvhd_day", "Shared onset day applied to every involved organ."),
    "anc_engraftment": ("derived", "PMN_day", "A recorded PMN day implies engraftment; present for all 20 patients."),
    "anc_engraftment_day_rel_transplant": ("direct", "PMN_day", "Day of neutrophil recovery."),
    "platelet_engraftment": ("limited", "PLT_over_20000_day", "A missing platelet day cannot be distinguished from failure to recover; the one missing patient (E10, alive at day +100) is coded 0."),
    "platelet_engraftment_day_rel_transplant": ("direct", "PLT_over_20000_day", "Day of platelet recovery."),
    "death": ("limited", "Outcome_at_100", "Vital status through day +100 only; A -> 0, D -> 1."),
    "end_observation_reason": ("derived", "constant", 'Set to "administrative": follow-up was censored at day +100 for every subject.'),
    "end_observation_day_rel_transplant": ("derived", "constant", "Set to 100; no later outcome date exists in the source."),
    "mucositis": ("recoded", "Mucositis_grade", 'Grades I/II/III -> 1; "/" (ungraded, n=5) and NA (n=5) -> 0, because the source records mucositis only as a graded adverse event.'),
    "bloodstream_infection": ("derived", "BSI", "Any non-missing organism string -> 1; NA -> 0, confirmed against manuscript Table 2."),
}

FUJIMOTO = {
    "sample-id": ("exact", "sample-id", "Copied as character without modification."),
    "study": ("derived", "constant", 'Set to "Fujimoto".'),
    "person": ("derived", "Patient", "Natural-sort crosswalk to Fujimoto_NN."),
    "timepoint": ("recoded", "Timepoint", "dayN labels binned by the shared day rule; the 'pre' label is assigned pre-conditioning by a study-specific override."),
    "sex": ("recoded", "Sex", "Mapped to female | male."),
    "age": ("direct", "Age", "Years, retained unrounded."),
    "disease": ("recoded", "Disease", "Expanded to the shared disease vocabulary."),
    "transplant_type": ("recoded", "Graft_Type", "BM -> bone marrow; PB -> peripheral blood stem cells; CB -> umbilical cord blood."),
    "sample_day_rel_transplant": ("limited", "Timepoint", "Parsed from dayN labels; the 'pre' baseline sample carries no numeric day and stays NA."),
    "conditioning_intensity": ("direct", "Conditioning_Intensity", "MAC | RIC | NMA already in canonical form."),
    "conditioning_tbi": ("recoded", "Conditioning_TBI", "yes -> 1; no -> 0."),
    "agvhd": ("recoded", "AGVHD", "Source 1/0 event flag."),
    "agvhd_grade": ("direct", "AGVHD_Severity", "Overall Glucksberg grade at diagnosis."),
    "agvhd_day_rel_transplant": ("direct", "AGVHD_TTE", "Overall onset day."),
    "gut_gvhd": ("derived", "AGVHD + AGVHD_Organ", "Membership in the involved-organ list; an aGVHD-negative patient is a confirmed negative."),
    "gut_gvhd_stage": ("derived", "AGVHD_Severity + AGVHD_Organ", "Overall grade applied to every organ named; this is a composite grade, not a true organ stage."),
    "gut_gvhd_day_rel_transplant": ("derived", "AGVHD_TTE + AGVHD_Organ", "Overall onset day applied to every organ named."),
    "skin_gvhd": ("derived", "AGVHD + AGVHD_Organ", "Membership in the involved-organ list."),
    "skin_gvhd_stage": ("derived", "AGVHD_Severity + AGVHD_Organ", "Overall grade applied to every organ named."),
    "skin_gvhd_day_rel_transplant": ("derived", "AGVHD_TTE + AGVHD_Organ", "Overall onset day applied to every organ named."),
    "liver_gvhd": ("derived", "AGVHD + AGVHD_Organ", "Membership in the involved-organ list."),
    "liver_gvhd_stage": ("derived", "AGVHD_Severity + AGVHD_Organ", "Overall grade applied to every organ named."),
    "liver_gvhd_day_rel_transplant": ("derived", "AGVHD_TTE + AGVHD_Organ", "Overall onset day applied to every organ named."),
    "gvhd_prophylaxis": ("unsupported", "AGVHD_Treatment", "AGVHD_Treatment (mPSL, ATG, MSC) is rescue therapy given after diagnosis, not prophylaxis."),
    "gvhd_prophylaxis_cni": ("unsupported", "AGVHD_Treatment", "Same: the only drug column is post-diagnosis rescue therapy."),
}

INGHAM = {
    "sample-id": ("exact", "sample-id", "Copied as character without modification."),
    "study": ("derived", "constant", 'Set to "Ingham".'),
    "person": ("derived", "patient", "Natural-sort crosswalk to Ingham_NN."),
    "timepoint": ("recoded", "timepoint", "Shared day-bin rule on the numeric day."),
    "sex": ("recoded", "sex", "Mapped to female | male."),
    "age": ("direct", "age", "Years, retained unrounded."),
    "disease": ("recoded", "disease", "Expanded to the shared disease vocabulary."),
    "transplant_type": ("recoded", "transplant_type", "BM | PBSC | UC | BM_UC mapped to the canonical graft vocabulary."),
    "transplant_date": ("recoded", "transplant_date", "Parsed to ISO YYYY-MM-DD."),
    "sample_date": ("recoded", "sampling_date", "Parsed to ISO YYYY-MM-DD."),
    "sample_day_rel_transplant": ("direct", "timepoint", "Day relative to transplant."),
    "conditioning_intensity": ("derived", "Myeloabl", "Constant 1 across all 96 documented rows -> MAC; the one metadata-less row stays NA."),
    "conditioning_regimen": ("derived", "X233Bu, X270Cyclo, X284.2Fludarab, Total.dose.melphalan..mg., Total.dose.VP16..mg., Total.dose.thiotepa..mg.", "Six drug-presence flags and dose columns assembled into a sorted token string; X233Bu values 1 and 2 both count as busulfan."),
    "conditioning_tbi": ("derived", "TBI, Irrad", "TBI is NA for 28 samples, all of which have Irrad = 0; those are recovered to 0."),
    "conditioning_serotherapy": ("derived", "X197ATGmm, X10Ab", "ATG or an antibody-based agent -> 1."),
    "gvhd_prophylaxis": ("recoded", "gvhd_prophylaxis", "Three source strings collapsed to cni-mtx | cni-steroid | cni-alone; ATG in conditioning and graft manipulation deliberately excluded."),
    "gvhd_prophylaxis_cni": ("derived", "gvhd_prophylaxis", "All recorded regimens are cyclosporine-based, so the backbone is set to cyclosporine wherever prophylaxis is known."),
    "agvhd": ("recoded", "agvhd", "Source 1/0 event flag."),
    "agvhd_grade": ("direct", "agvhd_grade", "Glucksberg grade."),
    "agvhd_day_rel_transplant": ("derived", "agvhd_date - transplant_date", "Calendar onset date converted to a day relative to transplant, masked by the event."),
    "gut_gvhd": ("unsupported", "agvhd", "aGVHD is recorded overall with no organ breakdown anywhere in the source."),
    "gut_gvhd_stage": ("unsupported", "agvhd_grade", "Only an overall grade exists; no organ stage."),
    "gut_gvhd_day_rel_transplant": ("unsupported", "agvhd_date", "Only an overall onset date exists; no organ-specific day."),
    "skin_gvhd": ("unsupported", "agvhd", "No organ breakdown in the source."),
    "skin_gvhd_stage": ("unsupported", "agvhd_grade", "Only an overall grade exists."),
    "skin_gvhd_day_rel_transplant": ("unsupported", "agvhd_date", "Only an overall onset date exists."),
    "liver_gvhd": ("unsupported", "agvhd", "No organ breakdown in the source."),
    "liver_gvhd_stage": ("unsupported", "agvhd_grade", "Only an overall grade exists."),
    "liver_gvhd_day_rel_transplant": ("unsupported", "agvhd_date", "Only an overall onset date exists."),
    "cgvhd": ("recoded", "cgvhd", "Source 1/0 event flag; constant 0 in this cohort, a genuine all-negative column."),
    "anc_engraftment": ("recoded", "Engraphment", "Source 0/1 flag (source spelling)."),
    "anc_engraftment_day_rel_transplant": ("unavailable", "", "No engraftment day column in the source."),
    "death": ("recoded", "death", "Source 1/0 event flag."),
    "cause_of_death": ("limited", "cause_of_death", "EBMT registry code retained as EBMT_code_N rather than a text cause; masked by the death event."),
    "death_day_rel_transplant": ("derived", "tte_death", "Retained only for death events, so censoring times are never read as death times."),
    "relapse": ("recoded", "relapse", "Source 1/0 event flag."),
    "relapse_day_rel_transplant": ("derived", "tte_relapse", "Contains event or censoring time, so retained only for relapse events."),
    "end_observation_reason": ("derived", "death, censor", 'death -> "death"; otherwise a recorded censor day -> "EOS".'),
    "end_observation_day_rel_transplant": ("derived", "tte_death, censor", "tte_death for deaths (earlier than the planned censor day), otherwise the planned end-of-follow-up day."),
}

JAROSCH = {
    "sample-id": ("exact", "Run", "Renamed from Run; copied as character without modification."),
    "study": ("derived", "constant", 'Set to "Jarosch".'),
}

LIU = {
    "sample-id": ("exact", "sample-id", "Copied as character without modification."),
    "study": ("derived", "constant", 'Set to "Liu"; the Liu2017 suffix was dropped 2026-08-19.'),
    "person": ("derived", "host_subject_id", "Natural-sort crosswalk to Liu_NN."),
    "timepoint": ("derived", "study design", "Every subject was sampled once before conditioning began, so every row is pre-conditioning by design; no sample day or date exists."),
    "sex": ("recoded", "sex", "Mapped to female | male."),
    "age": ("derived", "age, donor_or_patient", "Years; donor rows set to NA."),
    "disease": ("derived", "disease, donor_or_patient", 'Expanded to the shared disease vocabulary; donor rows -> "none".'),
    "transplant_type": ("recoded", "donor_source", 'pbsc | marrow | cord+cord mapped to the canonical graft vocabulary; donor rows -> "none".'),
    "conditioning_intensity": ("recoded", "conditioning_intensity", 'High -> MAC, Intermediate -> RIC, Low -> NMA. The Low group is coded NMA despite the paper labelling it "RIC" parenthetically, because its regimens (Flu/TBI, Cy/ATG) are NMA.'),
    "conditioning_regimen": ("recoded", "chemotherapy_regimen", "Dose annotations in parentheses stripped, string split on /, TBI and ATG removed into their own columns, remaining tokens mapped and sorted."),
    "conditioning_tbi": ("derived", "chemotherapy_regimen", "TBI token detected in the regimen string."),
    "conditioning_serotherapy": ("derived", "chemotherapy_regimen", "ATG token detected in the regimen string."),
    "gvhd_prophylaxis": ("derived", "cyclosporine, tacrolimus, methotrexate, mmf, sirolimus", "Five one-hot drug columns collapsed to the partner-agent category cni-mtx | cni-mmf; sirolimus is constant no. Patient-level one-hots are treated as authoritative over the dictionary's Table 1 counts, which appear transposed."),
    "gvhd_prophylaxis_cni": ("derived", "cyclosporine, tacrolimus", "Backbone identity taken from the one-hot CNI columns."),
    "agvhd": ("recoded", "agvhd", "Source 1/0 event flag; donor rows NA."),
    "agvhd_grade": ("recoded", "agvhd_severity", "Free-text severity parsed to a numeric overall grade."),
    "agvhd_day_rel_transplant": ("direct", "time_to_agvhd", "Overall onset day."),
    "gut_gvhd": ("derived", "agvhd, agvhd_organ", 'Membership in the free-text organ list; "upper gut" is deliberately combined into gut, reproducing the source agvhd_gut column exactly.'),
    "gut_gvhd_stage": ("derived", "agvhd_severity + agvhd_organ", "Overall grade applied to every organ named; a composite grade, not a true organ stage."),
    "gut_gvhd_day_rel_transplant": ("derived", "time_to_agvhd + agvhd_organ", "Overall onset day applied to every organ named."),
    "skin_gvhd": ("derived", "agvhd, agvhd_organ", "Membership in the free-text organ list."),
    "skin_gvhd_stage": ("derived", "agvhd_severity + agvhd_organ", "Overall grade applied to every organ named."),
    "skin_gvhd_day_rel_transplant": ("derived", "time_to_agvhd + agvhd_organ", "Overall onset day applied to every organ named."),
    "liver_gvhd": ("derived", "agvhd, agvhd_organ", "Membership in the free-text organ list."),
    "liver_gvhd_stage": ("derived", "agvhd_severity + agvhd_organ", "Overall grade applied to every organ named."),
    "liver_gvhd_day_rel_transplant": ("derived", "time_to_agvhd + agvhd_organ", "Overall onset day applied to every organ named."),
    "cgvhd": ("derived", "cgvhd_severity", "A staged recipient is an event; a blank recipient row is a confirmed negative; donor rows NA."),
    "cgvhd_stage": ("recoded", "cgvhd_severity", "Stage 1/2/3 aligned with Vallet's NIH mild/moderate/severe onto 1/2/3."),
    "cgvhd_day_rel_transplant": ("unsupported", "time_to_cgvhd", "time_to_cgvhd duplicates time_to_agvhd in 78 of 79 rows and its missingness does not track cgvhd_severity, so it is not a usable chronic onset time."),
    "anc_engraftment": ("recoded", "anc_engrafment", "yes -> 1; no -> 0 (source spelling); donor rows NA."),
    "anc_engraftment_day_rel_transplant": ("direct", "days_to_anc_engrafment", "Masked by the engraftment event."),
    "platelet_engraftment": ("recoded", "platelet_engrafment", "yes -> 1; no -> 0; donor rows NA."),
    "platelet_engraftment_day_rel_transplant": ("direct", "days_to_platelet_engrafment", "Masked by the engraftment event."),
    "death": ("recoded", "deceased", "Source 1/0 event flag; donor rows NA."),
    "cause_of_death": ("recoded", "etiology_of_death", "Free text mapped to canonical semicolon-separated cause phrases; masked by the death event."),
    "death_day_rel_transplant": ("direct", "time_to_death", "Masked by the death event."),
    "relapse": ("recoded", "relapsed", "yes -> 1; no -> 0; donor rows NA."),
    "relapse_day_rel_transplant": ("direct", "days_at_relapse", "Masked by the relapse event."),
    "end_observation_reason": ("derived", "deceased", 'deceased -> "death"; otherwise "EOS".'),
    "end_observation_day_rel_transplant": ("derived", "right_censor_time, time_to_death", "Death day where recorded, otherwise the right-censor time. Two documented exceptions: NYYC95BI (censor 365 > death 345, death day used) and CCHWVERY (deceased with no death time, censor 100 used)."),
    "bloodstream_infection": ("recoded", "infection_duringafter_transplant, infection_details", "Two free-text columns looked up against hand-classified crosswalk maps; either mapping to 1 makes the recipient BSI-positive. NA -> 0, since 'not documented' and 'not assessed' are indistinguishable here. Donor rows NA."),
}

VALLET = {
    "sample-id": ("exact", "sample-id", "Copied as character without modification."),
    "study": ("derived", "constant", 'Set to "Vallet".'),
    "person": ("derived", "allozithro_id", "Natural-sort crosswalk to Vallet_NN."),
    "timepoint": ("recoded", "j.hsct, sample.time, dat.cond", "Study-specific override: pre-conditioning vs conditioning is decided by whether the sample predates the recorded conditioning start date; samples from day -1 onward use the shared day rule."),
    "sex": ("recoded", "gender", "Mapped to female | male."),
    "age": ("direct", "age", "Years, retained unrounded."),
    "disease": ("recoded", "diagnosis2", "Expanded to the shared disease vocabulary."),
    "nutrition": ("recoded", "nutrition", "Mapped to the canonical nutrition vocabulary."),
    "transplant_type": ("recoded", "csh_type", "PBC -> peripheral blood stem cells; cord blood -> umbilical cord blood; bone marrow -> bone marrow."),
    "transplant_date": ("direct", "dat.hsct", "Parsed to ISO YYYY-MM-DD."),
    "sample_date": ("direct", "sample.time", "Parsed to ISO YYYY-MM-DD."),
    "sample_day_rel_transplant": ("direct", "j.hsct", "Day relative to transplant."),
    "conditioning_intensity": ("recoded", "conditioning", "myeloablative -> MAC; non myeloablative -> NMA. No RIC patients in this cohort."),
    "gvhd_prophylaxis": ("recoded", "gvhd_proph_type", "Three source levels collapsed to cni-mtx | cni-mmf | other."),
    "gvhd_prophylaxis_cni": ("derived", "gvhd_proph_type", 'All recorded regimens are cyclosporine-based (the source spells it "ciclosporin" and "cyclosporin"); "other" leaves the backbone NA.'),
    "agvhd": ("recoded", "agvhd", "Three-level competing-risk code: 0 -> 0, 1 -> 1, 2 (died before aGVHD, n = 25) -> 0. Those 25 are informatively censored; fit competing risks from the raw code if that matters."),
    "agvhd_grade": ("direct", "grad.agvhd", "Glucksberg/Seattle grade. Three agvhd = 1 patients have no recorded grade or date."),
    "agvhd_day_rel_transplant": ("derived", "dat.agvhd - dat.hsct", "Calendar onset date converted to a day relative to transplant, masked by the event."),
    "gut_gvhd": ("unsupported", "agvhd", "aGVHD is recorded overall with no organ breakdown anywhere in the source."),
    "gut_gvhd_stage": ("unsupported", "grad.agvhd", "Only an overall grade exists; no organ stage."),
    "gut_gvhd_day_rel_transplant": ("unsupported", "dat.agvhd", "Only an overall onset date exists."),
    "skin_gvhd": ("unsupported", "agvhd", "No organ breakdown in the source."),
    "skin_gvhd_stage": ("unsupported", "grad.agvhd", "Only an overall grade exists."),
    "skin_gvhd_day_rel_transplant": ("unsupported", "dat.agvhd", "Only an overall onset date exists."),
    "liver_gvhd": ("unsupported", "agvhd", "No organ breakdown in the source."),
    "liver_gvhd_stage": ("unsupported", "grad.agvhd", "Only an overall grade exists."),
    "liver_gvhd_day_rel_transplant": ("unsupported", "dat.agvhd", "Only an overall onset date exists."),
    "cgvhd": ("derived", "dat_cgvhd", "A recorded chronic GVHD date is an event; dat_cgvhd and cgvhd_grad are present or absent together, so a missing date is a confirmed negative."),
    "cgvhd_stage": ("recoded", "cgvhd_grad", "NIH mild | moderate | severe aligned onto 1/2/3."),
    "cgvhd_day_rel_transplant": ("derived", "dat_cgvhd - dat.hsct", "Calendar onset date converted to a day relative to transplant."),
    "death": ("derived", "dat.death", "A recorded death date is the event."),
    "death_date": ("direct", "dat.death", "Parsed to ISO YYYY-MM-DD."),
    "death_day_rel_transplant": ("derived", "dat.death - dat.hsct", "Calendar date converted to a day relative to transplant."),
    "relapse": ("recoded", "relapse01", "Source 1/0 event flag."),
    "relapse_day_rel_transplant": ("derived", "dat.relapse - dat.hsct", "Calendar date converted to a day relative to transplant, masked by the event."),
    "end_observation_reason": ("derived", "dat.lfu, dat.endstudy, dat.death", 'Earliest of last follow-up, end of study and death. "lost to follow up" never fires in this cohort but the logic is preserved.'),
    "end_observation_day_rel_transplant": ("derived", "dat.lfu, dat.endstudy, dat.death", "Earliest of the three dates, as a day relative to transplant. dat.endstudy is NA for 32/50 patients, whose last-follow-up date serves as the censoring date."),
    "bronchiolitis_obliterans": ("recoded", "bos", "yes -> 1; NA -> 0, because the data dictionary states missing means no BOS and manuscript Table 1 confirms exactly 2 cases."),
}

BY_STUDY = {
    "Artacho": ARTACHO,
    "DAmico": DAMICO,
    "Fujimoto": FUJIMOTO,
    "Ingham": INGHAM,
    "Jarosch": JAROSCH,
    "Liu": LIU,
    "Vallet": VALLET,
}

def main(out_path):
    missing_domain = [c for c in TARGET_COLS if c not in DOMAIN_OF]
    if missing_domain:
        raise SystemExit(f"target columns with no domain: {missing_domain}")

    rows = []
    for order, col in enumerate(TARGET_COLS, start=1):
        for study in STUDIES:
            status, source, note = BY_STUDY[study].get(col, DEFAULT)
            rows.append({
                "target_order": order,
                "domain_order": DOMAIN_ORDER[DOMAIN_OF[col]],
                "domain": DOMAIN_OF[col],
                "target_column": col,
                "study": study,
                "status": status,
                "source_column": source,
                "harmonization_rule": note,
            })

    fieldnames = ["target_order", "domain_order", "domain", "target_column",
                  "study", "status", "source_column", "harmonization_rule"]
    with open(out_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t",
                           lineterminator="\n")
        w.writeheader()
        w.writerows(rows)

    print(f"wrote {len(rows)} rows to {out_path}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "harmonization_provenance.tsv")
