-- Citation-network SQLite schema.
-- Each citing paper has its own local reference list (refs). A claim is
-- one sentence (or short span) inside a citing paper that anchors one or
-- more citations. citations is a long-format edge list claim -> ref.
-- concepts + claim_concepts are filled in later, after clustering review.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS papers (
  paper_id      TEXT PRIMARY KEY,   -- short key, e.g. "Liu2017"; default = pdf stem
  title         TEXT,
  authors       TEXT,
  year          INTEGER,
  doi           TEXT,
  pdf_path      TEXT,
  tei_path      TEXT,
  processed_at  TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS refs (
  ref_id             INTEGER PRIMARY KEY AUTOINCREMENT,
  citing_paper_id    TEXT NOT NULL,
  local_number       INTEGER,        -- N in [N] within the citing paper
  tei_xml_id         TEXT,           -- GROBID xml:id, e.g. "b4"
  title              TEXT,
  authors            TEXT,
  year               INTEGER,
  doi                TEXT,
  resolved_paper_id  TEXT,           -- canonical key once matched to a paper
  FOREIGN KEY (citing_paper_id) REFERENCES papers(paper_id)
);
CREATE INDEX IF NOT EXISTS idx_refs_citing ON refs(citing_paper_id);
CREATE INDEX IF NOT EXISTS idx_refs_resolved ON refs(resolved_paper_id);

CREATE TABLE IF NOT EXISTS claims (
  claim_id           INTEGER PRIMARY KEY AUTOINCREMENT,
  citing_paper_id    TEXT NOT NULL,
  verbatim_sentence  TEXT,           -- exact text from the PDF
  paraphrased_claim  TEXT,           -- human-written short version
  section            TEXT,           -- intro | methods | results | discussion | conclusion | other
  citation_role      TEXT,           -- background | supports | contrast | method | data
  page               INTEGER,
  needs_review       INTEGER DEFAULT 0,
  review_reason      TEXT,
  FOREIGN KEY (citing_paper_id) REFERENCES papers(paper_id)
);
CREATE INDEX IF NOT EXISTS idx_claims_paper ON claims(citing_paper_id);

CREATE TABLE IF NOT EXISTS citations (
  citation_id  INTEGER PRIMARY KEY AUTOINCREMENT,
  claim_id     INTEGER NOT NULL,
  ref_id       INTEGER NOT NULL,
  FOREIGN KEY (claim_id) REFERENCES claims(claim_id),
  FOREIGN KEY (ref_id)   REFERENCES refs(ref_id)
);
CREATE INDEX IF NOT EXISTS idx_citations_claim ON citations(claim_id);
CREATE INDEX IF NOT EXISTS idx_citations_ref ON citations(ref_id);

CREATE TABLE IF NOT EXISTS concepts (
  concept_id  INTEGER PRIMARY KEY AUTOINCREMENT,
  label       TEXT,
  definition  TEXT
);

CREATE TABLE IF NOT EXISTS claim_concepts (
  claim_id    INTEGER NOT NULL,
  concept_id  INTEGER NOT NULL,
  PRIMARY KEY (claim_id, concept_id),
  FOREIGN KEY (claim_id)   REFERENCES claims(claim_id),
  FOREIGN KEY (concept_id) REFERENCES concepts(concept_id)
);
