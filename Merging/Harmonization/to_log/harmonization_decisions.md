# Harmonization decision log

Running record of harmonization changes made after the first pass. Each entry
notes what changed, why, and what still needs to be reflected in
`data_dictionaries_harmonized.xlsx`. At the end of this round these decisions
get folded into the workbook (`Canonical_Schema`, `Value_Map`,
`Harmonization_Summary`, and the per-study sheets) and the log is cleared.

Code: `Merging/Harmonization/harmonize_gvhd_metadata.R`

---

## 2026-08-17 — Binary outcomes recoded yes/no -> 1/0

**Decision.** `gut_gvhd`, `death` and `relapse` are now coded `1` (event
occurred) / `0` (event did not occur). `NA` continues to mean unknown or not
applicable. `sex` is unchanged (still `male` / `female`) and disease labels are
unchanged.

**Why.** Numeric event coding drops straight into the modelling code without a
recode step, and matches how the source studies (Ingham `death`/`relapse`,
Fujimoto `AGVHD`, Vallet `relapse01`) already store their event indicators.

**Implementation.** New shared helper `harmonize_binary(event)` takes a logical
vector and returns `"1"` / `"0"` / `NA`. Every study's event logic now produces
a logical and is passed through it, so the coding lives in exactly one place.
Downstream masks that previously tested `== "yes"` now test `== "1"`
(Fujimoto and Liu `gut_gvhd_day_rel_transplant`).

**QA.** `build_qa()$invalid_binary_values` now flags anything that is not
`"0"` or `"1"`.

**Workbook edits still owed.**

- `Canonical_Schema`: rows 10 (`gut_gvhd`), 13 (`death`), 17 (`relapse`) —
  change `canonical_format_or_values` from `yes | no` to `1 | 0`.
- `Value_Map`: update every yes/no target mapping.
- Per-study sheets, `harmonized_values` column: Artacho `gut_gvhd_grade`,
  DAmico `gut_gvhd_grade` / `Outcome_at_100`, Fujimoto `AGVHD` /
  `AGVHD_Organ`, Ingham `death` / `relapse`, Liu `agvhd_gut` / `deceased` /
  `relapsed`, Vallet `dat.death` / `relapse01`.

---

## 2026-08-17 — New target column `timepoint`

**Decision.** Added `timepoint` to `target_cols`, positioned immediately after
`person`. It is a sample-level ordered phase label with six canonical values:

| value | shared day rule (day relative to transplant, day 0 = graft infusion) |
|---|---|
| `pre-conditioning` | day < -7 |
| `conditioning` | -7 <= day < -1 |
| `transplant` | -1 <= day <= 1 |
| `pre-engraftment` | 1 < day < 14 |
| `engraftment` | 14 <= day < 21 |
| `follow-up` | day >= 21 |

Hyphenated spelling is canonical throughout (`pre-conditioning`, not
`preconditioning`). Values are exported as an exported vector
`timepoint_levels` in the stated order, so downstream code can factor on it.

**Why.** Sample day relative to transplant is not comparable across studies
that sample on different schedules, and two studies (Liu, and the Fujimoto
`pre` label) have no numeric day at all. A coarse phase label gives a common
grouping variable for cross-study comparison while
`sample_day_rel_transplant` is retained unchanged for anything that needs the
exact day.

**Implementation.** New shared function `harmonize_timepoint(day)` implements
the table above. Studies with a usable numeric day call it directly; studies
without one override inside their own `harmonize_*` function.

### Per-study rules

| study | rule | source columns |
|---|---|---|
| Artacho | shared day rule on the numeric `Timepoint` | `Timepoint` |
| DAmico | shared day rule on the numeric `Timepoint` | `Timepoint` |
| Fujimoto | `pre` -> `pre-conditioning`; otherwise pull the integer following `day` from `Timepoint` and apply the shared rule | `Timepoint` |
| Ingham | shared day rule on the numeric `timepoint` | `timepoint` |
| Liu2017 | every row -> `pre-conditioning` | none (fixed) |
| Vallet | day >= -1: shared rule on `j.hsct`. day < -1: `sample.time` < `dat.cond` -> `pre-conditioning`, else `conditioning` | `j.hsct`, `sample.time`, `dat.cond`, `dat.hsct` |

**Decisions taken along the way.**

- *Artacho pre/post.* Artacho carries both `Timepoint_Class` (pre/post) and a
  numeric `Timepoint`. The numeric day wins: it is more precise and correctly
  splits `post` (days 11-15) into `pre-engraftment` and `engraftment`, and day-0
  `pre` samples into `transplant`. `Timepoint_Class` is not used.
- *Liu2017.* All samples are single pre-transplant draws with no day or date in
  the source, so the label is assigned by study design rather than derived.
  This includes donor rows.
- *Fujimoto `pre`.* Corresponds to the `Baseline1` preconditioning baseline
  flag. `sample_day_rel_transplant` stays `NA` for these rows — the timepoint
  label is asserted, not derived, so no fake day is manufactured.
- *Vallet.* Vallet is the only study recording an actual conditioning start
  date (`dat.cond`), so its pre-transplant split uses the real regimen start
  instead of the shared -7 day cutoff. Post-transplant samples fall back to the
  shared rule on `j.hsct`. If either date is missing the shared rule is used.

**QA.** `build_qa()` gains three tables: `invalid_timepoint_values` (anything
outside `timepoint_levels`), `missing_timepoint_samples` (rows where
`timepoint` is `NA`, with the sample day for context), and
`timepoint_by_study` (counts per study, ordered by phase — the sanity check on
whether a study's samples landed in plausible phases).

**Workbook edits still owed.**

- `Canonical_Schema`: insert `timepoint` as order 4 and renumber 4-18 to 5-19.
  `semantic_type` = ordinal/categorical; `canonical_format_or_values` = the six
  values in order; `key_rule` = derived from day relative to transplant, with
  the Liu / Fujimoto-`pre` / Vallet overrides noted.
- `Harmonization_Summary` and `Coverage`: add a `timepoint` row.
- `Value_Map`: add the day-bin table and the three study overrides.
- Per-study sheets, `harmonized_name` column: add `timepoint` to Artacho
  `Timepoint`, DAmico `Timepoint`, Fujimoto `Timepoint`, Ingham `timepoint`,
  Vallet `j.hsct` (plus note `sample.time` and `dat.cond` as inputs). Liu has
  no source column to annotate — record the fixed assignment in the sheet
  notes.
- Artacho `Timepoint_Class`: note explicitly that it is *not* used for
  `timepoint`, so the choice is not silently re-litigated later.

---

## 2026-08-17 — Time-to-event outcome blocks for skin, liver, overall aGVHD and cGVHD

**Decision.** Every time-to-event outcome now uses the same shape: an
`<outcome>` column coded 1/0, an `<outcome>_day_rel_transplant` column, and a
severity column where the source supports one. The outcome set is:

| outcome | severity column | meaning |
|---|---|---|
| `agvhd` | `agvhd_grade` | overall acute GVHD, composite Glucksberg/IBMTR grade 0-4 |
| `gut_gvhd` | `gut_gvhd_stage` | gut involvement |
| `skin_gvhd` | `skin_gvhd_stage` | skin involvement |
| `liver_gvhd` | `liver_gvhd_stage` | liver involvement |
| `cgvhd` | `cgvhd_stage` | chronic GVHD, 1 mild / 2 moderate / 3 severe |
| `death` | (none) | all-cause death |
| `relapse` | (none) | disease relapse |

Column order in `target_cols` groups them: overall aGVHD triple, then gut, skin,
liver, then cGVHD, then death and relapse. Harmonized output is 885 samples x 31
columns.

**Grade 0 codes as 0, not NA.** An organ stage of 0 is a confirmed negative, so
it becomes `0`. This preserves the denominators — Artacho alone has 91 confirmed
skin-negative and 156 liver-negative samples that would have been thrown away as
unknown.

**Event days are masked by their own event.** A day is retained only where that
outcome equals 1, so censoring and diagnosis times can never be mistaken for
event times. QA table `unmasked_event_days` enforces this across all seven
outcomes.

### Two families of source encoding

- **Grade-per-organ** (Artacho, DAmico): a separate 0-4 stage per organ.
  Involvement is stage > 0, and `_stage` holds a true organ stage.
- **Organ-list** (Fujimoto, Liu): one overall grade plus a list of involved
  organs. Involvement is membership in the list, and the overall grade and
  overall onset day are applied to every organ named.
- **Overall-only** (Ingham, Vallet): no organ breakdown at all. Organ columns
  stay NA; only the `agvhd` triple is populated.

Shared helpers: `organ_involved()`, `organ_patterns`, `parse_liu_agvhd_grade()`,
`harmonize_cgvhd_stage()`.

### Per-study rules

| study | agvhd | organ outcomes | cgvhd |
|---|---|---|---|
| Artacho | `GVHD_grade` > 0; grade = `GVHD_grade`; day NA | gut/skin/liver from their own 0-4 grades; all days NA (source records no onset date) | not recorded -> NA |
| DAmico | any organ grade > 0; grade NA (no composite in source); day = `gvhd_day` | gut/skin/liver from their own grades; each involved organ gets `gvhd_day` | not recorded -> NA |
| Fujimoto | `AGVHD`; grade = `AGVHD_Severity`; day = `AGVHD_TTE` | `AGVHD_Organ` split on Gut/Skin/Liver; involved organs inherit `AGVHD_Severity` and `AGVHD_TTE` | not recorded -> NA |
| Ingham | `agvhd`; grade = `agvhd_grade`; day = `agvhd_date` − `transplant_date` | none in source -> NA | `cgvhd` (constant 0 in this cohort); stage and day NA |
| Liu2017 | `agvhd`; grade parsed from `agvhd_severity`; day = `time_to_agvhd` | `agvhd_organ` split; gut and upper gut combined; involved organs inherit severity and onset day | `cgvhd_severity` present -> 1; stage 1-3; **day NA** |
| Vallet | `agvhd` == 1; grade = `grad.agvhd`; day = `dat.agvhd` − `dat.hsct` | none in source -> NA | `dat_cgvhd` present -> 1; stage from `cgvhd_grad`; day = `dat_cgvhd` − `dat.hsct` |

### Decisions taken along the way

- <a name="gvhd-stage-note"></a>**`_stage` mixes two scales (gvhd_stage_note).**
  Artacho and DAmico put a genuine per-organ Glucksberg stage in the `_stage`
  columns. Fujimoto and Liu have no organ stage, only an overall composite
  grade, and per the decision on 2026-08-17 that overall grade is copied into
  each involved organ's `_stage`. So `gut_gvhd_stage` contains organ stages for
  Artacho/DAmico and overall grades for Fujimoto/Liu. **These are not the same
  quantity and should not be pooled without a study-level covariate.** The
  binary `gut_gvhd` column is unaffected and is safe to pool. See open
  questions — a `gvhd_stage_source` flag would make this filterable.
- **DAmico onset day is shared across organs.** `gvhd_day` is the day of first
  clinical aGVHD diagnosis in any organ. A patient with both gut and skin
  involvement therefore carries the same onset day on both. That is the
  source's resolution; it does not say which organ presented first.
- **Liu gut combines upper and lower GI.** "upper gut" counts as gut. Verified:
  the derived `gut_gvhd` reproduces the source `agvhd_gut` flag exactly (19
  positive, 38 negative, 22 donor NA), so this changes nothing versus the
  previous rule while also yielding skin and liver.
- **Liu ungraded aGVHD.** `agvhd_severity` values `yes` (n=8) and `suspected`
  (n=1) mean aGVHD occurred but was never assigned an IBMTR grade. These get
  `agvhd = 1` with `agvhd_grade = NA` rather than being forced onto the scale.
  `no` maps to grade 0.
- **Liu `time_to_cgvhd` is not used.** It equals `time_to_agvhd` in 78 of 79
  rows, and its missingness does not track `cgvhd_severity` at all: 19 rows with
  no cGVHD stage carry a time, while 4 rows staged Stage 2 carry none. It is a
  copy of the acute onset time, not a chronic one. Liu therefore contributes
  `cgvhd` and `cgvhd_stage` but `cgvhd_day_rel_transplant` is NA.
- **Liu blank `cgvhd_severity` is a confirmed negative.** All 57 recipients have
  either a stage (19) or a blank (38), so blank means no chronic GVHD rather
  than not recorded. Donors stay NA.
- **Vallet competing-risk code 2 maps to 0.** `agvhd` is three-level: 0 = no
  aGVHD (n=21), 1 = aGVHD (n=72), 2 = died before developing aGVHD (n=25). The
  25 never developed aGVHD, so the binary outcome is 0 — but their follow-up
  was truncated by death and they are informatively censored. Fit a
  competing-risks model from the raw three-level code, not from this column.
- **Vallet: 3 patients have `agvhd` = 1 with no date and no grade.** They keep
  `agvhd = 1` with NA grade and NA day.
- **cGVHD severity aligns two different instruments.** Liu reports Shulman-style
  "Stage 1/2/3"; Vallet reports NIH consensus "mild/moderate/severe". Both are
  mapped onto 1/2/3 so `cgvhd_stage` is usable across studies. They share an
  ordinal structure but are not the same instrument — treat cross-study
  severity comparisons with the same caution as `gvhd_stage_note` above.
- **Ingham cGVHD is a real all-negative.** `cgvhd` is present in the source and
  constant 0 across the cohort, so Ingham contributes 96 confirmed cGVHD
  negatives (plus the one metadata-less row).

### Bug found and fixed

`transmute()` resolves bare names against the source data frame before the
calling environment. Three locals were being silently shadowed by raw columns of
the same name: DAmico's `gvhd_day`, and Ingham's `transplant_date` and
`agvhd_date`. The Ingham ones were a hard error (unparsed `dd-mm-yyyy` character
minus a Date); DAmico's worked only by luck, because readr happened to parse
`gvhd_day` as numeric, which bypassed the `as_num()` cleaning. All three are now
suffixed (`gvhd_day_num`, `transplant_date_parsed`, `agvhd_date_parsed`) with a
comment explaining why. **Watch for this whenever a local shares a name with a
source column.**

### New QA tables

- `unmasked_event_days` — an event day present without its event equal to 1.
- `organ_without_agvhd` — an organ outcome of 1 while overall `agvhd` is 0.
- `outcome_coverage` — per study and outcome: n, n_event, n_nonevent, n_missing.
  This is the table to read first when judging what a study can contribute.
- `invalid_binary_values` now loops over `binary_outcome_cols` instead of naming
  three columns, so new outcomes are validated automatically.

### Verification

`Merging/Harmonization/test_harmonize_gvhd_metadata.R` — 12 helper unit tests
plus 24 end-to-end assertions run against the six real `*_meta_qiime.tsv` files.
All pass. Run with `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`
from the repository root, or set `ODSI_ROOT`.

Observed event counts (n_event / n_nonevent / n_missing):

| study | agvhd | gut | skin | liver | cgvhd |
|---|---|---|---|---|---|
| Artacho (172) | 93/79/0 | 58/114/0 | 81/91/0 | 16/156/0 | 0/0/172 |
| DAmico (104) | 59/45/0 | 46/58/0 | 39/65/0 | 21/83/0 | 0/0/104 |
| Fujimoto (315) | 151/164/0 | 105/210/0 | 94/221/0 | 11/304/0 | 0/0/315 |
| Ingham (97) | 55/41/1 | 0/0/97 | 0/0/97 | 0/0/97 | 0/96/1 |
| Liu2017 (79) | 30/27/22 | 19/38/22 | 13/44/22 | 3/54/22 | 19/38/22 |
| Vallet (118) | 72/46/0 | 0/0/118 | 0/0/118 | 0/0/118 | 65/53/0 |

**Workbook edits still owed.**

- `Canonical_Schema`: insert the 12 new rows (`agvhd`, `agvhd_grade`,
  `agvhd_day_rel_transplant`, the skin and liver triples, the cGVHD triple) in
  the order above and renumber. Record the `gvhd_stage_note` caveat in
  `key_rule` for all four `_stage` columns.
- `Value_Map`: add the organ-list splitting rules, the Liu severity parse, the
  cGVHD 1-3 mapping for both vocabularies, and the Vallet competing-risk
  collapse.
- `Coverage` and `Harmonization_Summary`: add rows for the new outcomes; the
  event-count table above can be pasted in directly.
- Per-study sheets, `harmonized_name` column: Artacho `GVHD_grade`,
  `skin_gvhd_grade`, `liver_GVHD_grade`; DAmico `Skin_gvhd_grade`,
  `liver_gvhd_grade`, and extend `gvhd_day` to all four day columns; Fujimoto
  `AGVHD`, `AGVHD_Severity`, `AGVHD_TTE`, `AGVHD_Organ`; Ingham `agvhd`,
  `agvhd_grade`, `agvhd_date`, `cgvhd`; Liu `agvhd`, `agvhd_organ`,
  `agvhd_severity`, `cgvhd_severity`; Vallet `agvhd`, `grad.agvhd`,
  `dat.agvhd`, `dat_cgvhd`, `cgvhd_grad`.
- Liu `time_to_cgvhd`: mark explicitly as unused with the duplication evidence,
  so it is not picked up in a later pass.
- Liu `agvhd_gut`: mark as superseded by `agvhd_organ` (kept as a cross-check).

---

## 2026-08-18 — nutrition

**Decision.** One new column `nutrition` added after `disease`. Canonical vocabulary: `parenteral`, `enteral`, `mixed`, `oral`. Shared helper `harmonize_nutrition()` with `nutrition_levels` vector handles all source spellings including Vallet's French "parenterale".

**Why.** Nutritional support type is a covariate of interest for microbiome composition analysis in the transplant setting.

### Per-study rules

| Study | Source column | Construction |
|---|---|---|
| Artacho | `Parenteral.Nutrition` | Yes → parenteral; No → enteral; no NAs |
| DAmico | `Nutritional_Regimen` | detect "EN" and/or "PN" tokens in free-text string: EN-only → enteral; PN-only → parenteral; both → mixed |
| Fujimoto | — | Not recorded; NA |
| Ingham | — | Not recorded; NA |
| Liu2017 | — | Not recorded; NA |
| Vallet | `nutrition` | "parenterale" → parenteral; "enteral" → enteral; "oral" → oral; NA stays NA |

### Decisions taken along the way

- **Artacho**: Column is `Parenteral.Nutrition` (mixed case, not `parenteral.nutrition`). Values are `Yes`/`No` with no NAs: Yes=30 patients (parenteral), No=75 patients (enteral).
- **DAmico**: `Nutritional_Regimen` encodes time-windows per modality (e.g. `EN (+0/+12)`, `PN (+0/+16)`, `EN (+1/+10); PN (+10/+13)`). Detection of `"EN"` and `"PN"` substrings classifies the regimen. Per-patient counts: EN-only=10, PN-only=7, both (mixed)=3. No NAs.
- **Vallet**: Source column is literally named `nutrition`, creating a transmute() shadowing risk. Pre-computed as `nutrition_vallet` before the transmute call. Values: enteral=8, oral=29, parenterale=11, NA=2 patients. The `oral` category appears here (and nowhere else across the six studies).
- **transmute() shadowing**: Artacho pre-computes `pn_flag` and `nutrition_artacho`; DAmico `reg` and `nutrition_damico`; Vallet `nutrition_vallet`. None of these names collide with source columns.

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`. All 86 tests passed (14 new tests added for nutrition).

`noncanonical_nutrition_values` QA table is empty. Per-study nutrition distribution:

| Study | parenteral | enteral | mixed | oral | NA |
|---|---|---|---|---|---|
| Artacho | 46 samples | 126 samples | — | — | 0 |
| DAmico | 25 samples | 47 samples | 13 samples | — | 0 |
| Fujimoto | — | — | — | — | all 315 |
| Ingham | — | — | — | — | all 97 |
| Liu2017 | — | — | — | — | all 79 |
| Vallet | 28 samples | 19 samples | — | 68 samples | 3 |

**Workbook edits still owed.**
- `Canonical_Schema`: add row for `nutrition` (type: categorical, vocabulary: parenteral | enteral | mixed | oral).
- `Value_Map`: add mappings for each study (Artacho Yes/No, DAmico EN/PN tokens, Vallet parenterale).
- `Coverage`: add row for `nutrition` showing per-study availability.
- `Harmonization_Summary`: note that only four of six studies record nutrition type.

---

## 2026-08-18 — anc_engraftment and platelet_engraftment

**Decision.** Four new columns added immediately after the cGVHD block, before death:
- `anc_engraftment` (1/0): ANC ≥ 500/µL sustained
- `anc_engraftment_day_rel_transplant`: day relative to transplant
- `platelet_engraftment` (1/0): platelets ≥ 20,000/µL untransfused
- `platelet_engraftment_day_rel_transplant`: day relative to transplant

**Why.** These are the recovery landmarks the pre-engraftment and engraftment timepoint bins are named for. Having them as explicit outcomes lets us validate the timepoint bins against observed recovery data.

### Per-study rules

| Study | Source columns | Construction |
|---|---|---|
| Artacho | — | Not recorded; all four columns NA |
| DAmico | `PMN_day`, `PLT_over_20000_day` | Day present → event 1; day absent → event 0, NA day |
| Fujimoto | — | Not recorded; all four columns NA |
| Ingham | `Engraphment` (binary flag, no day) | `anc_engraftment` reflects the flag; day and platelet columns NA |
| Liu2017 | `anc_engrafment`, `days_to_anc_engrafment`, `platelet_engrafment`, `days_to_platelet_engrafment` | yes → 1 + day; no → 0 + NA day; donors NA |
| Vallet | — | Not recorded; all four columns NA |

### Decisions taken along the way

- **DAmico — no separate event flag**: The spec requires treating a present day as event=1 and an absent day as event=0. All 20 unique patients have `PMN_day`, so `anc_engraftment` is 1 for all DAmico patients. One patient (E10, `Outcome_at_100 = "a"`, alive at day +100) has `PLT_over_20000_day = NA`, so `platelet_engraftment = 0` for that patient. **Caveat logged here:** a missing PLT day in this study cannot be distinguished from a patient who failed to achieve platelet recovery — the source records no separate flag. E10 survived to day +100, so delayed engraftment after the observation window cannot be ruled out.
- **Liu — source spelling is single-t**: Column names are `anc_engrafment`, `platelet_engrafment`, `days_to_anc_engrafment`, `days_to_platelet_engrafment` (one 't'). Two patient recipients (QOHVF823, XI91FUC4) have event = "no" and NA days for both outcomes — confirmed clean by cross-tabulation.
- **Ingham — flag present, day absent**: Ingham's `Engraphment` column is a binary 0/1 flag (92 engrafted, 4 not, 1 NA across 97 samples). No day column exists, so `anc_engraftment_day_rel_transplant` stays NA (filled by `to_schema()`). Platelet engraftment columns also remain NA — no source data for them. Updated after initial implementation to reflect the flag rather than leaving `anc_engraftment` NA.
- **transmute() shadowing**: DAmico pre-computes `pmn_day_num` and `plt_day_num` (suffixed) to avoid the bare names `PMN_day` / `PLT_over_20000_day` resolving against the source data frame inside transmute(). Liu pre-computes `anc_eng_flag`, `plt_eng_flag`, `anc_eng_day`, `plt_eng_day` — none collide with source column names.

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`. All 69 tests passed (12 new tests added for engraftment).

Cross-check from `invalid_binary_values` QA: no non-0/1 values in `anc_engraftment` or `platelet_engraftment`. Cross-check from `unmasked_event_days` QA: no day present when event ≠ 1.

**Workbook edits still owed.**
- `Canonical_Schema`: add rows for `anc_engraftment`, `anc_engraftment_day_rel_transplant`, `platelet_engraftment`, `platelet_engraftment_day_rel_transplant`.
- `Value_Map`: DAmico — note the inferred-flag caveat for both engraftment events.
- `Coverage`: add rows for all four new columns showing per-study availability.
- `Harmonization_Summary`: note that Ingham has a binary engraftment flag but no day, and that DAmico's platelet event is inferred from day presence.

---

## 2026-08-18 — end_observation_day_rel_transplant and end_observation_reason

**Decision.** Two new columns added after `relapse_day_rel_transplant`:
- `end_observation_reason`: one of `EOS`, `administrative`, `death`, `last observation`, `lost to follow up`.
- `end_observation_day_rel_transplant`: day relative to transplant of the last day outcomes could be observed. Serves as the censoring time for subjects who do not experience a given event. Not masked by a binary event column (unlike the other day columns) because every followed subject has an end-observation time.

**Why.** A competing-risks or survival analysis requires a common censoring horizon. This column supplies it directly rather than requiring downstream code to reconstruct it from outcome columns.

### Per-study rules

| Study | end_observation_day_rel_transplant | end_observation_reason | Source columns |
|---|---|---|---|
| Artacho | NA | NA | Not recorded |
| DAmico | 100 (constant) | administrative | No per-patient follow-up; entire study censored at day +100 |
| Fujimoto | NA | NA | Not recorded |
| Ingham | `tte_death` if `death == 1`, else `censor` | `death` or `EOS` | `death`, `tte_death`, `censor` |
| Liu2017 | `time_to_death` if `deceased == 1` and non-NA, else `right_censor_time` | `death` or `EOS` | `deceased`, `time_to_death`, `right_censor_time` |
| Vallet | `min(lfu_day, eos_day, death_day)` computed from dates minus transplant date | `death`, `lost to follow up`, or `EOS` | `dat.lfu`, `dat.endstudy`, `dat.death`, `dat.hsct` |

### Decisions taken along the way

- **Ingham `censor`**: Values range 1561–2286 days (4–6 years post-transplant), confirming they are end-of-study administrative censoring dates, not death times. Six dead patients have `tte_death` values of 9–784 days with `censor` values all above 1500 days. One patient has both `death = NA` and `censor = NA`; both new columns are NA for that patient. Suffixed local `censor_day_num` to avoid transmute() shadowing the raw `censor` column.
- **Liu `right_censor_time` vs `time_to_death`**: For 16 of 18 deceased patients these are equal. Patient NYYC95BI has `time_to_death = 345` and `right_censor_time = 365` (diff = +20 days). A `right_censor_time` later than the death day is logically impossible for an end-of-observation column; used `time_to_death = 345` (confirmed by Sophie). Patient CCHWVERY has `deceased = 1` but `time_to_death = NA`; `right_censor_time = 100` used, reason = `death`.
- **Vallet `dat.endstudy`**: Not a single study-wide cutoff — 18 distinct patient-specific dates. 32/50 patients have NA `dat.endstudy`; all 32 are alive with `dat.lfu` present. Those patients get `dat.lfu` as end-observation day, reason = `EOS` (confirmed by Sophie). No patient has `dat.lfu < dat.endstudy`, so `lost to follow up` never fires in this cohort but the logic is preserved. One patient (002-2107-P-G) has `dat.endstudy = 2016-07-21 < dat.lfu = 2016-07-29`; end-observation = `eos_day = 723` (the minimum), reason = `EOS`.
- **Vallet death day**: Pre-computed `death_day_vallet` outside `transmute()` to feed `pmin()` for `end_obs_day_vallet`. This duplicates the formula already used for `death_day_rel_transplant` inside `transmute()`, but avoids transmute() shadowing.
- **`lost to follow up` never fires in Vallet data**: Confirmed by cross-tabulation (0 patients with `dat.lfu < dat.endstudy`). The vocabulary entry is retained in `end_obs_reason_levels` for correctness and for the QA validity check.

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`. All 46 tests passed.

End-observation coverage:
| Study | n_samples | n_day_present | n_day_missing | reasons |
|---|---|---|---|---|
| Artacho | 172 | 0 | 172 | — |
| DAmico | 104 | 104 | 0 | administrative |
| Fujimoto | 315 | 0 | 315 | — |
| Ingham | 97 | 96 | 1 | death, EOS |
| Liu2017 | 79 | 57 | 22 | death, EOS |
| Vallet | 118 | 118 | 0 | death, EOS |

Liu2017's 22 missing days are the donor rows (NA by design).
Ingham's 1 missing day is the patient with `death = NA` and `censor = NA`.

**Workbook edits still owed.**
- `Canonical_Schema`: add rows for `end_observation_reason` (type: categorical, vocabulary: EOS | administrative | death | last observation | lost to follow up) and `end_observation_day_rel_transplant` (type: numeric, units: days relative to transplant day 0).
- `Value_Map`: add mappings for `end_observation_reason` values per study.
- `Coverage`: add rows for `end_observation_day_rel_transplant` and `end_observation_reason` showing per-study availability.
- `Harmonization_Summary`: note that Artacho and Fujimoto do not record follow-up time; DAmico is administratively censored at day +100.

---

## 2026-08-18 — transplant_type

**Decision.** Categorical covariate recording the stem cell source used for transplant. Canonical vocabulary: `none` (donor-only rows in Liu), `bone marrow`, `umbilical cord blood`, `peripheral blood stem cells`, `bone marrow and umbilical cord blood`. Coded via `harmonize_transplant_type()`. Placed in `target_cols` after `nutrition`.

**Why.** Stem cell source is a core transplant characteristic and a known predictor of engraftment speed, GVHD risk profile, and immune reconstitution kinetics. Required for any model that conditions on transplant characteristics.

### Per-study rules

| Study | Rule | Source columns |
|---|---|---|
| Artacho2024 | Numeric code: 1 = bone marrow, 2 = umbilical cord blood, 3 = peripheral blood stem cells | `Transplant.source` |
| DAmico2019 | Free-text uppercased: BM = bone marrow, PBSC = peripheral blood stem cells | `Stem_cell_source` |
| Fujimoto2024 | Free-text uppercased: BM = bone marrow, PB = peripheral blood stem cells, CB = umbilical cord blood | `Graft_Type` |
| Ingham2019 | Free-text uppercased: BM = bone marrow, PBSC = peripheral blood stem cells, UC = umbilical cord blood, BM_UC = bone marrow and umbilical cord blood; local suffixed `tt_ingham` to avoid transmute() shadowing the raw `transplant_type` column | `transplant_type` |
| Liu2017 | Donor-only rows (where `donor == TRUE`) mapped to `none`; `pbsc` = peripheral blood stem cells, `marrow` = bone marrow, `cord+cord` = umbilical cord blood | `donor_source`, `donor` |
| Vallet2023 | Free-text lowercased: `pbc` = peripheral blood stem cells, `cord blood` = umbilical cord blood, `bone marrow` = bone marrow | `csh_type` |

### Decisions taken along the way

- **Ingham transmute() shadowing**: Ingham's source metadata has a column literally named `transplant_type`. The pre-computation local was suffixed to `tt_ingham` (for the uppercased/cleaned intermediate) and `transplant_type_ingham` (for the harmonized result) to avoid the raw source column silently shadowing the local inside `transmute()`.
- **Liu donor rows**: Liu includes 22 bone marrow donor samples alongside 57 recipient samples. Donor rows have no transplant of their own; mapped to `none` via the `donor` flag rather than leaving them NA, which would be ambiguous (NA means "not recorded" elsewhere). The `none` level exists solely for this case.
- **Vallet `csh_type` = "PBC"**: The abbreviation expands to peripheral blood cells (stem cells implied by context). Cross-tabulation shows all 118 Vallet patients have non-NA `csh_type`; no unrecognized values remain after mapping.
- **Source value cross-tabulation** (pre-implementation):
  - Artacho: codes 1/2/3 only, no NAs, 172 rows — clean.
  - DAmico: BM (n=61), PBSC (n=43) — clean.
  - Fujimoto: BM (n=106), PB (n=141), CB (n=68) — clean.
  - Ingham: BM (n=56), PBSC (n=28), UC (n=9), BM_UC (n=3), NA (n=1) — one genuinely missing row.
  - Liu: pbsc (n=38), marrow (n=14), cord+cord (n=3), plus 22 donor rows → `none`.
  - Vallet: PBC (n=115), cord blood (n=2), bone marrow (n=1) — clean.

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`. All 111 tests passed (25 new transplant_type checks added).

QA `noncanonical_transplant_type_values` is empty. All non-NA `transplant_type` values are members of `transplant_type_levels`.

**Workbook edits still owed.**
- `Canonical_Schema`: add row for `transplant_type` (type: categorical, vocabulary: none | bone marrow | umbilical cord blood | peripheral blood stem cells | bone marrow and umbilical cord blood).
- `Value_Map`: add per-study mappings for `transplant_type` (source column → canonical value).
- `Coverage`: add row for `transplant_type` showing per-study availability (Ingham has 1 NA; Liu donor rows have `none`).
- `Harmonization_Summary`: note that `none` is exclusive to Liu donor rows and should be excluded from any clinical modelling that restricts to recipients.

---

## Open questions

- Should `chpc/lib/extract_read_counts.py` emit the bare study surname instead
  of `StudyYYYY`, so the `study_key()` normalization in `Read_Attrition.qmd`
  becomes unnecessary? (Raised 2026-08-19 with the Liu label change.)
- Should `timepoint` be exported as an ordered factor in any downstream R
  object, or is the character column plus `timepoint_levels` enough?
- Liu donor rows currently get `pre-conditioning` like the recipients. If donor
  rows should be excluded from phase-based analyses, that is a filtering
  decision downstream rather than a change to the label.
- **`gvhd_stage_source` flag.** The `_stage` columns currently mix per-organ
  stages with overall composite grades (see `gvhd_stage_note`). A companion
  column recording which one a row holds would make this filterable instead of
  relying on the analyst remembering which studies are which. Worth adding
  before any modelling that uses stage as a covariate.
- **Severity when the outcome is 0 is inconsistent across studies.** Artacho,
  Ingham and Liu record an explicit grade 0 for aGVHD-negative patients;
  Fujimoto, DAmico and Vallet leave it NA. Nothing was manufactured — each study
  keeps what its source says. If a shared convention is wanted, the natural one
  is "outcome 0 implies grade 0", since Glucksberg grade 0 is by definition no
  aGVHD. Decide before computing any mean-severity summary, because the
  denominators differ today.
- DAmico has no overall aGVHD grade, so `agvhd_grade` is NA for the whole study
  even though 59 samples have `agvhd` = 1. Deriving it from the organ stages
  would require applying the Glucksberg composite table; not attempted.

---

## 2026-08-18 — gvhd_prophylaxis and gvhd_prophylaxis_cni

**Decision.** Two new categorical covariate columns placed immediately after `sample_day_rel_transplant` and before the agvhd block:

- `gvhd_prophylaxis`: partner-agent category. Vocabulary: `cni-mtx` | `cni-mmf` | `cni-steroid` | `cni-alone` | `other`.
- `gvhd_prophylaxis_cni`: calcineurin inhibitor backbone identity. Vocabulary: `cyclosporine` | `tacrolimus`. NA where the backbone is unspecified (Vallet "Other"; rows with no recorded prophylaxis).

**Why.** The prophylaxis regimen is a pre-transplant treatment variable with a direct biological rationale for gut microbiome effects: methotrexate causes mucositis and gut epithelial damage; mycophenolate is enterohepatically recycled. Separating partner agent (the primary microbiome axis) from backbone identity (a weaker direct effect) preserves both for modelling while keeping the variable compact.

### Per-study rules

| Study | Rule | Source columns |
|---|---|---|
| Artacho2024 | Not recorded (no prophylaxis column in source) → NA for both | — |
| DAmico2019 | Not recorded → NA for both. `Conditioning_regimen` (EDX/cyclophosphamide etc.) is the preparative regimen, not prophylaxis — not mapped | — |
| Fujimoto2024 | Not recorded → NA for both. `AGVHD_Treatment` (mPSL, ATG, MSC) is rescue therapy after aGVHD diagnosis, not prophylaxis — not mapped | — |
| Ingham2019 | `gvhd_prophylaxis` (3 levels): "Cyclosporine A + Methotrexate" → cni-mtx; "Cyclosporine + Corticosteroids" → cni-steroid; "Cyclosporine A" → cni-alone. CNI = cyclosporine for all three | `gvhd_prophylaxis` |
| Liu2017 | One-hot collapse of `cyclosporine`/`tacrolimus` → `gvhd_prophylaxis_cni`; `methotrexate`/`mmf` → `gvhd_prophylaxis` (sirolimus constant "no"). Donor rows → NA | `cyclosporine`, `tacrolimus`, `methotrexate`, `mmf`, `sirolimus` |
| Vallet2023 | `gvhd_proph_type`: "ciclosporin-MTX" → cni-mtx / cyclosporine; "cyclosporin-MMF" → cni-mmf / cyclosporine; "Other" → other / NA | `gvhd_proph_type` |

### Decisions taken along the way

- **Liu label swap (resolved — use patient-level data).** The data dictionary note on Liu's `cyclosporine` column cites Table 1 from the paper as tacrolimus/MTX N=21 and tacrolimus/MMF N=13. The one-hot columns give tacrolimus/MTX N=13 and tacrolimus/MMF N=21 — the same multiset {2, 21, 21, 13} but with the two tacrolimus sub-labels transposed. Patient-level encoded data takes precedence over a published summary table: the one-hot columns were derived from the source file and their totals (cyclosporine=23, tacrolimus=34) are internally consistent. The Table 1 counts appear to be a transposition error. Mapping used: tacrolimus/MTX=13, tacrolimus/MMF=21.

- **Ingham ATG — held back.** `X197ATGmm` (n=72 samples with ATG) is described in the data dictionary as "Anti-thymocyte globulin treatment as part of the conditioning (or not)." Including it in `gvhd_prophylaxis` would make the variable mean something different for Ingham than for the other two contributing studies (Liu and Vallet record only the calcineurin inhibitor + partner regimen). ATG belongs in a future conditioning variable alongside the other Ingham conditioning fields. `Was.graft.manipulated.for.GVHD.prophylaxis` is constant 0 and excluded on the same grounds.

- **Ingham "Cyclosporine A" alone → `cni-alone`.** The EBMT registry code 1 is a distinct category ("Cyclosporine A") that explicitly distinguishes monotherapy from combination. Coded as `cni-alone` on the basis that the registry does distinguish these by code, not because we can independently verify from the source that no partner was used. Eight samples (n≈4 patients). Documented here so the decision can be revisited.

- **Vallet ciclosporin/cyclosporin spelling.** The source uses "ciclosporin-MTX" in one value and "cyclosporin-MMF" in the other. Both are matched by exact lower-cased string comparison (no regex needed) and mapped to `cyclosporine` in `gvhd_prophylaxis_cni`.

- **Coverage: 3 of 6 studies, 271 of 885 samples.** Artacho, DAmico, and Fujimoto do not record GVHD prophylaxis. The NAs in those three studies are a logged decision, not an oversight.

- **DAmico: Conditioning_regimen explicitly excluded.** Values (EDX = cyclophosphamide, BU, TT, FLUDARA, L-PAM, TREO) are all preparative conditioning drugs — the cyclophosphamide is conditioning cyclophosphamide, not post-transplant cyclophosphamide prophylaxis.

- **Fujimoto: AGVHD_Treatment explicitly excluded.** Values (mPSL, ATG, MSC) are rescue therapy given after aGVHD was diagnosed, not prophylaxis started at transplant.

- **transmute() shadowing: Ingham.** Ingham's source metadata has a column literally named `gvhd_prophylaxis`. Pre-computed as `src_proph_ingham` (cleaned source) and `proph_val_ingham` / `proph_cni_val_ingham` (harmonized values) before the transmute call.

- **transmute() shadowing: Liu.** The five one-hot columns (`cyclosporine`, `tacrolimus`, `methotrexate`, `mmf`, `sirolimus`) all exist as source column names. All intermediate logicals (`cyc_yes`, `tac_yes`, `mtx_yes`, `mmf_yes`) and derived columns (`liu_prophylaxis`, `liu_prophylaxis_cni`) are computed before the transmute call with names that do not collide with any source column.

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`. All 105 tests passed (19 new tests added: 4 unit, 15 end-to-end).

Coverage:

| Study | n_samples | n_prophylaxis_present | n_prophylaxis_missing | n_cni_present | n_cni_missing |
|---|---|---|---|---|---|
| Artacho | 172 | 0 | 172 | 0 | 172 |
| DAmico | 104 | 0 | 104 | 0 | 104 |
| Fujimoto | 315 | 0 | 315 | 0 | 315 |
| Ingham | 97 | 96 | 1 | 96 | 1 |
| Liu2017 | 79 | 57 | 22 | 57 | 22 |
| Vallet | 118 | 118 | 0 | 112 | 6 |

Ingham's 1 NA row is the single sample with no clinical metadata. Liu's 22 NAs are the donor rows. Vallet's 6 NA CNI rows are the "Other" regimen patients (n=6 samples) where backbone identity is unspecified.

`noncanonical_gvhd_prophylaxis_values` and `noncanonical_gvhd_prophylaxis_cni_values` QA tables are both empty. `person_conflicts` QA table remains empty (prophylaxis is constant within person as expected).

**Workbook edits still owed.**
- `Canonical_Schema`: add rows for `gvhd_prophylaxis` (type: categorical, vocabulary: cni-mtx | cni-mmf | cni-steroid | cni-alone | other) and `gvhd_prophylaxis_cni` (type: categorical, vocabulary: cyclosporine | tacrolimus).
- `Value_Map`: add per-study mappings for both columns.
- `Coverage`: add rows for both columns showing per-study availability.
- `Harmonization_Summary`: note 3-of-6 coverage; note that Ingham's cni-alone is an EBMT registry code and that Liu's Table 1 counts differ from the patient-level data (Table 1 appears to have a transposition error for the tacrolimus sub-groups).
- Per-study sheets (`Ingham`, `Liu`, `Vallet`): update `harmonized_name` and `harmonized_values` for the relevant source columns.

---

## 2026-08-18 — Conditioning variables

**Decision.** Four new columns added, placed immediately after `sample_day_rel_transplant` and before the prophylaxis block:

- `conditioning_intensity` — categorical: `MAC` | `RIC` | `NMA`
- `conditioning_regimen` — canonical drug token string, alphabetically sorted and joined by `/`. Token vocabulary: `bu` (busulfan), `cy` (cyclophosphamide), `flu` (fludarabine), `mel` (melphalan), `thio` (thiotepa), `treo` (treosulfan), `vp16` (etoposide). TBI and serotherapy agents are not tokens — they are captured in the binary columns below.
- `conditioning_tbi` — binary `1`/`0`/`NA`, added to `binary_outcome_cols`
- `conditioning_serotherapy` — binary `1`/`0`/`NA` (ATG or anti-CD10 antibody), added to `binary_outcome_cols`

**Why.** Conditioning intensity is an established predictor of GVHD and engraftment and a required covariate in competing-risks analyses. TBI and serotherapy are independent predictors with separate biological mechanisms; separating them from the drug-token regimen string prevents confounding during modelling.

### Per-study rules

| Study | Rule | Source columns |
|---|---|---|
| Artacho2024 | All four conditioning columns NA — no conditioning data in source. `Myelosuppression` (0/98 samples, 1/74) is a toxicity outcome, not a description of the preparative regimen, and must not be mapped. | — |
| DAmico2019 | `conditioning_intensity` = MAC for all 104 samples (data dictionary labels `Conditioning_regimen` as myeloablative for all; confirmed by drug classes present). `conditioning_regimen` from free-text `Conditioning_regimen`: strip/tokenise 6 distinct values. TBI extracted to `conditioning_tbi`. `conditioning_serotherapy` NA — no ATG in source. | `Conditioning_regimen` |
| Fujimoto2024 | `conditioning_intensity` direct 3-level mapping from `Conditioning_Intensity` (MAC/RIC/NMA). `conditioning_tbi` from `Conditioning_TBI` (yes/no). `conditioning_regimen` and `conditioning_serotherapy` not recorded → NA. | `Conditioning_Intensity`, `Conditioning_TBI` |
| Ingham2019 | `conditioning_intensity` = MAC for all 96 documented patients (`Myeloabl` non-NA). `conditioning_regimen` assembled from drug-presence flags (binary or dose columns). `conditioning_tbi` from `TBI` column; 7 patients (28 samples) with TBI=NA but Irrad=0 recovered to TBI=0. `conditioning_serotherapy` from `X197ATGmm` (mouse ATG) or `X10Ab` (anti-CD10). The 1 metadata-less sample stays NA across all conditioning columns. | `Myeloabl`, `X233Bu`, `X270Cyclo`, `X284.2Fludarab`, `Total.dose.melphalan..mg.`, `Total.dose.VP16..mg.`, `Total.dose.thiotepa..mg.`, `TBI`, `Irrad`, `X197ATGmm`, `X10Ab` |
| Liu2017 | `conditioning_intensity`: High → MAC, Intermediate → RIC, Low → NMA. `conditioning_regimen` from `chemotherapy_regimen`: strip parenthetical dose annotations, split on `/`, remove TBI and ATG tokens, map to canonical names, sort. `conditioning_tbi` and `conditioning_serotherapy` extracted from the same parsed regimen string. Donors NA on all four columns. | `conditioning_intensity`, `chemotherapy_regimen` |
| Vallet2023 | `conditioning_intensity` from `conditioning` (myeloablative → MAC, non myeloablative → NMA; no RIC patients). `conditioning_regimen`, `conditioning_tbi`, `conditioning_serotherapy` all NA — not recorded in source. | `conditioning` |

### Decisions taken along the way

- **DAmico all MAC**: The data dictionary explicitly labels `Conditioning_regimen` as myeloablative for all 104 samples. Five samples have `EDX, FLUDARA, TBI`; Cy/Flu/TBI at ablative doses can be myeloablative but TBI dose is not in the source, so we accept the manuscript's label rather than inferring from the regimen. A QA table (`ingham_mac_tbi_dose_check`) was added to `build_qa()` to flag any Ingham MAC+TBI patients with sub-MAC TBI dose; 3 such rows exist (P23, P25, P27 with doses 400–450 cGy single-fraction) and are recorded here as an open question.
- **Liu Low → NMA**: The paper's Table 1 labels this group "RIC (low)" parenthetically, but the regimens (Flu/TBI and Cy/ATG) are physiologically non-myeloablative. We map Low → NMA, overriding the parenthetical label.
- **Liu donor rows**: donors are NA for all four conditioning columns because `conditioning_intensity`, `chemotherapy_regimen`, and all derived columns are patient-specific. `if_else(donor, NA, ...)` is used for TBI and serotherapy to avoid `!donor & str_detect(...)` returning `"0"` instead of NA for donor rows.
- **Artacho Myelosuppression**: `Myelosuppression` records a transplant-course toxicity (74 positive, 98 negative). This is not a description of the preparative regimen — it occurs after conditioning under MAC, RIC or NMA — and is explicitly excluded from all four conditioning columns with a code comment.
- **GOTCHA: transmute() shadowing in Liu and Vallet**: `conditioning_intensity` and `chemotherapy_regimen` are source column names in Liu; `conditioning` is a source column name in Vallet. Locals are suffixed (`intensity_liu`, `chem_raw_liu`, `src_cond_vallet`) to prevent silent shadowing.
- **Ingham TBI recovery**: 7 patients (28 samples) have `TBI` = NA but `Irrad` = 0. `Irrad` = 0 means no radiation of any kind was administered, so TBI must be 0. Recovered with `case_when(!is.na(irrad_ingham) & irrad_ingham == 0L ~ 0L)`. One metadata-less sample remains NA.
- **Ingham bu flag**: `X233Bu` = 1 or 2 (both indicate busulfan administration, 2 likely high-dose variant), so the flag is `df[["X233Bu"]] %in% c(1, 2)`.
- **build_qa() signature extension**: `build_qa` now accepts `raw = list()` to pass the Ingham source data frame for the dose cross-check. Called as `build_qa(metadata, raw = list(ingham = ingham_raw))` in `harmonize_all()`.

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`. All tests passed (0 failures). 56 new tests added: 5 unit, 51 end-to-end.

Coverage:

| Study | n_samples | n_intensity | n_regimen | n_tbi | n_serotherapy |
|---|---|---|---|---|---|
| Artacho | 172 | 0 | 0 | 0 | 0 |
| DAmico | 104 | 104 | 104 | 104 | 0 |
| Fujimoto | 315 | 315 | 0 | 315 | 0 |
| Ingham | 97 | 96 | 96 | 96 | 96 |
| Liu2017 | 79 | 57 | 57 | 57 | 57 |
| Vallet | 118 | 118 | 0 | 0 | 0 |

Notes: DAmico's serotherapy=0 reflects no ATG in source. Fujimoto has no regimen data but full TBI coverage. Liu's 22 NAs are donor rows. Vallet has only intensity from the `conditioning` column.

Distinct regimen strings confirmed clean (no `tbi` or `atg` tokens) via `conditioning_regimen_forbidden_tokens` QA table (empty).

**Workbook edits still owed.**
- `Canonical_Schema`: add rows for `conditioning_intensity` (type: categorical, vocabulary: MAC | RIC | NMA), `conditioning_regimen` (type: string, format: alphabetically sorted `/`-joined token string), `conditioning_tbi` (type: binary), `conditioning_serotherapy` (type: binary).
- `Value_Map`: add per-study mappings for `conditioning_intensity` (all 6 studies), `conditioning_regimen` (DAmico, Ingham, Liu), `conditioning_tbi` (DAmico, Fujimoto, Ingham, Liu), `conditioning_serotherapy` (Ingham, Liu).
- `Coverage`: add rows for all four new columns.
- `Harmonization_Summary`: note coverage pattern; note Artacho exclusion of Myelosuppression.
- Per-study sheets: update `harmonized_name` and `harmonized_values` for relevant source columns in DAmico, Fujimoto, Ingham, Liu, Vallet.

---

## 2026-08-18 — Secondary post-transplant outcomes

**Decision.** Four binary event flags added at the end of `target_cols`, after `end_observation_day_rel_transplant`, all added to `binary_outcome_cols`:

- `myelosuppression` — myelosuppression during the transplant course
- `mucositis` — mucositis (oral/GI) during the transplant course
- `bloodstream_infection` — documented bacteraemia or fungaemia post-transplant
- `bronchiolitis_obliterans` — bronchiolitis obliterans syndrome

No time-to-event columns and no severity columns for any of these. Where a source records a grade, it is collapsed to presence/absence.

**Why.** These are secondary clinical outcomes that supplement the primary GVHD, death and relapse endpoints. They appear at the end of the schema to reflect their secondary status and because coverage is mostly single-study.

### Per-study rules

| Study | Variable | Rule | Source columns |
|---|---|---|---|
| Artacho | myelosuppression | 0→0, 1→1, no NAs | `Myelosuppression` |
| Artacho | mucositis | Yes→1, No→0, no NAs | `Mucositis` |
| Artacho | bloodstream_infection, bronchiolitis_obliterans | NA | — |
| DAmico | mucositis | I/II/III→1; `/`→0; NA→0 (ungraded = mucositis-free per source) | `Mucositis_grade` |
| DAmico | bloodstream_infection | non-NA→1, NA→0 (NA confirmed = no BSI per manuscript) | `BSI` |
| DAmico | myelosuppression, bronchiolitis_obliterans | NA | — |
| Fujimoto | all four | NA | — |
| Ingham | all four | NA | — |
| Liu2017 | bloodstream_infection | literal crosswalk over two free-text columns (see below) | `infection_duringafter_transplant`, `infection_details` |
| Liu2017 | myelosuppression, mucositis, bronchiolitis_obliterans | NA | — |
| Vallet | bronchiolitis_obliterans | "yes"→1, NA→0 (dictionary explicit: missing = no BOS) | `bos` |
| Vallet | myelosuppression, mucositis, bloodstream_infection | NA | — |

### Decisions taken along the way

- **Artacho Myelosuppression correctly excluded from conditioning**: confirmed the conditioning_intensity block uses only the preparative regimen columns; `Myelosuppression` is a transplant-course toxicity and appears only in this secondary outcome column, not in `conditioning_intensity`.
- **DAmico mucositis "/" → 0**: the source uses "/" (5 patients) to indicate the patient was not graded rather than absent. Per spec, ungraded = mucositis-free in this source. NA (5 patients, separately) also → 0. Total 94 yes / 10 no.
- **DAmico BSI NA → 0**: the manuscript explicitly states all BSI events were in the PN group; the EN group had zero BSI. NA therefore genuinely means no event, not missing data. Total 39 yes / 65 no.
- **Vallet BOS NA → 0**: the data dictionary entry for `bos` states that missing means no BOS. Manuscript Table 1 confirms exactly 2 cases (both confirmed by the 2 "yes" values). Total 2 yes / 116 no.
- **Mucositis pooling caveat**: Artacho records a bare Yes/No with no stated threshold or grading system; DAmico uses an unnamed I/II/III scale. Both the timing window and the severity threshold are documented as UNCERTAIN in the data dictionary for both sources. Pooling the two columns for analysis compares two undefined thresholds. This caveat must be stated when mucositis is used as a pooled outcome.
- **Liu BSI**: two free-text infection columns (`infection_duringafter_transplant`, `infection_details`) were read in full. All 45 + 27 = 72 distinct non-NA strings were manually classified (plus NA → 0 for both columns). A recipient is BSI=1 if either column maps to 1 (OR logic). 14 of 57 recipients are classified as BSI=1. A strict regex on bacteremia|bacteraemia|fungemia|candidemia|septic shock|sepsis gives 13 of 57; the extra case is `hepatosplenic candidiasis` (classified 1 as disseminated candidemia equivalent; does not match the regex because the source string names a clinical syndrome rather than the bloodstream event that preceded it).
- **Liu 6 recipients with both fields empty**: classified BSI=0. "No documented infection" and "not assessed" are indistinguishable in this source.
- **Ingham tx_death not harmonized**: `tx_death` (treatment-related death) was deliberately not added as a `treatment_related_death` column per spec.

### Liu BSI classification (uncertain calls)

| String | Column | Call | Reasoning |
|---|---|---|---|
| `bipolaris mold, neutropenic fever` | col1 | 0 | Mold without bloodstream context |
| `C difficile, sepsis, Strep pneumonia, VRE UTI` | col1 | **1** | "sepsis" in HCT implies bacteremia; matches sanity-check regex |
| `CMV viremia, peritonitis, septic shock` | col1 | **1** | "septic shock"; matches sanity-check regex |
| `CMV viremia, rhinovirus, influenza, candida glabrata` | col1 | 0 | Candida species without bloodstream site |
| `CMV, CNS, rhinovirus` | col1 | 0 | CNS = central nervous system in context of other viruses, not CoNS bacteremia |
| `knee 9/2013` | col1 | 0 | Septic joint implied; no bacteremia named |
| `oral candida, VRE` | col1 | 0 | VRE without bloodstream site |
| `pneumonia, oral candida, CNS, rhinovirus` | col1 | 0 | Same CNS ambiguity |
| `VRE, C difficile, CMV viremia, BK virus, adenovirus` | col1 | 0 | VRE without bloodstream site |
| `hepatosplenic candidiasis` | col2 | **1** | Disseminated Candida; invasive fungal equivalent to candidemia in HCT context |
| `neutropenic fever, Abiotopia/strep viridans` | col2 | 0 | Named organisms but no explicit bloodstream site |
| `port infection` | col2 | 0 | CLABSI vs local port-site ambiguous; classified non-BSI |
| `propionibacterium acnes` | col2 | 0 | Organism without bloodstream context |

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R`. All tests passed (0 failures). 34 new tests added: 2 unit, 32 end-to-end.

Coverage:

| Study | n_samples | n_myelosuppression | n_mucositis | n_bloodstream_infection | n_bronchiolitis_obliterans |
|---|---|---|---|---|---|
| Artacho | 172 | 172 | 172 | 0 | 0 |
| DAmico | 104 | 0 | 104 | 104 | 0 |
| Fujimoto | 315 | 0 | 0 | 0 | 0 |
| Ingham | 97 | 0 | 0 | 0 | 0 |
| Liu2017 | 79 | 0 | 0 | 57 | 0 |
| Vallet | 118 | 0 | 0 | 0 | 118 |

Event counts: Artacho myelosuppression 74/172; Artacho mucositis 15/172; DAmico mucositis 94/104; DAmico BSI 39/104; Liu BSI 14/57; Vallet BOS 2/118.

`liu_bsi_unrecognized` QA table is empty (all 72 distinct source strings present in lookup). `invalid_binary_values` QA table remains empty.

**Workbook edits still owed.**
- `Canonical_Schema`: add rows for `myelosuppression`, `mucositis`, `bloodstream_infection`, `bronchiolitis_obliterans` (all type: binary).
- `Value_Map`: add per-study mappings for each column.
- `Coverage`: add rows for all four columns.
- `Harmonization_Summary`: note coverage pattern; note mucositis pooling caveat; note Liu BSI derivation method and uncertain calls.
- Per-study sheets (`Artacho`, `DAmico`, `Liu`, `Vallet`): update `harmonized_name` and `harmonized_values` for the relevant source columns.

---

## 2026-08-19 — Study label for Liu drops the year suffix

**Decision.** `study_labels[["liu"]]` changes from `"Liu2017"` to `"Liu"`. Every
cohort now labels as the capitalized author surname with no year: Artacho,
DAmico, Fujimoto, Ingham, Liu, Vallet (plus Jarosch, added in
`Merging_Metadata.qmd`, which was already bare).

**Why.** Liu was the only cohort carrying a publication-year suffix, so the
`study` column was internally inconsistent and every plot that keyed a palette
on it needed a fuzzy prefix match to avoid dropping Liu to NA. With the label
regularized, `Functions/study_colors.R` is a plain named lookup.

### Per-study rules

| Study | Rule | Source columns |
|---|---|---|
| Liu | `study_labels[["liu"]]` = `"Liu"` (was `"Liu2017"`) | n/a — constant, not derived from source |
| all others | unchanged | n/a |

### Decisions taken along the way

- `person_prefixes[["liu"]]` was already `"Liu"` and is **not** changed, so
  person IDs stay `Liu_01`, `Liu_02`, … Nothing about person identity moves.
- Every reference in the harmonizer and the test file goes through
  `study_labels[["liu"]]` symbolically — `grep '"Liu2017"'` found exactly one
  literal occurrence in the whole harmonization folder (the constant itself) and
  zero in the tests. So the change is confined to one line.
- `Merging/ReadCounts/*_read_counts.tsv` (written on CHPC by
  `chpc/lib/extract_read_counts.py`) still uses the full `StudyYYYY` form for
  every cohort. Rather than touch the CHPC extractor, `Functions/study_colors.R`
  exposes `study_key()`, which strips a trailing 4-digit year and errors on an
  unknown cohort; `Merging/Read_Attrition.qmd` normalizes with it at read time.
- Consequence: `Merging/merged_metadata.tsv` still contains 79 rows of
  `Liu2017` until `Merging/Merging_Metadata.qmd` is re-run. Plotting code
  tolerates both forms in the meantime, so this is not urgent, but the file is
  stale with respect to the harmonizer until then.

### Verification

Ran `Rscript Merging/Harmonization/test_harmonize_gvhd_metadata.R` against the
six real `*_meta_qiime.tsv` files. **ALL TESTS PASSED (0 failures).** Per-study
sample counts unchanged: Artacho 172, DAmico 104, Fujimoto 315, Ingham 97,
Liu 79, Vallet 118. QA tables all report under the `Liu` label.

Separately confirmed the palette is hue-for-hue identical to the old
`Shared_aesthetics/Study_colors.R` assignment for all seven cohorts.

**Workbook edits still owed.**
- Per-study sheet `Liu`: any cell recording the emitted `study` value should read
  `Liu` rather than `Liu2017`.
- `Canonical_Schema`: the `study` row's documented value set drops `Liu2017` and
  gains `Liu`.
- `Value_Map`: same substitution wherever `Liu2017` appears as a harmonized value.
