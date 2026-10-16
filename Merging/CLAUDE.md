# Merging/ — Harmonization Round 2 (Jarosch, OrbergMO, Spindelboek)

Working notes for adding three cohorts to the harmonized GVHD metadata. Written
2026-10-16 so the work can resume in a fresh session. The repo-root `CLAUDE.md`
still governs everything here, especially **"Harmonization Variable Additions"**
(coding contract, transmute() shadowing, QA, tests, decision-log shape,
stop-and-ask triggers) and **"Prompt Requests"**. This file does not restate
those rules; it records the plan, the state, and the per-study facts.

Update the **Status** table as each step finishes.

Work is driven by **Claude Code prompts** Sophie pastes into the Positron
terminal (root CLAUDE.md "Prompt Requests"). Phase A prompts are saved in
`Merging/Data_Dictionary_Scripts/` as `Round2_01_scaffold.txt`,
`Round2_02_first_pass.txt`, `Jarosch_parsing.txt`, `OrbergMO_parsing.txt`,
`Spindelboek_parsing.txt`. They all write `data_dictionaries.xlsx`, so run them
one at a time, never in parallel.

---

## Status

| Step | Jarosch | OrbergMO | Spindelboek |
|---|---|---|---|
| 0. Pre-flight (commit pending work, back up xlsx) | shared: todo (folded into prompt 01) | | |
| A1. Dictionary-ready source table | done (`jarosch_clinical_16s.tsv` written 10-16) | ready (`"missing"` -> NA done 10-16) | ready (`sample-id` added 10-16) |
| A2. Scaffold rows via `build_data_dictionary.R` | done (10-16) | done (10-16) | done (10-16) |
| A3. Technical / ID / constant meanings pass | todo (prompt 02) | todo (prompt 02) | todo (prompt 02) |
| A4. Study meanings pass (`<Study>_parsing.txt`) | todo (prompt written) | todo (prompt written) | todo (prompt written) |
| A5. Sophie reviews UNCERTAIN queue | todo | todo | todo |
| B. Jarosch mapping contract + dummy mapping | todo | n/a | n/a |
| C1. Labels, prefixes, palette, crosswalk wiring | todo | todo | todo |
| C2. Core identity + timing columns | todo | todo | todo |
| C3. Variable families (see list below) | todo | todo | todo |
| C4. Tests extended to nine cohorts, passing | todo | todo | todo |
| C5. End-of-round workbook batch + clear log | shared: todo | | |
| C6. Re-run `Merging_Metadata.qmd` | shared: blocked on real Jarosch mapping | | |

---

## Decisions taken with Sophie (2026-10-16)

- **Workbook batch.** Round 1 "still owed" edits and round 2 go into ONE
  combined update of `data_dictionaries_harmonized.xlsx` at C5. Do not fold
  round 1 separately.
- **Jarosch is not clean, accepted.** Join key is `Biopsy`. 53 runs vs 52
  biopsy rows with 16S, and some runs will not map; expected outcome is roughly
  8 biopsies/runs whose clinical metadata is entirely NA. That is not an error.
- **Jarosch / OrbergMO subject overlap** (both Regensburg): Sophie will check
  later. Not a blocker.
- **New schema column `sample_source`** = `patient` / `donor`. Spindelboek:
  from `sample_type`. Liu: from `donor_or_patient` (Liu donors already get
  `disease = "none"`; keep that). Every other study: `patient`. Place it
  next to `person` in `target_cols`; categorical covariate with a
  `sample_source_levels` vector and a validity QA table.
- **Spindelboek timing.** Design makes nearly every sample Follow-Up.
  `sample_day_rel_transplant` is filled only where `Time` is an exact day; the
  `<FMT day` upper bounds (86 rows) become NA. Timepoint still assigned.
- **Gut GVHD.** Upper and lower gut combine into `gut_gvhd` (same rule as Liu).
- **OrbergMO.** Sophie replaced the literal `"missing"` with NA in the source
  TSV, so `clean_chr()` is unchanged.

---

## Files in play

| Role | Path |
|---|---|
| Per-study raw dictionaries (scaffold + meanings) | `Merging/data_dictionaries.xlsx` |
| Scaffold builder | `Merging/build_data_dictionary.R` |
| Dictionary prompts from round 1 (reuse as templates) | `Merging/Data_Dictionary_Scripts/First_pass.txt`, `*_parsing.txt` |
| Harmonized workbook (Canonical_Schema, Value_Map, Coverage, Harmonization_Summary + study sheets) | `Merging/Harmonization/data_dictionaries_harmonized.xlsx` |
| Harmonizer / tests / decision log | `Merging/Harmonization/harmonize_gvhd_metadata.R`, `test_harmonize_gvhd_metadata.R`, `to_log/harmonization_decisions.md` |
| Variable-addition prompt template | `Merging/Harmonization/PROMPT_TEMPLATE.md` |
| Writes `Merging/merged_metadata.tsv` | `Merging/Merging_Metadata.qmd` (currently has a Jarosch stub: sample-id + study only) |
| Palette / study labels | `Functions/study_colors.R` |

Source metadata for the new cohorts:

| Cohort | Sample table | Clinical / supporting sources |
|---|---|---|
| Jarosch | `Jarosch2023/Metadata/Raw_metadata/meta_samples.csv` (53 ENA runs) | `Raw_metadata/meta_clinical.csv` (83 biopsy rows), `jarosch_metadata_mapping.xlsx`, `Manuscript/manuscript.pdf`, `Manuscript/Supplement 1.pdf` |
| OrbergMO | `OrbergMO2024/Metadata/orbergMO_meta_qiime.tsv` (269 x 15) | `Metadata/Parsing_metadata.qmd`, `Raw_metadata/meta_clinical1.xlsx`, `Raw_metadata/processing.Rmd` (authors' own code, best key for the integer codes), `Raw_metadata/processed.rds`, `Orberg2024/Manuscript/` (paper PDF + `mapping_wsm.xlsx`) |
| Spindelboek | `Spindelboek2021/Metadata/spindelboek_meta_qiime.tsv` (206 x 31) | `Metadata/Parsing_metadata.qmd` (hand-entered `patient_fmts` FMT-day table), `Raw_metadata/meta_clinical.xlsx`, `Manuscript/` PDF + `sj-doc-2-...doc` supplement |

---

## Step 0 — Pre-flight

1. **Commit the placeholder sheets.** `Merging/data_dictionaries.xlsx` is modified
   and uncommitted (empty `Jarosch`, `OrbergMO`, `Spindelboek` sheets added).
   `Spindelboek2021/Metadata/Parsing_metadata.qmd` and its `Raw_metadata/`
   inputs are untracked. Commit both before anything rewrites them.
2. **Round 1 workbook batch is still owed.** `data_dictionaries_harmonized.xlsx`
   was last written 2026-08-17, but the decision log has entries through
   2026-08-19, each ending in "Workbook edits still owed", and the log was
   never cleared. Decide with Sophie: fold round 1 into the workbook first
   (cleanest), or let it ride and do one combined batch at C5.
3. **Back up `data_dictionaries.xlsx`** before running `build_data_dictionary.R`.
   The script rewrites the whole workbook from its `studies` list with
   `write_xlsx()`; manual columns are carried forward only for sheets in that
   list.
4. **R is not on the PATH in the computer-side shell** used by cloud sessions.
   Follow the root CLAUDE.md fallback (apt-install R in the container, stage
   the TSVs, run there). In Positron locally, run normally.

---

## Phase A — Data dictionary (same process as round 1)

**A1. Dictionary-ready source table**, one row per sample (or per clinical unit
for Jarosch), with a `sample-id` column.
- OrbergMO: already ready.
- Spindelboek: the ID column is `Run`. Rename to `sample-id` in
  `Parsing_metadata.qmd` and re-export (preferred over teaching
  `ensure_sample_id()` another alias).
- Jarosch: there is no sample to clinical link yet, so the dictionary is built
  from the **clinical** side: `meta_clinical.csv` filtered to `16S data == "yes"`
  (52 biopsy rows, 39 patients), written to
  `Jarosch2023/Metadata/jarosch_clinical_16s.tsv`. The ENA run fields are
  boilerplate and can be documented in A3 from `meta_samples.csv` in a second
  block on the same sheet, or skipped.

**A2. Scaffold.** Add the three cohorts to `studies` in
`build_data_dictionary.R`:
- `OrbergMO`: `patient_key = "Patient"`
- `Spindelboek`: `patient_key = "Patient"`. Note 4 donor rows (cases 40, 50)
  have no `Patient`; `classify_variation()` drops NA keys, so check their
  columns are not misclassified. `case` is an alternative key.
- `Jarosch`: `patient_key = "Patient"` on `jarosch_clinical_16s.tsv`.
Run, confirm all nine sheets survive with round 1 annotations intact, compare
variation counts printed to console.

**A3. Technical pass.** Adapt `First_pass.txt` to the three new sheets only:
fill `meaning` + `notes` for CONSTANT / UNIQUE_ID / ALL_MISSING rows, with the
"UNCERTAIN: constant in this study but analytically meaningful" flag.

**A4. Meanings pass, one prompt per study,** modeled on
`Data_Dictionary_Scripts/Vallet_parsing.txt` (meaning + units + value key;
UNCERTAIN prefix with basis; flag redundant columns and one-hot groups; print
the UNCERTAIN queue at the end). Save each as
`Data_Dictionary_Scripts/<Study>_parsing.txt`. Study-specific hints to include:
- **Jarosch**: German center (Regensburg). `GvHD (Lerner)` is the histologic
  Lerner grade of the biopsy; `clinical GvHD total` / `clinical GvHD GI` are the
  clinical overall grade and GI stage; `d after aHSCT` is the biopsy day;
  `Bx Timepoint` is Screening / Onset / Course (one row is misspelled
  `Sceening`). Age and donor age are 5-year bands, not numbers.
- **OrbergMO**: integer codes with no key in the TSV (`Diagnosis` 0/1, `GVHD`
  from source `GVHD_012`, `NY` 0/1/2, `Prophylaxe` 0/1/2/"missing",
  `Antiviral_therapy` 0/1/"missing"). `processing.Rmd` and `mapping_wsm.xlsx`
  are where the codes are defined; read them before the paper. `Day` is source
  `Time.num`; `Timepoint` includes `COND` (Day -7). Two centers, MUC and REG.
- **Spindelboek**: FMT case series for steroid-refractory aGVHD (so
  `gut_gvhd` is constant 1 by design). `Time` is the sample day; "pre" samples
  are stored as `<FMT day` (86 rows) and are upper bounds, not days.
  `fmt_cycle_day` comes from the hand-entered `patient_fmts` table in
  `Parsing_metadata.qmd`; verify it against the paper. Semicolon-joined values
  (`Donor sex` "female; male", `Donor match` "HID; HID", two prophylaxis
  regimens) suggest second transplants. Infection fields are parallel
  semicolon lists with days from HSCT and from FMT.

**A5. Review.** Sophie clears the UNCERTAIN queue for each study before its
harmonization starts. Commit each study's dictionary as
`[<Study>] data dictionary meanings`.

---

## Phase B — Jarosch mapping scaffolding

**What is known (checked 2026-10-16).** 53 ENA runs; 52 clinical rows with
16S, 39 patients, 44 distinct patient-days, 46 distinct (Richness, Shannon)
profiles. `Biopsy` is unique among the 52 rows. Several fields vary **within**
a patient-day (GvHD grade, steroid status, the alpha metrics, and one
patient's age band), so patient-day alone is not a clean join key. The
alpha-diversity matching attempt (`jarosch_sample_to_clinical.tsv`,
`attempted_matching_1/2` sheets) is exploratory, not a mapping.

**Mapping contract (proposed default, confirm when the authors' file arrives).**
`Jarosch2023/Metadata/jarosch_sample_mapping.tsv`, one row per run:

| column | meaning |
|---|---|
| `sample-id` | ENA run accession (ERR...), matches the QIIME table |
| `Patient` | as in `meta_clinical.csv` ("Patient 01") |
| `Biopsy` | as in `meta_clinical.csv`; NA allowed if authors give patient-day only |
| `day_after_ahsct` | required when `Biopsy` is NA |
| `mapping_source` | `"authors"` for the real file, `"DUMMY"` for the test file |

**Dummy.** `Jarosch2023/Metadata/make_dummy_mapping.R` writes
`jarosch_sample_mapping_DUMMY.tsv` with a fixed seed: every run gets a random
16S biopsy, a few runs left unmapped and one biopsy given two runs, so the
unmatched and many-to-one paths are exercised. Deliberately **not** built from
the alpha-diversity matches, so plausible-looking links cannot leak into
analysis.

**Harmonizer behavior.**
- `harmonize_jarosch(samples, clinical, mapping)` joins sample -> mapping ->
  clinical and then codes like any other study.
- Loader prefers the real file, falls back to the dummy with a loud `warning()`.
- QA table `jarosch_mapping_status` (mapping_source, n mapped, n unmapped, runs
  mapped to more than one clinical row). Empty-when-correct table
  `jarosch_unmapped_runs`.
- `Merging_Metadata.qmd` refuses to write `merged_metadata.tsv` while
  `mapping_source == "DUMMY"`.
- Tests split into mapping-agnostic assertions (vocabularies, masking, column
  set) and mapping-dependent counts in one clearly marked block, so the real
  mapping only requires updating that block.

---

## Phase C — Harmonization

**C1. Wiring.** Add to `study_labels`, `person_prefixes`, `harmonize_all()`
(arguments, `ensure_sample_id`, crosswalk, `bind_rows`), and
`Functions/study_colors.R` (Jarosch already exists there; OrbergMO and
Spindelboek need hues, and `study_key()` must accept them). Proposed labels:
`Jarosch`, `OrbergMO`, `Spindelboek`. `OrbergMO` keeps its suffix because
`OrbergSJ` will join later as a separate cohort; confirm with Sophie. Write any
Orberg helper so OrbergSJ can reuse it.

**C2. Core columns** for each study: `sample-id`, `study`, `person`,
`sample_source` (new, all nine studies; see Decisions), `sex`, `age`,
`disease`, `sample_date`, `sample_day_rel_transplant`, `timepoint`.

**C3. Variable families**, one prompt per family across all three cohorts,
filled in from `PROMPT_TEMPLATE.md`, in round 1 order:
1. aGVHD triple + organ triples (gut, skin, liver), cGVHD triple
2. death (+ `death_date`, `cause_of_death`), relapse
3. transplant_type
4. conditioning (intensity, regimen, TBI, serotherapy)
5. gvhd_prophylaxis, gvhd_prophylaxis_cni
6. anc / platelet engraftment
7. end_observation reason + day
8. secondary outcomes (myelosuppression, mucositis, bloodstream_infection, bronchiolitis_obliterans)
9. nutrition
Columns a study does not record are logged as "not recorded -> NA", not omitted.

**C4. Tests.** Extend Part 2 of `test_harmonize_gvhd_metadata.R` to nine
cohorts; add per-study cross-tabs; run against the real TSVs and paste the
output into the decision-log entry.

**C5. End-of-round workbook batch** (its own prompt, starts with the
`~$data_dictionaries_harmonized.xlsx` lock check): copy the three study sheets
into the harmonized workbook, add Canonical_Schema / Value_Map / Coverage /
Harmonization_Summary rows, then clear the "still owed" items from the log.

**C6. Re-run `Merging_Metadata.qmd`**, replacing the Jarosch stub. Blocked on the
real Jarosch mapping. This also clears the stale `Liu2017` rows noted in round 1.

---

## Stop-and-ask candidates still open

Resolved items moved to Decisions above. Still to raise when reached:

- **Spindelboek second transplants.** Semicolon-joined donor fields
  (`Donor sex` "female; male", `Donor match` "HID; HID", two prophylaxis
  regimens) suggest some patients had two transplants. Which one is day 0?
- **Spindelboek donor-only cases 40 and 50** (4 rows) have no `Patient`. They
  need a `person` value (donor-specific ID?) or NA.
- **Jarosch age** is a 5-year band; `age` is numeric. NA, band midpoint, or an
  `age_band` column.
- **Jarosch outcome source.** Histologic Lerner grade vs clinical grade/GI
  stage for `agvhd_grade` / `gut_gvhd_stage`; these are status at biopsy, not
  onset events with days (only `Bx Timepoint == "Onset"` approximates onset).
- **OrbergMO three-level `GVHD` (0/1/2) and `NY`**: confirm the key before
  collapsing to binary (Vallet competing-risk precedent).

---

## Commit messages

`[Merging] ...` for shared scaffolding and the workbook; `[Jarosch2023] ...`,
`[OrbergMO2024] ...`, `[Spindelboek2021] ...` for study-specific changes.
