# Prompt: classify-ta v1
# Created: 2026-06-11
# PRISMA-trAIce item: methods-tools

---

You are classifying papers for the ODSiData GVHD microbiome meta-analysis.

Read the spreadsheet at `Classify/Included.xlsx` (columns: `Title`, `Abstract`) row by row. For each row, parse the Title and Abstract to classify the study type of the paper. Create separate output csvs for all the different study types and save results to `Classify/NAMEOFSTUDYTYPE_classified.csv`. The entire row from the input csv should be copied over to the output csv of the classified studytype. Use python with openpyxl.


Use the text in the title to classify studies into CaseStudy, RCT, CaseControl, MetaAnalysis, RCT, Cohort, Review, Multiple, Other.

If an abstract is missing then classify the paper into Other. If it doesn't fit any other category classify the paper into Other.
If the title and abstract indicate multiple study types classify the paper into Multiple.

CaseStudy should be case studies or case series. 
RCT should be randomized controlled trials.
CaseControl should be case-control studies.
MetaAnalysis should include data synthesis rather than just narrative synthesis.
Cohort includes prospective, retrospective, and cross-sectional cohorts. 
Reviews can be narrative or scoping literature reviews. 



