# Claims network lab talk, running flow

Audience: microbiology lab update. Target 50-60 min at roughly 1.5-2 min per slide.
Status column: PLACEHOLDER = exists in Claims_Network_November2026.pptx, NEW = to build,
KEEP = existing slide carried over largely intact.

Standing rules for every slide
- Huntsman template, title top left, footer band preserved
- Bullet fragments, not sentences
- Figures legible from the back of the room; redraw rather than shrink
- Full citation, small white text, bottom left
- Talking points in the notes field, register matched to old slide 4 (narrative sentences,
  parenthetical source so a fact can be traced under questioning)

## Section 1. Open

| # | Slide | Status |
|---|---|---|
| 1 | Title | KEEP (old 1) |
| 2 | Agenda | KEEP (old 2), retitle section 3 to match new flow |

## Section 2. Background, the clinical problem

| # | Slide | Status |
|---|---|---|
| 3 | Divider, Background | KEEP (old 3) |
| 4 | What GVHD is | KEEP (old 4) |
| 5 | Microbiome acts in all three phases | BUILT, Moses Fig 1 edited, innate vs adaptive framing from Samarkhazan Table 2 |

## Section 3. Antigen presentation, Moses Figure 2

| # | Slide | Status |
|---|---|---|
| 6 | The donor graft arrives programmed | BUILT, panels A and B |
| 7 | Naive T cells meet host peptides | BUILT, panels C and D |
| 8 | Memory T cells need MHC II | BUILT, panel E |

## Section 4. Metabolites, Paredes Figure 3

| # | Slide | Status |
|---|---|---|
| 9 | Fibre and short-chain fatty acids | BUILT, left column |
| 10 | Fat and bile acid signalling | BUILT, second column |
| 11 | Tryptophan, indoles and ILC3 | BUILT, third column |

Built slides live in Background_Section_Nov2026.pptx, seven slides on the Content with
Caption layout from slideMaster2. Old slides 5, 6, 7, 8, 9, 10 are superseded by these.
Old slides 11, 12, 13, the therapeutic examples, move to the therapeutics section, next.

## Section 5. Therapeutics, to be built

| # | Slide | Status |
|---|---|---|
| 12 | Metabolites and dysbiosis | KEEP (old 8) |
| 13 | Oxygen, iron and the self-reinforcing loop | KEEP (old 12), chelation |
| 14 | Therapeutic closer, feeding the metabolite axis | NEW, prebiotics and postbiotics |

## Section 6. Phase 3, barrier failure and pathobionts

| # | Slide | Status |
|---|---|---|
| 15 | Phase 3 | REBUILD (old 10), crop to the phase 3 sector |
| 16 | Barrier-directed example, xylose | KEEP (old 11) |
| 17 | Therapeutic closer, ecosystem restoration | NEW, FMT, SER-155, MaaT013 |

## Section 7. Bridge

| # | Slide | Status |
|---|---|---|
| 18 | The intervention landscape mapped onto mechanism | NEW, the pivot slide, see mapping below |
| 19 | Why a claims network | NEW, the question slide 18 raises and cannot answer |

## Section 8. Literature review

| # | Slide | Status |
|---|---|---|
| 20 | Divider, Literature review | KEEP (old 14) |
| 21 | Search strategy | REBUILD (old 16), simplified PRISMA, counts only |
| 22 | What the corpus looks like, concept blocks | REBUILD (old 15) |

## Section 9. Claims network construction

| # | Slide | Status |
|---|---|---|
| 23 | Divider, Claims network | KEEP (old 17) |
| 24 | Goal | KEEP (old 18) |
| 25 | Worked example, one quote to one edge | NEW, replaces the two text slides as the teaching slide |
| 26 | Extraction rules and what was excluded | REBUILD (old 19) |
| 27 | Harmonization, GTDB, valence, evidence, mechanism | REBUILD (old 20) |
| 28 | The schema at a glance | NEW, the five mechanism classes with claim counts |

## Section 10. Results, the four views

| # | Slide | Status |
|---|---|---|
| 29 | Evidence weight, Clostridia | REBUILD (old 21A, 23) |
| 30 | Conflicting claims, Lactobacillus | REBUILD (old 21B, 24) |
| 31 | Translational gaps, clinical trial filter | REBUILD (old 21C, 25) |
| 32 | Source tracing, Enterococcus to Peled 2020 | REBUILD (old 21D, 26) |

## Section 11. Close

| # | Slide | Status |
|---|---|---|
| 33 | What this cannot tell us | NEW, unattributed share, FMT and consortia without composition |
| 34 | Future work | NEW |
| 35 | Interactive demo, link | KEEP (old 22), move to the end as the live close |

---

## Mapping used on slide 18

Claim counts from claim-network/framework/claims_synthesis_framework.csv, n=329.
The interventions come from the four anchor reviews. The mapping of intervention to
mechanism class is our inference and is not stated by any of the reviews.

| Mechanism class | Claims | Interventions acting there |
|---|---|---|
| 1a SCFA and butyrate signalling | 85 | RPS, Amylofiber SH with GFO, FOS, GOS, sodium butyrate, SCFA-directed strain selection |
| 1b Bile acid signalling | 25 | Secondary bile acids, preclinical only |
| 1c Tryptophan and indole signalling | 21 | Rifaximin, FMT response correlates with tryptophan metabolites |
| 1d Other metabolites | 7 | none identified |
| 2a Innate immune | 9 | historical only, LPS-resistant grafts |
| 2b T cell adaptive | 44 | synbiotic Treg induction only, no taxon-specific agent |
| 2c Other immune | 1 | none identified |
| 3a Epithelial barrier | 13 | xylose, B. fragilis, both murine |
| 3b Colonization resistance | 8 | FMT, SER-155, MaaT013 |
| 4b Pathobiont expansion | 32 | antibiotic stewardship, selective antibiotics, antibiotic-neutralizing agents |
| 0 Unattributed | 84 | not targetable, no mechanism stated |

The asymmetry is the argument for the talk. The two largest mechanism classes are SCFA
signalling at 85 claims and adaptive T cell responses at 44, but only the first has a
dense intervention pipeline. A further 84 claims, 26 percent of the dataset, sit in a
class that no intervention can target because the citing review stated no mechanism.
