"""Batch-process PDFs through a local GROBID server.

Prereq: GROBID running on http://localhost:8070 (see top-level setup notes).

Usage (from citation-network/):
    python scripts/01_run_grobid.py
    python scripts/01_run_grobid.py --pdf-dir pdfs --out-dir grobid_out

Writes one <stem>.tei.xml per PDF. Skips files already processed.
"""

import argparse
import sys
from pathlib import Path

import requests

GROBID_URL = "http://localhost:8070/api/processFulltextDocument"

# segmentSentences=1 wraps every sentence in <s>, which the parser relies on.
# consolidateCitations=1 enriches references via CrossRef when possible.
# includeRawCitations=1 keeps the raw citation string for fallback matching.
PARAMS = {
    "segmentSentences": "1",
    "consolidateCitations": "1",
    "includeRawCitations": "1",
    "teiCoordinates": "ref,biblStruct",
}


def process_pdf(pdf_path: Path, out_dir: Path, force: bool) -> bool:
    out_path = out_dir / (pdf_path.stem + ".tei.xml")
    if out_path.exists() and not force:
        print(f"skip (exists): {pdf_path.name}")
        return True
    try:
        with pdf_path.open("rb") as f:
            files = {"input": (pdf_path.name, f, "application/pdf")}
            r = requests.post(GROBID_URL, files=files, data=PARAMS, timeout=600)
    except requests.RequestException as e:
        print(f"FAIL ({e.__class__.__name__}): {pdf_path.name} -- {e}")
        return False
    if r.status_code != 200:
        print(f"FAIL ({r.status_code}): {pdf_path.name}")
        return False
    out_path.write_text(r.text, encoding="utf-8")
    print(f"done: {pdf_path.name} -> {out_path.name}")
    return True


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf-dir", default="pdfs")
    ap.add_argument("--out-dir", default="grobid_out")
    ap.add_argument("--force", action="store_true",
                    help="reprocess even if TEI already exists")
    args = ap.parse_args()

    pdf_dir = Path(args.pdf_dir)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    pdfs = sorted(pdf_dir.glob("*.pdf"))
    if not pdfs:
        print(f"no PDFs in {pdf_dir.resolve()}")
        sys.exit(1)

    ok = 0
    for p in pdfs:
        if process_pdf(p, out_dir, args.force):
            ok += 1
    print(f"\n{ok}/{len(pdfs)} processed")


if __name__ == "__main__":
    main()
