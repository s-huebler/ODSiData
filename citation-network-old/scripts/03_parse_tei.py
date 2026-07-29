"""Parse GROBID TEI XML into the SQLite database.

For each TEI file:
  1. Upsert the citing paper into `papers`.
  2. Insert that paper's reference list into `refs` (keyed by GROBID xml:id).
  3. Walk every <s> in <body>; if it contains one or more <ref type="bibr">,
     write a row to `claims` and one row per cited ref to `citations`.
  4. Flag the claim for human review when the citation sits mid-sentence
     (i.e. there is meaningful text after the last citation marker), since
     in those cases the citation usually applies to a clause rather than
     the whole sentence.

Usage (from citation-network/):
    python scripts/03_parse_tei.py
    python scripts/03_parse_tei.py --tei-dir grobid_out --db db/citations.sqlite

Re-running a paper deletes that paper's existing claims/refs/citations first,
so edits to TEI files re-import cleanly.
"""

import argparse
import re
import sqlite3
from pathlib import Path
from typing import Dict, Optional

from lxml import etree

TEI_NS = "http://www.tei-c.org/ns/1.0"
XML_NS = "http://www.w3.org/XML/1998/namespace"
NS = {"t": TEI_NS}

SECTION_PATTERNS = [
    (re.compile(r"\b(intro|background)", re.I), "intro"),
    (re.compile(r"\b(method|material|procedure)", re.I), "methods"),
    (re.compile(r"\b(result|finding)", re.I), "results"),
    (re.compile(r"\bdiscuss", re.I), "discussion"),
    (re.compile(r"\bconclu", re.I), "conclusion"),
]

# Text considered "meaningful" after the last citation: anything other than
# punctuation / whitespace / closing brackets.
MID_SENTENCE_TAIL = re.compile(r"[A-Za-z0-9]")


def classify_section(head_text: str) -> str:
    for pat, label in SECTION_PATTERNS:
        if pat.search(head_text):
            return label
    return "other"


def nearest_section(elem) -> str:
    for anc in elem.iterancestors():
        if anc.tag == f"{{{TEI_NS}}}div":
            head = anc.find("t:head", NS)
            if head is not None:
                txt = "".join(head.itertext()).strip()
                if txt:
                    return classify_section(txt)
    return "unknown"


def sentence_text(s_elem) -> str:
    # itertext pulls text from the sentence and any nested <ref> markers,
    # which is what we want -- it preserves the verbatim reading.
    return re.sub(r"\s+", " ", "".join(s_elem.itertext())).strip()


def extract_paper_meta(tree) -> Dict[str, Optional[str]]:
    title_el = tree.find(".//t:teiHeader//t:titleStmt/t:title", NS)
    title = "".join(title_el.itertext()).strip() if title_el is not None else None
    year = None
    date_el = tree.find(".//t:teiHeader//t:publicationStmt/t:date", NS)
    if date_el is not None:
        m = re.search(r"\d{4}", (date_el.get("when") or date_el.text or ""))
        if m:
            year = int(m.group())
    authors = []
    for pers in tree.findall(
        ".//t:teiHeader//t:sourceDesc//t:author/t:persName", NS
    ):
        sur = pers.find("t:surname", NS)
        fore = pers.find("t:forename", NS)
        parts = []
        if fore is not None and fore.text:
            parts.append(fore.text)
        if sur is not None and sur.text:
            parts.append(sur.text)
        if parts:
            authors.append(" ".join(parts))
    doi_el = tree.find(".//t:teiHeader//t:idno[@type='DOI']", NS)
    doi = doi_el.text.strip() if doi_el is not None and doi_el.text else None
    return {
        "title": title,
        "authors": "; ".join(authors) if authors else None,
        "year": year,
        "doi": doi,
    }


def biblstruct_to_row(b, fallback_local: int) -> Dict[str, Optional[str]]:
    xml_id = b.get(f"{{{XML_NS}}}id")
    title_el = b.find(".//t:title[@type='main']", NS)
    if title_el is None:
        title_el = b.find(".//t:title", NS)
    title = "".join(title_el.itertext()).strip() if title_el is not None else None

    authors = []
    for pers in b.findall(".//t:author/t:persName", NS):
        sur = pers.find("t:surname", NS)
        fore = pers.find("t:forename", NS)
        parts = []
        if fore is not None and fore.text:
            parts.append(fore.text)
        if sur is not None and sur.text:
            parts.append(sur.text)
        if parts:
            authors.append(" ".join(parts))

    year = None
    date_el = b.find(".//t:date[@when]", NS)
    if date_el is not None:
        m = re.search(r"\d{4}", date_el.get("when") or "")
        if m:
            year = int(m.group())

    doi = None
    doi_el = b.find(".//t:idno[@type='DOI']", NS)
    if doi_el is not None and doi_el.text:
        doi = doi_el.text.strip()

    # Local number: prefer the trailing digits in xml:id ("b4" -> 4); fall back
    # to source order.
    local_number = fallback_local
    if xml_id:
        m = re.search(r"(\d+)$", xml_id)
        if m:
            local_number = int(m.group(1)) + 1  # b0 -> [1]

    return {
        "tei_xml_id": xml_id,
        "local_number": local_number,
        "title": title,
        "authors": "; ".join(authors) if authors else None,
        "year": year,
        "doi": doi,
    }


def load_refs(conn, tree, paper_id: str) -> Dict[str, int]:
    cur = conn.cursor()
    mapping: Dict[str, int] = {}
    biblstructs = tree.findall(".//t:listBibl/t:biblStruct", NS)
    for i, b in enumerate(biblstructs):
        row = biblstruct_to_row(b, fallback_local=i + 1)
        cur.execute(
            """INSERT INTO refs
               (citing_paper_id, local_number, tei_xml_id, title, authors, year, doi)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (
                paper_id,
                row["local_number"],
                row["tei_xml_id"],
                row["title"],
                row["authors"],
                row["year"],
                row["doi"],
            ),
        )
        if row["tei_xml_id"]:
            mapping[row["tei_xml_id"]] = cur.lastrowid
    conn.commit()
    return mapping


def parse_paper(conn, tei_path: Path) -> None:
    paper_id = tei_path.stem.replace(".tei", "")
    tree = etree.parse(str(tei_path))

    # Wipe prior rows for this paper so re-runs are idempotent.
    cur = conn.cursor()
    cur.execute(
        """DELETE FROM citations WHERE claim_id IN
           (SELECT claim_id FROM claims WHERE citing_paper_id = ?)""",
        (paper_id,),
    )
    cur.execute("DELETE FROM claims WHERE citing_paper_id = ?", (paper_id,))
    cur.execute("DELETE FROM refs   WHERE citing_paper_id = ?", (paper_id,))

    meta = extract_paper_meta(tree)
    cur.execute(
        """INSERT INTO papers (paper_id, title, authors, year, doi, tei_path)
           VALUES (?, ?, ?, ?, ?, ?)
           ON CONFLICT(paper_id) DO UPDATE SET
             title=excluded.title, authors=excluded.authors,
             year=excluded.year, doi=excluded.doi,
             tei_path=excluded.tei_path, processed_at=CURRENT_TIMESTAMP""",
        (paper_id, meta["title"], meta["authors"], meta["year"], meta["doi"],
         str(tei_path)),
    )
    conn.commit()

    ref_map = load_refs(conn, tree, paper_id)

    n_claims = 0
    n_citations = 0
    for s in tree.findall(".//t:body//t:s", NS):
        bibrs = s.findall(".//t:ref[@type='bibr']", NS)
        if not bibrs:
            continue
        text = sentence_text(s)
        section = nearest_section(s)

        # Mid-sentence flag: meaningful text in the tail of the last bibr ref.
        last_tail = (bibrs[-1].tail or "").strip()
        needs_review = 0
        review_reason = None
        if last_tail and MID_SENTENCE_TAIL.search(last_tail):
            needs_review = 1
            review_reason = "mid-sentence citation"

        cur.execute(
            """INSERT INTO claims
               (citing_paper_id, verbatim_sentence, section,
                needs_review, review_reason)
               VALUES (?, ?, ?, ?, ?)""",
            (paper_id, text, section, needs_review, review_reason),
        )
        claim_id = cur.lastrowid
        n_claims += 1

        seen = set()
        for ref in bibrs:
            target = (ref.get("target") or "").lstrip("#")
            if not target or target in seen:
                continue
            ref_id = ref_map.get(target)
            if ref_id is None:
                continue
            cur.execute(
                "INSERT INTO citations (claim_id, ref_id) VALUES (?, ?)",
                (claim_id, ref_id),
            )
            seen.add(target)
            n_citations += 1

    conn.commit()
    print(f"{paper_id}: {n_claims} claims, {n_citations} citations, "
          f"{len(ref_map)} refs")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tei-dir", default="grobid_out")
    ap.add_argument("--db", default="db/citations.sqlite")
    args = ap.parse_args()

    tei_files = sorted(Path(args.tei_dir).glob("*.tei.xml"))
    if not tei_files:
        print(f"no TEI files in {args.tei_dir}")
        return

    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        for tei in tei_files:
            parse_paper(conn, tei)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
