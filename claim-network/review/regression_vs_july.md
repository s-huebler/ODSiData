# Claims Synthesis Regression Report
**Claims_Synthesis3.xlsx vs Claims_Synthesis2.xlsx**  
Run date: 2026-10-07  
Pipeline: `claim-network/scripts/synthesis/run_synthesis.py`  
Input: `claim-network/data/Claims_Master_reflinked.xlsx` (222 source rows)

---

## Summary

| Check | July (Synthesis2) | Mine (Synthesis3) | Status |
|---|---|---|---|
| Atomic claims | 330 | 328 | 2 missing — expected (see §1) |
| Canonical claims | 109 | 107 | 2 missing — expected (see §1) |
| Edges rows | 330 | 328 | 2 missing — expected (see §1) |
| Graph nodes | 237 | 235 | 2 fewer claim nodes — expected |
| Graph SUPPORTS edges | 290 | 288 | 2 fewer — expected |
| Graph CITES edges | 153 | 153 | ✓ exact match |
| Claim labels (graph) | — | — | ✓ all 107 shared claims match exactly |
| n_atomic_claims per claim | — | — | ✓ all 107 match |
| n_primary_refs per claim | — | — | ✓ all 107 match |
| n_reviews per claim | — | — | ✓ all 107 match |
| reviews per claim | — | — | ✓ all 107 match |
| Valence (per src_row) | — | — | ✓ 222/222 match |
| Mechanism primary | — | — | ✓ 222/222 match |
| ref_label | Chatila_2018 | Telesford_2015 | expected (see §2) |
| mechanism_categories | — | — | 2 known diffs (see §3) |
| GTDB lineage cols | n/a | added | 03_taxonomy adds domain→species + gtdb_reclassified (see §5) |

---

## §1 — Two missing atomic rows (src_row 32, Paredes_2026)

**What:** The July synthesis produced 3 atomic tokens from the taxa cell
`"Clostridium cluster XIVa (for example, Clostridium leptum, Clostridium coccoides)"`:

| July token | Subject | Canonical claim ID |
|---|---|---|
| `Clostridium Clostridia` | Clostridia | 15 |
| `Clostridium leptum` | Clostridium leptum | **33** |
| `Clostridium coccoides)` | Clostridium coccoides) | **34** |

The pipeline strips parenthetical qualifiers before splitting, producing one token
`"Clostridium cluster XIVa"` → subject Clostridia → claim 15.  Claim 33 and 34
are absent from the Synthesis3 output.

**Why the difference:** The July synthesis inconsistently handled commas inside
parentheses: for src_row 32 it extracted parenthetical examples as additional taxa
(Clostridium leptum and Clostridium coccoides), but for src_rows 189–190 it
treated the parenthetical as illustrative and collapsed to the parent group
(`Clostridiales order`).  A consistent algorithm cannot reproduce both behaviors.
Uniform parenthetical stripping (the current rule) matches the more common pattern
(src_rows 189–190 and ~15 others with `(qualifier)` cells).

**Impact:** Claims 33 and 34 remain in `canonical_claims.csv` with their July IDs
and will be re-connected to atomic rows if/when source data is corrected or a manual
override added to `subject_lookup.csv`.

---

## §2 — ref_label Chatila_2018 → Telesford_2015 (ref_id 03b8633c)

**What:** One ref_label differs between the workbooks:

| ref_id | July label | Mine label |
|---|---|---|
| 03b8633c | Chatila_2018 | Telesford_2015 |

**Why:** The October 2026 citation-network dictionary QA corrected the BIBTEXKEY for
this paper (Telesford et al. 2015, DOI 10.1080/19490976.2015.1056973).  The July
synthesis used the old label from the pre-correction dictionary.  The pipeline reads
ref_label from the current `Claims_Master_reflinked.xlsx`, which reflects the
corrected dictionary.

**Impact:** No structural change — same ref_id, same canonical claims; only the
human-readable label is updated.

---

## §3 — Two mechanism_categories ordering/content differences

**What:** Two canonical claims differ in `mechanism_categories`:

| claim_id | Subject | July | Mine |
|---|---|---|---|
| 62 | Enterobacter (genus) | `Biomarker / indicator (1)` | `Biomarker / indicator (1); Diversity / commensal depletion (1); Lactate metabolite (1)` |
| 63 | Lactate/lactase-producing bacteria | `Biomarker / indicator (1); Lactate metabolite (1); Diversity / commensal depletion (1)` | `Biomarker / indicator (1); Diversity / commensal depletion (1); Lactate metabolite (1)` |

**Why:** Both arise from the `Biomarker (ratio)` mechanism verbatim, which the July
synthesis assigned context-dependent categories:
- src_row 72 (Enterobacter): July assigned only `"Biomarker / indicator"` (single)
- src_row 73 (Lactate/lactase ratio): July assigned the full triple in a different order

The mechanism_lookup stores one canonical mapping per verbatim string; it uses the
merged union of both July assignments ordered as `Biomarker / indicator; Diversity /
commensal depletion; Lactate metabolite`.  This conflict is recorded in
`review/seed_conflicts.csv`.

**Impact:** Cosmetic for claim 63 (order differs, same categories). For claim 62
(Enterobacter), mine adds two extra categories.  The `mechanism_primary` matches in
both cases (`Biomarker / indicator`).  To resolve: add a row to mechanism_lookup with
a more specific verbatim key for the Enterobacter context, or accept the fuller
categorisation as the correct one.

---

## §4 — Graph JSON comparison

```
                         July      Mine
Nodes total               237       235
  claim nodes             109       107
  review nodes             10        10
  primary nodes           118       118
Edges total               443       441
  SUPPORTS                290       288
  CITES                   153       153
```

All claim labels for the 107 shared claims match exactly.  The 2 missing nodes are
`CLAIM_33` and `CLAIM_34` (see §1).  The 2 missing SUPPORTS edges connect primary
`a57ed71f` to those claims.

---

## §5 — GTDB r232 taxonomy lineage (new columns in Synthesis3)

**What:** `03_taxonomy.py` now joins GTDB r232 lineage columns onto every atomic row:
`gtdb_name`, `domain`, `phylum`, `class`, `order`, `family`, `genus`, `species`,
`gtdb_reclassified`.  `Canonical_Claims` gains `gtdb_phylum`.

**Coverage:** 86 subjects in rank_lookup.csv:
- 54 exact GTDB match (name unchanged)
- 15 NCBI→GTDB reclassifications (`gtdb_reclassified = yes`):
  phylum renames (Firmicutes→Bacillota, Bacteroidetes→Bacteroidota,
  Proteobacteria→Pseudomonadota, Cyanobacteria→Cyanobacteriota),
  family rename (Odoribacteraceae→Marinifilaceae),
  10 species/genus reclassifications (see `review/gtdb_reclassifications.csv`)
- 7 manual (non-GTDB taxa: Candida, Trichoderma, Picobirnavirus, B. mimicus,
  C. perfringens, Streptococci, Clostridium coccoides) artifact)
- 10 not applicable (functional groups, molecular pattern)

**Build:** Regenerate `lookups/taxonomy_lookup.csv` with
`python claim-network/scripts/synthesis/build_taxonomy_lookup.py`
(requires `lookups/gtdb_cache/bac120_taxonomy.tsv.gz` and `ar53_taxonomy.tsv.gz`).

**Sharpea note:** GTDB r232 places Sharpea in phylum Bacillota_I (distinct from
Bacillota); the July subject_group "Firmicutes (Bacillota)" is preserved as-is.

---

## Open items

1. **Claims 33, 34** — Consider whether to add manual overrides in `subject_lookup.csv`
   for `Clostridium leptum` and `Clostridium coccoides` extracted from the src_row 32
   parenthetical, or to accept the current single-token behavior.
2. **Biomarker (ratio) context split** — `mechanism_lookup.csv` may need a finer-grained
   entry for the Enterobacter-specific usage (see §3).
