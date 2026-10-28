# Prompt template — adding a variable to the harmonized metadata

Paste one of these into Claude Code running from the repository root
(`~/Documents/ODSi/ODSiData`).

The standing conventions live in the **"Harmonization Variable Additions"**
section of `CLAUDE.md` — coding contract, the `transmute()` shadowing gotcha,
QA requirements, the test command, the decision-log entry shape, and the list of
things that should trigger a stop-and-ask. Claude Code reads that automatically,
so the prompt below only needs to carry the spec and the per-study construction.

Fill in the bracketed fields. Delete rows for studies where the variable is not
available — but say so explicitly rather than omitting them silently, so the
"not recorded → NA" decision is deliberate and gets logged.

---

## Template

```
Add [VARIABLE NAME(S)] to the harmonized GVHD metadata.

Follow the "Harmonization Variable Additions" section of CLAUDE.md for all
standing conventions.

SHAPE: [time-to-event triple | binary | categorical covariate | numeric covariate]

DEFINITION: [one or two sentences — what this variable means clinically, and
what a reader should be able to conclude from it]

[For a time-to-event variable, name all three columns:
   <name>                        1/0 event
   <name>_day_rel_transplant     day relative to transplant
   <name>_stage or _grade        severity, or "none — source has no severity"]

[For a categorical variable, give the canonical vocabulary you want:
   e.g. myeloablative | reduced-intensity | non-myeloablative]

PLACEMENT: [where in target_cols, e.g. "immediately after the cgvhd block"]

PER-STUDY CONSTRUCTION:
- Artacho:  [source columns and rule, or "not recorded -> NA"]
- DAmico:   [...]
- Fujimoto: [...]
- Ingham:   [...]
- Liu2017:  [...]
- Vallet:   [...]

[Optional] NOTES: [anything you already know is odd, or a convention you want
followed that differs from the standing rules]

Before editing anything, read the relevant study sheets in
data_dictionaries_harmonized.xlsx and cross-tabulate the real source columns in
the *_meta_qiime.tsv files. If the data contradicts the spec above, or you hit
any of the stop-and-ask triggers in CLAUDE.md, stop and ask me before writing
code — report the counts that make it matter and propose a default. Otherwise
proceed: edit harmonize_gvhd_metadata.R, extend build_qa(), add unit and
end-to-end tests, run the test suite, and append an entry to
to_log/harmonization_decisions.md. Do not touch the xlsx.
```

---

## Worked example 1 — time-to-event (engraftment)

Coverage is thin: only DAmico and Liu record engraftment. That is worth stating
explicitly so the four NA studies are a logged decision rather than an oversight.

```
Add neutrophil and platelet engraftment to the harmonized GVHD metadata.

Follow the "Harmonization Variable Additions" section of CLAUDE.md for all
standing conventions.

SHAPE: two time-to-event triples

DEFINITION: Engraftment is recovery of donor-derived haematopoiesis after
transplant. Neutrophil engraftment is conventionally ANC >= 500/uL sustained,
platelet engraftment is platelets >= 20,000/uL untransfused. These are the
recovery landmarks the pre-engraftment and engraftment timepoint bins are named
for, so having them as explicit outcomes lets me check the timepoint bins
against observed recovery rather than assuming the nominal day windows.

COLUMNS:
  anc_engraftment                        1/0
  anc_engraftment_day_rel_transplant     day
  platelet_engraftment                       1/0
  platelet_engraftment_day_rel_transplant    day
  (no severity column for either)

PLACEMENT: immediately after the cgvhd block, before death.

PER-STUDY CONSTRUCTION:
- Artacho:  not recorded -> NA
- DAmico:   PMN_day is the neutrophil engraftment day and PLT_over_20000_day the
            platelet engraftment day. There is no separate event flag, so treat a
            recorded day as the event: day present -> 1, day absent -> 0 with a
            NA day. Flag in the log that a missing day here cannot be
            distinguished from a patient who never engrafted.
- Fujimoto: not recorded -> NA
- Ingham:   not recorded -> NA
- Liu2017:  anc_engrafment / platelet_engrafment (note the source spelling) are
            yes/no event flags; days_to_anc_engrafment and
            days_to_platelet_engrafment are the days. Donor rows -> NA
            throughout, as with every other Liu clinical outcome.
- Vallet:   not recorded -> NA

Before editing anything, read the DAmico and Liu sheets in
data_dictionaries_harmonized.xlsx and cross-tabulate the real source columns. In
particular check whether Liu's two "no" engraftment patients have a day recorded,
and whether any DAmico patient is missing PMN_day. If the data contradicts the
spec above, or you hit any of the stop-and-ask triggers in CLAUDE.md, stop and
ask me before writing code. Otherwise proceed: edit harmonize_gvhd_metadata.R,
extend build_qa(), add unit and end-to-end tests, run the test suite, and append
an entry to to_log/harmonization_decisions.md. Do not touch the xlsx.
```

---

## Worked example 2 — categorical covariate (conditioning intensity)

This one has a real vocabulary conflict baked in — three studies use three
different scales that only look alignable — so it is a good illustration of
letting the stop-and-ask do its job rather than pre-deciding.

```
Add conditioning intensity to the harmonized GVHD metadata.

Follow the "Harmonization Variable Additions" section of CLAUDE.md for all
standing conventions.

SHAPE: categorical covariate

DEFINITION: Intensity of the preparative regimen given before transplant. This
is a major confounder for early post-transplant microbiome disruption, so I want
it available as a study-level adjustment variable.

CANONICAL VOCABULARY (proposed, push back if the sources do not support it):
  myeloablative | reduced-intensity | non-myeloablative

COLUMNS:
  conditioning_intensity     categorical
  conditioning_tbi           1/0, whether total body irradiation was included

PLACEMENT: in the patient-characteristics block, immediately after disease.

PER-STUDY CONSTRUCTION:
- Artacho:  intensity not recorded -> NA. No TBI column either -> NA.
- DAmico:   Conditioning_regimen is a free-text drug list with no intensity
            label. Leave conditioning_intensity NA rather than inferring
            intensity from the drug combination. Set conditioning_tbi from
            whether the regimen string names TBI.
- Fujimoto: Conditioning_Intensity is MAC / RIC / NMA -> map directly.
            Conditioning_TBI is Yes/No -> conditioning_tbi.
- Ingham:   Myeloabl is constant 1 in this cohort -> myeloablative for all.
            TBI column -> conditioning_tbi; note Irrad is broader than TBI, so
            use TBI and not Irrad.
- Liu2017:  conditioning_intensity is Low / Intermediate / High intensity. This
            is NOT the same instrument as MAC/RIC/NMA — tell me what you think
            the defensible mapping is before applying one.
- Vallet:   conditioning is myeloablative / non myeloablative, two levels only,
            with no reduced-intensity category. Map directly and note that
            Vallet cannot distinguish RIC from NMA.

Before editing anything, read all six study sheets in
data_dictionaries_harmonized.xlsx and tabulate the real values of each source
column. I expect the vocabularies not to align cleanly across Fujimoto, Liu and
Vallet — report what you find, say whether a single canonical vocabulary is
defensible or whether this needs a coarser two-level split, and propose a
default before writing code. Otherwise proceed: edit harmonize_gvhd_metadata.R,
extend build_qa() with a non-canonical value table for the new vocabulary, add
unit and end-to-end tests, run the test suite, and append an entry to
to_log/harmonization_decisions.md. Do not touch the xlsx.
```

---

## When to use a second prompt instead

Keep one prompt per variable (or per tightly-related group, like the two
engraftment triples above). Split into a separate prompt when:

- The variable needs a source file that is not one of the six `*_meta_qiime.tsv`
  files — make locating and validating that file its own step.
- You are folding the accrued "workbook edits still owed" into
  `data_dictionaries_harmonized.xlsx`. That is always its own prompt, run at the
  end of a round, and it should start by checking for the Excel lock file.
- The answer to a stop-and-ask changes the spec substantially. Re-issue a fresh
  filled-in template rather than continuing a long thread, so the final prompt
  matches what actually got built.
