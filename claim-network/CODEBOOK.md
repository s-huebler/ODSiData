# Claims network codebook

**Version 1.4 (2026-11-12).** Every `proposals.json` records the codebook version it was drafted
under. Change a rule here before the next review, add a changelog line, and never change it
silently. A new rule applies to reviews drafted after it; earlier reviews it would have changed
are listed in the changelog so they can be revisited.

## 1. What a claim is

A claim is a statement **made by a review** that links a **microbial target** to a **GVHD
outcome**, with the review's citation(s) for it. We record what the review says, not what the
cited paper found. Each claim becomes one proposed row; after approval it is exploded to one row
per cited reference.

### 1.1 Microbial target (required)

- **Taxon** at any rank (strain or species up to phylum), named as the review names it.
- **Functional group** only when its members share a biological function: butyrate or SCFA
  producers, secondary bile acid producers, obligate anaerobes, segmented filamentous bacteria, pathobionts. Not groups defined
  by an engineering or generic label ("genetically engineered bacteria", "intestinal
  microorganisms", "commensals" used loosely, "the gut microbiota"). *(GUO_032)*
- Whole-community statements (diversity, dysbiosis, germ-free, "the microbiota") are **not**
  targets. Diversity is not a row.

### 1.2 GVHD outcome (required)

Counts: acute or chronic GVHD incidence (any organ, including GI), grade or severity, steroid or
treatment response, GVHD-related mortality, and composition differences between GVHD and
non-GVHD patients.

Does not count on its own: infection or bacteremia, relapse, immune reconstitution, engraftment,
overall survival, non-relapse or treatment-related mortality. Include these only when the review
ties them to GVHD in the same statement. A statement with both a GVHD and a non-GVHD outcome is
included and the short claim names the GVHD part. *(GUO_033 to 035, GUO_039)*

### 1.3 Context

Allogeneic HSCT recipients or transplant models. FMT or probiotic uses in other diseases are out.

## 2. Splitting statements into claims

- One proposal per **target × mechanism** within a quote. Four taxa in one sentence give four
  proposals sharing the quote.
- Taxa named as examples ("e.g.", "such as") get their own proposals. *(GUO_024, 025, 027)*
- A sentence naming two mechanisms for one taxon gives two proposals, one per mechanism.
  *(GUO_013, 014)*
- Tables, including supplementary tables: one quote per relevant cell sentence; location gives
  the table row. A cell that repeats a claim already taken from the text is skipped. A cell that
  adds a new claim, or conflicts with the text, gets its own proposal (note the conflict).
- Figures: only when the figure carries a claim with a citation that the text does not.
  Figures that repeat the text are skipped.
- A single statement that reports more than one evidence type (for example a murine model and a human correlation) is split into one proposal per evidence type. *(MOS_011, MOS_027.)*

## 3. Fields

| Field | Values / rule |
|---|---|
| `taxon_as_cited` | Name as printed. Expand abbreviations to the full name ("E.limosum" → *Eubacterium limosum*). Fix nothing else; GTDB harmonization comes later. |
| `taxon_rank_as_cited` | `species`, `genus`, `family`, `order`, `class`, `phylum`, `functional group`. The rank the review used, even if the name is now classified differently. |
| `direction` | See 3.1. |
| `evidence_as_stated` | The study type in the review's words, or `unspecified`. |
| `evidence` | `human observational`, `human interventional`, `murine`, `unspecified`. See 3.2. |
| `mechanism_specific` | See section 4. `mechanism_broad` is derived from it. |
| `target_type` | `taxon`, or `mechanism` for a functional group (functional groups point to the mechanism, not a taxon node). |
| `intervention` | blank, `diet`, `antibiotic`, `probiotic / LBP`, `FMT`, `defined consortium`, `other`. The therapy in the statement, if any. `other` is for an experimental or non-standard manipulation that fits no named category (e.g. single-species reintroduction, a therapeutic replenishing suggestion). |
| `mechanism_as_named` | Short claim in plain words, under about 12 words. |
| `ref_string` | Citation as printed: `[30]`, `[32,33]`, `[60-63]`, or `Taur 2014; Jenq 2012`. Blank if uncited. |
| `mechanism_assignment` | Audit trail of how the mechanism was set (see 4.3). |
| `location` | `body: <section heading>`, `table N, row R ([refs])`, `supplementary table SN, row R ([refs])`, `figure N`, `box N`. |
| `quote` | Verbatim from the paper text in the paper skill, as it renders (no markdown, citation superscripts dropped). Shortest span that carries the claim. |

### 3.1 Direction (describes the target, never the intervention)

| Value | Use when |
|---|---|
| `protective` | Higher abundance or presence goes with better GVHD outcomes; depleted in GVHD; enriched in non-GVHD patients; rises after a successful therapy. |
| `exacerbating` | The reverse: expanded in GVHD, worsens severity or mortality, removed or reduced by a successful therapy. |
| `context-dependent` | The review reports conflicting or conditional effects ("controversial", "depends on"). |
| `unspecified` | The review says the target matters for GVHD but gives no direction (e.g. a biomarker). *(GUO_029, 030)* |
| `no effect` | The review reports no association or no effect. |

Taxa that rise after a successful FMT are `protective` even if they are often considered harmful
elsewhere; the row records the review's framing. *(GUO_038, Desulfovibrionaceae)*

A conflicting finding reported elsewhere in the review, including one that is itself skipped (for example a metabolite-level result with no taxon), may set a claim's direction to `context-dependent`. This is a reviewer judgment call, is likely to apply only when the two statements sit in close proximity, and must be recorded in the row note. *(MOS_009 with MOS_S09.)*

### 3.2 Evidence

Taken from the review's own words in the statement or its immediate context (same or preceding
sentence). Never from outside knowledge of the cited paper. *(GUO_012: Sofi 2021 is murine but the
review does not say so, so `unspecified`.)*

| Value | Covers |
|---|---|
| `human observational` | Patient cohorts, case-control, biomarker studies, meta-analyses of these. A patient cohort implied by context counts. *(GUO_007)* |
| `human interventional` | Any study that gave patients an intervention: randomized trials, single-arm or pilot studies, treated case series and case reports. *(GUO_036 to 039)* |
| `murine` | Mouse and other animal models. |
| `unspecified` | The review does not say. |

## 4. Mechanisms (scheme 3C, revised)

| Broad class | Specific | Use for |
|---|---|---|
| Class 0: Unattributed | 0. Unattributed | Association with no mechanism stated |
| Class 1: Metabolite-mediated | 1a. SCFA / butyrate signaling | SCFAs, and the case where SCFA/metabolite signaling is itself the operative GvHD mechanism; also a taxon called an SCFA, butyrate or propionate producer when the review gives only an association or outcome with no distinct downstream mechanism *(GUO_015)*. When the review attributes the effect to a distinct mechanism (barrier, Treg/T-cell), classify there even if the taxon is also a producer *(MOS_005, MOS_007, MOS_008)* |
| | 1b. Bile acid signaling | Secondary bile acids, FXR/TGR5 |
| | 1c. Tryptophan / indole signaling | Indoles, indoxyl sulfate, AhR, IL-22 via AhR *(GUO_031)* |
| | 1d. Other metabolites | Other named metabolites |
| Class 2: Immune cell targeting | 2a. Innate immune | Macrophages, DCs, NK, innate sensing |
| | 2b. T-cell adaptive | Treg/Th17 balance, T-cell differentiation, and antigen presentation to T cells including epithelial MHC class II induction or suppression *(MOS_013, MOS_014)* |
| | 2c. Other immune | B cells, MAIT, γδ T cells, ILC3 |
| Class 3: Barrier and structural | 3a. Epithelial barrier | Tight junctions, mucus, epithelial survival |
| Class 4: Pathobiont expansion | 4a. Colonization resistance / competitive exclusion | Niche competition that keeps pathobionts out |
| | 4b. Pathobiont expansion / mono-dominance | Expansion of the listed pathobionts |

### 4.1 Pathobiont list (4b without a stated mechanism)

Enterococcus (any species), Enterobacterales / Enterobacteriaceae and member genera (Klebsiella,
Escherichia, Enterobacter), Gammaproteobacteria, Streptococcus. The families of listed genera
count as pathobionts too (Enterococcaceae, Streptococcaceae); orders that also hold
non-pathobiont genera (Lactobacillales) do not. Expansion of these in GVHD goes to 4b even when
the review states association only. Anything else with association only goes to 0.
Extend the list only by a codebook change. *(Staphylococcaceae in GUO_002 is not on the list.)*

### 4.2 Interventions

Therapy claims are assigned to the mechanism the therapy acts on, with the therapy in
`intervention`. If no mechanism is stated, use 0 (or 4b for a listed pathobiont).

### 4.3 `mechanism_assignment` values

`scheme C` (mechanism stated or listed pathobiont); `scheme C; diversity/dysbiosis ->
unattributed` (association only); `class 5 reassigned: mechanism stated`; `class 5 reassigned: no
mechanism stated`; `class 5 reassigned: from outcome described`.

## 5. Skipped passages

Passages that look like claims but fail a rule are logged as `skipped` items with the reason, so
the reviewer can confirm or promote them. Log the notable ones (a taxon named near GVHD, an FMT
or antibiotic result, a diversity finding), not every sentence. Common reasons: diversity only;
no microbial target; generic or engineered group; non-GVHD outcome; non-transplant context;
composition described with no direction and no GVHD link; figure repeats the text.

## 6. Reviews and identifiers

| Paper key | Skill | `citing_bibtex` (dictionary) | ID prefix |
|---|---|---|---|
| godefroy2025 | godefroy2025-paper | Godefroy_2025 | GOD |
| guo2024 | guo2024-paper | Guo_2024 | GUO |
| ji2024 | ji2024-paper | Ji_2024 | JI |
| junior2025 | junior2025-paper | SoaresFerreiraJunior_2025 | JUN |
| khuat2021 | khuat2021-paper | Khuat_2021 | KHU |
| moses2026 | moses2026-paper | Moses_2026 | MOS |
| paredes2026 | paredes2026-paper | Paredes_2026 | PAR |
| pinzonleal2025 | pinzonleal2025-paper | Pinzon-Leal_2025 | PIN |
| samarkhazan2025 | samarkhazan2025-paper | SoleimaniSamarkhazan_2025 | SAM |
| sohouli2025 | sohouli2025-paper | Sohouli_2025 | SOH |
| weber2026 | weber2026-paper | Weber_2026 | WEB |
| yue2024 | yue2024-paper | Yue_2024 | YUE |

Proposal IDs: `<PREFIX>_001`, `_002`, ... in reading order; skipped items `<PREFIX>_S01`, ...

## 7. Decisions

`approve`, `reject`, `discuss` (rows); `skip_ok`, `discuss` (skipped items). Every `discuss` is
resolved at the end-of-paper discussion into `approve` (with any field changes) or `reject`, and
the resolution is written to `decisions.json` under `discussion`. Only approved rows reach
`claims.csv`.

## Changelog

- **1.4 (2026-11-12).** (a) Families of listed pathobiont genera (Enterococcaceae,
  Streptococcaceae) count as pathobionts, so expansion goes to 4b. Applied directly to the three
  approved rows coded 0 under 1.3: JI_001 and KHU_001 (Enterococcaceae), JI_003
  (Streptococcaceae); PAR_018 and YUE_088 were already 4b. (b) Supplementary tables are in scope
  and follow the table rules; reviews with supplementary tables: junior2025 (Supplementary Table
  S2, about 10 taxon-aGvHD rows; see JUN_S18) and moses2026 (Supplementary Table 1, intervention
  studies). Not retro-applied. `validate_proposals.py` checks quotes against paper.md only, so it
  needs to read the supplementary table CSVs before supplementary rows can validate. (c) Table
  cells follow the figure rule: skip a cell that repeats the text, propose a cell that is new or
  conflicts. Not retro-applied; drafts that took one row per cell sentence even where the body
  already carried the claim (e.g. junior2025 Table 3, Jenq 2015 [28]) can be revisited.
- **1.3 (2026-11-06).** Added `other` to the `intervention` controlled vocabulary for experimental or non-standard manipulations that fit no named category. Applied while reviewing Paredes 2026 (PAR_025 B. ovatus reintroduction; PAR_032, PAR_033 bile-acid-strain replenishing). No existing rows invalidated; other reviews not retro-edited.
- **1.2 (2026-11-05).** Renamed the direction value `null` to `no effect`. The string `null` was being coerced to a missing value by pandas in the ring builder and drew a blank edge. Applied to all existing rows.
- **1.1 (2026-11-05).** Broadened 2b to include antigen presentation and epithelial MHC class II induction/suppression. Reworded the 1a rule so a stated downstream mechanism (barrier, Treg/T-cell) outranks an SCFA/producer descriptor; a producer label still maps to 1a when only an association is given. Added `secondary bile acid producers` as a functional group. Renumbered 3b to 4a (colonization resistance / competitive exclusion sits under Class 4 alongside 4b). Added that a conflicting finding elsewhere in the review, even a skipped one, may set direction to context-dependent as a noted reviewer judgment call. Added a split-by-evidence rule. Applied while reviewing Moses 2026. Guo recheck: GUO_013 and GUO_015 unchanged under the reworded 1a rule; GUO_032 mechanism relabeled 3b to 4a (mechanical, same meaning).
- **1.0 (2026-11-05).** First version, written after the Guo 2024 review. New relative to the
  anchor-review framework: GVHD outcomes only; `null` direction separated from `unspecified`;
  `clinical trial` renamed `human interventional` and widened to any treated patients;
  functional groups must have a biological definition; 3b moved under Class 4; examples get
  their own rows; diversity-only statements are skipped. Guo 2024 was drafted before this
  version and resolved to it at its discussion.
