"""Shared paths and helpers for the claims network scripts (standard library only)."""
import csv, json, os, re, unicodedata
from pathlib import Path

CN = Path(__file__).resolve().parent.parent          # claim-network/
REPO = CN.parent                                     # ODSiData/
REVIEWS = CN / "reviews"
SKILLS = CN / ".claude" / "skills"
LOOKUPS = CN / "lookups"
OUTPUT = CN / "output"
DICTIONARY = REPO / "citation-network" / "Full_Network" / "citing_dictionary.csv"
CLAIMS = REVIEWS / "claims.csv"
CLAIMS_LINKED = REVIEWS / "claims_linked.csv"
TAXA = REVIEWS / "taxa.csv"

FIELDS = ["taxon_as_cited", "taxon_rank_as_cited", "direction", "evidence_as_stated", "evidence",
          "mechanism_broad", "mechanism_specific", "target_type", "intervention",
          "mechanism_as_named", "ref_string", "mechanism_assignment"]

VOCAB = {
    "taxon_rank_as_cited": ["species", "genus", "family", "order", "class", "phylum", "functional group"],
    "direction": ["protective", "exacerbating", "context-dependent", "unspecified", "no effect"],
    "evidence": ["human observational", "human interventional", "murine", "unspecified"],
    "mechanism_specific": ["0. Unattributed", "1a. SCFA / butyrate signaling", "1b. Bile acid signaling",
                           "1c. Tryptophan / indole signaling", "1d. Other metabolites", "2a. Innate immune",
                           "2b. T-cell adaptive", "2c. Other immune", "3a. Epithelial barrier",
                           "4a. Colonization resistance / competitive exclusion",
                           "4b. Pathobiont expansion / mono-dominance"],
    "target_type": ["taxon", "mechanism"],
    "intervention": ["", "diet", "antibiotic", "probiotic / LBP", "FMT", "defined consortium", "other"],
}


def mechanism_broad(specific):
    k = specific.split(".")[0]
    if k == "0": return "Class 0: Unattributed"
    if k.startswith("1"): return "Class 1: Metabolite-mediated"
    if k.startswith("2"): return "Class 2: Immune cell targeting"
    if k == "3a": return "Class 3: Barrier and structural"
    return "Class 4: Pathobiont expansion"


def review_dirs():
    return sorted(p.parent for p in REVIEWS.glob("*/proposals.json"))


def load_json(p, default=None):
    try:
        return json.loads(Path(p).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


def write_json(p, obj):
    p = Path(p); tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, indent=1, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, p)


def read_csv(p):
    with open(p, newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def write_csv(p, rows, cols):
    p = Path(p); tmp = p.with_suffix(p.suffix + ".tmp")
    with open(tmp, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})
    os.replace(tmp, p)


DECISION_COLS = ["id", "kind", "decision", "edited", "review_note", "discussion", "decided_at",
                 "location", "quote"] + FIELDS


def write_decisions_csv(review_dir, decisions, proposals):
    """Mirror decisions.json to decisions.csv in proposal order."""
    order = {it["id"]: i for i, it in enumerate(proposals["items"])}
    rows = []
    for r in sorted(decisions.values(), key=lambda r: order.get(r["id"], 10**6)):
        flat = dict(r); flat.update((r.get("fields") or {}))
        rows.append(flat)
    write_csv(Path(review_dir) / "decisions.csv", rows, DECISION_COLS)


def norm_text(s):
    """Normalize text for quote matching: NFKC, unify quotes/dashes/space, lowercase."""
    s = unicodedata.normalize("NFKC", s)
    s = re.sub(r"[‘’ʼ′`]", "'", s)
    s = re.sub(r"[“”]", '"', s)
    s = re.sub(r"[‐-―−]", "-", s)
    return re.sub(r"\s+", " ", s).strip().lower()


def markdown_plain(md):
    """Approximate the rendered text of a paper.md (for quote checks outside the viewer)."""
    s = re.sub(r"<sup>\s*\[[\d,\s\-‐-―]+\]\s*</sup>", "", md)   # citation superscripts
    s = re.sub(r"</?[A-Za-z][^>]*>", "", s)                                          # other tags
    s = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", s)                       # links
    s = re.sub(r"(?<![A-Za-z0-9])[_*]+|[_*]+(?![A-Za-z0-9])", "", s)       # emphasis markers
    s = s.replace("\\", "").replace("|", " ")
    return norm_text(s)


def explode_refs(ref_string):
    """'[32,33]' -> ['[32]','[33]'];  '[60-63]' -> 4 refs;  'Taur 2014; Jenq 2012' -> 2 refs; '' -> ['']"""
    s = (ref_string or "").strip()
    if not s:
        return [""]
    if s.startswith("["):
        out = []
        for part in re.findall(r"\d+\s*[-‐-―]\s*\d+|\d+", s):
            m = re.match(r"(\d+)\s*[-‐-―]\s*(\d+)", part)
            nums = range(int(m.group(1)), int(m.group(2)) + 1) if m else [int(part)]
            out += [f"[{n}]" for n in nums]
        return out or [s]
    return [p.strip() for p in s.split(";") if p.strip()]


def ascii_lower(s):
    return unicodedata.normalize("NFKD", str(s)).encode("ascii", "ignore").decode().lower().strip()
