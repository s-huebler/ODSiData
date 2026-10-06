# PDF table and reference-list extraction tests (June – July 2026)

**When:** Jun 24 – Jul 9 2026.

**What was being attempted:** Two mechanical problems needed solving before claims could be
linked to primary papers:

1. **Getting review-paper tables into Excel.** In `Chatgpt_Thoughts/`, ChatGPT and Claude were
   compared at transcribing tables from four review PDFs (Hsu, Paredes, Samarkhazan, Weber). It holds
   the PDFs, the chat transcripts (`*_chatgpt_tables.rtfd`), the resulting `*_tables.xlsx`, and
   `PDF_to_Excel_PROMPT.md`, a reusable prompt that reads tables visually from rendered pages because
   automated detectors (Camelot, Tabula, GROBID) mangled them.
2. **Parsing each review's numbered reference list** into full citation, `Author_Year`
   abbreviation and DOI so numeric in-text citations could be resolved:
   - `Samarkhazan2025_refs.xlsx`, `PinzonLeal2025_refs.xlsx`, `PinzonLeal_2025_tables_refs.xlsx`,
     with their PDFs and chat transcripts (`*_chatgpt.rtf*`, `chat_refs.rtf`)
   - `Testing_excel_refs1/2.xlsx` and `Book11.xlsx`: scratch tests of splitting and abbreviating citations
   - `doi_lookup_log.txt`: log of a Crossref DOI-fill run over ~1,000 references
   - `batch2a_abbreviations.xlsx`: parsed reference lists (3,504 rows, all citing papers) with
     full and abbreviated citations

**Outcome / superseded by:** Reference parsing grew into the separate `citation-network/` pipeline
(`citation-network/Full_Network/citing_dictionary.csv`), which `scripts/reflink_claims.py` now uses
to link claims to primary papers. Table transcription was replaced by quoting the review text directly.
