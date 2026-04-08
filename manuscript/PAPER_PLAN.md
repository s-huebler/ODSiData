# Paper Plan: Scoping Review of Gut Microbiome in Adult Allo-SCT

## Working Title

"Gut Microbiome and Time-to-GVHD in Adult Allogeneic Stem Cell Transplant Recipients: A Scoping Review and Description of an Analytic Cohort"

## Paper Goals

This paper serves as the bedrock of a biostatistics dissertation investigating microbial features that affect time to GVHD. It has three interlocking objectives:

1. **Establish clinical relevance of microbial targets.** Targeted therapeutic options already exist (designer microbiomes, phage-derived enzymes like Fujimoto et al. 2024's anti-*Enterococcus faecalis* enzyme). This means that identifying specific microbial targets has direct downstream clinical utility — it is not just an academic exercise.

2. **Map what is currently known about specific microbial features.** Some taxa are widely understood to be influential (e.g., *Blautia*, *Enterococcus*, *Lachnospiraceae*), and reduced alpha diversity is broadly associated with worse outcomes. However, the apparent breadth of support for these findings is inflated by citation amplification: a single primary study may be cited by many narrative reviews, which then cite each other, creating an echo chamber effect. The citation network analysis in this paper will quantify how many *independent cohorts* actually support each commonly-cited claim.

3. **Identify gaps that motivate further research.** Time-to-GVHD (as opposed to occurrence alone) is understudied. Baseline definitions vary across studies. Methodological heterogeneity (16S region, bioinformatic pipeline, sample timing) complicates cross-study comparison. The analytic sub-cohort described in this paper provides a harmonized resource for addressing these gaps in Project 3 (application of bhCRR).


## Methodology Decisions

### Scoping Review Framework
- Follow **PRISMA-ScR** guidelines (Preferred Reporting Items for Systematic Reviews and Meta-Analyses extension for Scoping Reviews)
- **Not** formally registered as a protocol — this is a scoping review, not a systematic review
- The PRISMA-ScR structure provides methodological credibility and distinguishes this from the 20+ existing narrative reviews
- Key components: documented search strategy, explicit eligibility criteria, PRISMA flow diagram, structured data extraction

### Target Venue (tentative)
- Primary targets: *Transplantation and Cellular Therapy* or *Blood Advances*
- Both have the right clinical audience, expect quantitative rigor, and have published microbiome-GVHD work
- The citation network analysis would be a novel contribution at these venues
- If the methodology is particularly strong: *Microbiome* or *ISME J* are stretch targets

### Baseline Definition
- **Framing decision:** Present baseline heterogeneity as a *finding* of the scoping review, not just an internal methods choice
- For the analytic sub-cohort: use closest sample to day 0 of transplant (the most common reference point in the literature)
- Document deviations explicitly (e.g., Allozithro samples during pre-conditioning)
- This turns a limitation into a motivated design choice grounded in the evidence synthesis

### AI-Assisted Review Methodology
This review will use AI (Claude) as a methodological tool at multiple stages. All AI use will be reported following the **PRISMA-trAIce** framework (JMIR AI, 2025) — the current standard for transparent reporting of AI in systematic literature reviews. Note: this is distinct from **PRISMA-AI** (Nature Medicine, 2023), which covers systematic reviews *of* AI interventions and is not relevant here.

**Key PRISMA-trAIce requirements:**
- Name AI tool(s), version, and provider used at each stage
- Document exact prompts verbatim (reproducibility requirement)
- Describe the human–AI interaction model at each stage
- Report AI performance metrics (sensitivity, specificity, Cohen's kappa) validated against a human gold standard (~10% sample)
- Use the trAIce-modified PRISMA flow diagram, which tracks AI exclusions and human exclusions separately
- Discuss AI-related limitations explicitly in the Discussion

**Stage-by-stage AI use plan and permitted scope:**

| Stage | AI Role | Human Role | Risk Level |
|-------|---------|-----------|------------|
| Search string refinement | AI assists with term generation and testing | Human defines and approves final string | Low |
| Title/abstract screening | AI first-pass; validated on 10% gold standard | Human reviews all AI "include" + uncertain decisions | Medium — validated in literature |
| Full-text screening | AI flags likely exclusions with reasons | Human makes all final include/exclude decisions | Medium-high |
| Data extraction | AI generates structured first-pass draft | Human verifies every field | High — error rates 31%+ in literature |
| Citation network construction | Computational (code, not LLM inference) | Human reviews network logic and outputs | Low — this is a methods/code task |
| Synthesis and writing | AI assists drafting | Human leads, verifies all claims against sources | High — hallucination risk |

**All AI decisions, prompts, and validation records are logged in `AI_assisted_litreview/`** (see that directory's CLAUDE.md for logging rules and the session log template).


## Paper Structure

### Abstract
Structured format: Background / Objectives / Eligibility Criteria / Sources and Methods / Results / Conclusions

### 1. Introduction
- Open with the therapeutic pipeline: designer microbiomes and phage-derived enzymes show that once a microbial target is identified, intervention is possible (cite Fujimoto2024 prominently)
- Therefore, identifying which microbial features affect GVHD risk and timing has direct clinical implications
- The problem: dozens of studies exist but results appear inconsistent, and it's unclear whether inconsistency reflects biology or methodology
- Existing reviews are narrative and don't quantify the evidence base systematically
- State the three objectives

### 2. Methods

#### 2.1 Protocol and Registration
- State adherence to PRISMA-ScR; note that protocol was not pre-registered

#### 2.2 Eligibility Criteria
- **Population:** Adult (>=18) allogeneic HSCT recipients
- **Concept:** Gut microbiome composition (16S rRNA or shotgun metagenomics)
- **Context:** GVHD as an outcome (any type: acute, chronic, occurrence, timing, severity)
- **Study types:** Original research (exclude narrative reviews, editorials, case reports with n<5, animal-only studies)
- Decision: include pediatric-only studies in the broader scoping review (flagged), exclude from analytic sub-cohort
- Decision: include studies without publicly available data in the scoping review (Tier 3), but only studies with public 16S data + GVHD timing in the analytic sub-cohort

#### 2.3 Search Strategy
- Databases: PubMed, Embase, Web of Science
- Date range: inception through [search date]
- Documented search string (MeSH terms + free text)
- Supplementary hand-searching of reference lists from included reviews

#### 2.4 Data Extraction
- Structured extraction form capturing:
  - Study design, sample size, geographic region
  - Microbiome platform (16S region, sequencing technology, bioinformatic pipeline)
  - Baseline/sample timing definition
  - GVHD outcome type (acute/chronic, occurrence/timing/severity)
  - Key microbial findings (taxa, diversity metrics, metabolites)
  - Data availability (public repository, accession number)

#### 2.5 Citation Network Analysis
- Novel methodological contribution
- Extract reference lists from all included narrative/clinical reviews (Tier 4 papers)
- For each commonly-cited claim (e.g., "Blautia associated with reduced GVHD"), trace through the citation chain to identify the original empirical source(s)
- Build a bipartite network: reviews --> primary studies
- Quantify independent replication count for each major claim
- Tool: R (igraph) or Python (networkx)

#### 2.6 Analytic Sub-Cohort Selection
- Additional inclusion criteria beyond the scoping review:
  - Time-to-GVHD outcome available (not just occurrence)
  - Publicly available 16S rRNA sequencing data (with accession number)
  - Individual-level clinical metadata accessible
- Baseline definition: closest available sample to day 0 of transplant
- Harmonization approach: QIIME2 pipeline (cite ODSiData), batch correction (ComBat-seq)

### 3. Results

#### 3.1 Search Results and Study Selection
- PRISMA flow diagram (Figure 1)
- Total records identified, deduplicated, screened, included
- Breakdown by tier (Tier 1-4)

#### 3.2 Characteristics of Included Studies
- Descriptive table (Table 1): study design, N, platform, GVHD outcome type, baseline definition, data availability
- Summary statistics: geographic distribution, year range, sample sizes

#### 3.3 Citation Network and Evidence Mapping
- **Figure 2: Citation network** showing which primary papers are "load-bearing" across the review literature
- **Table 2: Evidence table** mapping specific claims to independent empirical sources
  - Columns: Claim | Primary sources (independent cohorts) | Reviews citing these sources | Independent replication count
  - Example rows:
    - "Reduced alpha diversity associated with aGVHD" | Taur2014, Jenq2015, Peled2020 | cited in 15/20 reviews | 3 independent cohorts
    - "*Blautia* associated with reduced GVHD mortality" | Jenq2015 | cited in 12/20 reviews | 1 independent cohort
- This is the core novel contribution: making visible the gap between citation frequency and independent replication

#### 3.4 Synthesis of Findings by Theme
Organized by the major claims in the literature:
- Alpha diversity and GVHD risk
- Specific taxa associated with GVHD outcomes (*Blautia*, *Enterococcus*, *Lachnospiraceae*, *Ruminococcaceae*)
- Metabolite pathways (SCFAs, butyrate, bile acids)
- Antibiotic exposure and dysbiosis
- Methodological factors (baseline timing, sequencing platform, bioinformatic pipeline)

#### 3.5 Analytic Sub-Cohort Description
- **Table 3:** Studies meeting analytic sub-cohort criteria (currently: Allozithro/Bergeron2017, Liu2017, Fujimoto2024)
  - Columns: Study, Year, N patients, Study design, GVHD outcomes available, Baseline definition, BioProject accession
- **Figure 3:** Sample inclusion/exclusion flow for the analytic cohort
- **Figure 4:** Cohort composition (sample counts by study, timepoint, outcome)
- Harmonization status: pipeline description, batch correction approach
- **Figure 5:** Beta diversity (PCoA) showing batch effects before/after correction
- Open methodological questions flagged for Project 3

### 4. Discussion
Three-part argument:
1. The therapeutic pipeline is real and growing — identifying microbial targets matters
2. Evidence for specific targets is thinner than citation frequency suggests; the citation network reveals that many "well-established" findings rest on 1-3 independent cohorts
3. Time-to-GVHD specifically is understudied; the analytic sub-cohort provides a resource for addressing this with appropriate statistical methods (motivate Project 3)

Additional discussion points:
- Baseline heterogeneity as a key methodological challenge
- Limitations of 16S vs. shotgun metagenomics for taxa-level claims
- Implications for future study design (standardized baselines, data sharing)

### 5. Conclusion
- Brief summary of scoping review findings
- The analytic sub-cohort as a resource
- Explicit connection to the thesis: this paper motivates and provides the data for a Bayesian hierarchical competing risks analysis of microbial features affecting time to GVHD


## Figures Plan

| Figure | Type | Content | Status |
|--------|------|---------|--------|
| Fig 1 | PRISMA flow diagram | Search/screening/inclusion numbers | Needs search completion |
| Fig 2 | Citation network (igraph/networkx) | Bipartite graph: reviews --> primary studies, node size = citation count | Needs reference extraction |
| Fig 3 | Flowchart | Sample inclusion/exclusion for analytic sub-cohort | Exists (Sample_IncExc.png) |
| Fig 4 | Stacked bar or alluvial | Cohort composition by study x timepoint x outcome | Needs creation |
| Fig 5 | PCoA panels | Beta diversity before/after batch correction | Exists (Uncorrected/CombatSeq PNGs) |

## Tables Plan

| Table | Content | Status |
|-------|---------|--------|
| Table 1 | Characteristics of all included primary studies | Needs data extraction |
| Table 2 | Evidence map: claims x independent sources x review citation count | Needs citation network |
| Table 3 | Analytic sub-cohort studies with detailed metadata | Partially exists (AnalysisSubCohort.tex) |


## Action Items

### Phase 1: Scoping Review Infrastructure (Priority)
- [ ] Write formal eligibility criteria (PCC framework: Population, Concept, Context)
- [ ] Develop and document the database search string (PubMed, Embase, Web of Science); document any AI assistance in refinement
- [ ] Run the search and deduplicate results
- [ ] **Build human gold standard:** manually screen ~10% random sample for AI performance validation
- [ ] Screen titles/abstracts (AI-first, human review of includes/uncertain); compute sensitivity/specificity vs. gold standard
- [ ] Full-text review (human primary, AI assist for flagging); log all AI prompts and decisions
- [ ] Design the structured data extraction form
- [ ] Extract data (AI first-pass, human verification field-by-field); log discrepancies
- [ ] Complete PRISMA-trAIce checklist for Methods/supplement

### Phase 2: Citation Network (High Priority — this is the differentiator)
- [ ] Compile complete reference lists from all Tier 4 narrative reviews
- [ ] Parse references to identify primary empirical studies vs. reviews
- [ ] For each major claim, trace the citation chain back to original sources
- [ ] Build bipartite citation network (R igraph or Python networkx)
- [ ] Calculate independent replication counts for key claims
- [ ] Generate citation network figure (Figure 2)

### Phase 3: Analytic Sub-Cohort
- [ ] Finalize inclusion criteria for the sub-cohort
- [ ] Document baseline definition and deviations by study
- [ ] Complete batch correction comparison (ComBat-seq vs. uncorrected)
- [ ] Generate cohort composition figure (Figure 4)
- [ ] Write sub-cohort description for the paper

### Phase 4: Writing
- [ ] Draft Introduction (therapeutic motivation + gap statement)
- [ ] Draft Methods (PRISMA-ScR structure)
- [ ] Draft Results sections 3.1-3.5
- [ ] Draft Discussion (three-part argument)
- [ ] Generate PRISMA flow diagram (Figure 1)
- [ ] Compile all tables and figures
- [ ] Write Abstract and Conclusion

### Phase 5: Finalization
- [ ] Internal review with advisor
- [ ] Verify all citation network claims against sources
- [ ] Check PRISMA-ScR checklist compliance
- [ ] Check PRISMA-trAIce checklist compliance; complete all 14 items
- [ ] Select target journal and format accordingly
- [ ] Prepare supplementary materials:
  - Full evidence table
  - Full search strategy with database-specific strings
  - PRISMA-trAIce checklist (Table S2)
  - AI prompt documentation (synthesized from `AI_assisted_litreview/prompts/`)
  - AI performance validation results (from `AI_assisted_litreview/validation/`)

### Key References for AI Methodology
- PRISMA-trAIce: https://ai.jmir.org/2025/1/e80247 (and GitHub: https://github.com/cqh4046/PRISMA-trAIce)
- PRISMA-AI (for AI-as-subject reviews, not directly applicable): https://pubmed.ncbi.nlm.nih.gov/36646804/
- LLM screening validation: https://www.cambridge.org/core/journals/research-synthesis-methods/article/validation-of-large-language-models-llama-3-and-chatgpt4o-mini-for-title-and-abstract-screening-in-biomedical-systematic-reviews/EDE7C95374C7FF6200B7280D5742D906
- LLM effectiveness in abstract screening: https://link.springer.com/article/10.1186/s13643-024-02609-x


## Key Strategic Notes

1. **The citation network is the differentiator.** Every journal has seen multiple GVHD microbiome review submissions. A paper that quantitatively shows how many independent studies support each consensus claim is genuinely novel.

2. **Frame the analytic sub-cohort as a resource, not a completed analysis.** The paper's job is to describe it and motivate why it exists — the analysis happens in Project 3 with bhCRR.

3. **The baseline question is a feature, not a bug.** Documenting that studies use heterogeneous baseline definitions is itself a finding that supports the claim that more methodological work is needed.

4. **Don't try to be a meta-analysis.** Scoping reviews map the evidence landscape; they don't synthesize effect sizes. This is appropriate given the methodological heterogeneity.
