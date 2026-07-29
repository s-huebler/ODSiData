#!/usr/bin/env python3
"""Build graph_data2.json for the batch-2 GVHD claims/evidence network.
Model (same as gvhd_claims_network_alt.html):
  nodes: review papers (Citing) + primary papers (ref) + claim nodes (canonical claims)
  edges: CITES  = review  -> primary  (review cites the primary for that claim)
         SUPPORTS = primary -> claim  (primary is evidence for the claim)
Source: Claims_Synthesis2.xlsx (Atomic_Claims + Canonical_Claims).
"""
import openpyxl, json, re
from collections import defaultdict, OrderedDict

XLSX = "/sessions/wonderful-magical-rubin/mnt/outputs/Claims_Synthesis2.xlsx"
wb = openpyxl.load_workbook(XLSX, read_only=True)

def sheet(name):
    rows = list(wb[name].iter_rows(values_only=True))
    hdr = rows[0]
    return [dict(zip(hdr, r)) for r in rows[1:]]

atomic = sheet("Atomic_Claims")
canon  = {r["canonical_claim_id"]: r for r in sheet("Canonical_Claims")}

# ---- claim wording: match alt style "X reduces / exacerbates GVHD" ----------
def claim_label(c):
    subj = c["subject"]
    v = c["valence"]
    if v == "favourable":
        return f"{subj} reduces GVHD"
    if v == "unfavourable":
        return f"{subj} exacerbates GVHD"
    if v == "context":
        return f"{subj} – context-dependent in GVHD"
    return f"{subj} – GVHD (unspecified)"

# ---- subjgroup: genus-level clustering for the ring (Clostridium cluster merged) ----
CLOSTRIDIA = {"clostridia","clostridiales","clostridium","lachnoclostridium","anaerostipes"}
def subjgroup(c):
    subj = c["subject"]; rank = c["subject_rank"]
    low = subj.lower()
    g = subj.split()[0] if rank == "species" else subj
    if g.lower() in CLOSTRIDIA or low.startswith("clostrid"):
        return "Clostridia"
    if rank == "functional":
        t = low
        if "scfa" in t: return "SCFA"
        if "bile" in t: return "bile_acid"
        if "indole" in t or "tryptophan" in t: return "tryptophan"
        if "lact" in t: return "lactate"
        if "gram-negative" in t: return "LPS"
        return "functional"
    return g

# ---- SUPPORTS: primary(ref) -> claim ; CITES: review(citing) -> primary(ref) ----
primaries = OrderedDict()   # ref_id -> label
reviews   = OrderedDict()   # citing_id -> label
supports  = OrderedDict()   # (ref_id, cid) -> {valence, w}
cites     = OrderedDict()   # (citing_id, ref_id) -> {valence, w}
claim_primaries = defaultdict(set)   # cid -> set(ref_id)
review_claims   = defaultdict(set)   # citing_id -> set(cid)
primary_claims  = defaultdict(set)   # ref_id -> set(cid)

for a in atomic:
    cid = a["canonical_claim_id"]
    cit_id, cit_lab = a["citing_id"], a["citing"]
    ref_id, ref_lab = a["ref_id"], a["ref_label"]
    val = a["valence"]
    if cit_id:
        reviews.setdefault(cit_id, cit_lab or cit_id)
        review_claims[cit_id].add(cid)
    if ref_id:
        primaries.setdefault(ref_id, ref_lab or ref_id)
        primary_claims[ref_id].add(cid)
        claim_primaries[cid].add(ref_id)
        k = (ref_id, cid)
        if k in supports: supports[k]["w"] += 1
        else: supports[k] = {"valence": val, "w": 1}
    if cit_id and ref_id:
        k = (cit_id, ref_id)
        if k in cites: cites[k]["w"] += 1
        else: cites[k] = {"valence": val, "w": 1}

# a node that is only ever a citing = review; only ever a ref = primary.
# (batch-2 citing set are the 10 reviews; refs are primaries. Handle overlap: review wins.)
review_ids = set(reviews)
primary_ids = set(primaries) - review_ids

nodes = []
# claim nodes
for cid, c in sorted(canon.items()):
    npr = len(claim_primaries[cid])
    nodes.append({"data": {
        "id": f"CLAIM_{cid}", "label": claim_label(c), "ntype": "claim",
        "valence": c["valence"] or "other", "subject": c["subject"],
        "subjgroup": subjgroup(c), "nprimary": npr, "size": 26 + npr * 4}})
# review paper nodes
for rid in reviews:
    nt = len(review_claims[rid])
    nodes.append({"data": {
        "id": rid, "label": reviews[rid], "ntype": "paper", "role": "review",
        "doi": "", "ntouched": nt, "size": 20 + nt * 3, "tmx": 0, "tmy": 0, "trot": 0}})
# primary paper nodes
for pid in primaries:
    if pid in review_ids:
        continue
    nt = len(primary_claims[pid])
    nodes.append({"data": {
        "id": pid, "label": primaries[pid], "ntype": "paper", "role": "primary",
        "doi": "", "ntouched": nt, "size": 20 + nt * 3, "tmx": 0, "tmy": 0, "trot": 0}})

edges = []
i = 0
for (ref_id, cid), v in supports.items():
    if ref_id in review_ids:  # skip if the "primary" is actually a review
        continue
    i += 1
    edges.append({"data": {"id": f"e{i}", "source": ref_id, "target": f"CLAIM_{cid}",
        "etype": "SUPPORTS", "valence": v["valence"] or "other",
        "weight": v["w"], "ewidth": 1.5 + v["w"] * 0.7}})
for (cit_id, ref_id), v in cites.items():
    if cit_id == ref_id:
        continue
    i += 1
    edges.append({"data": {"id": f"e{i}", "source": cit_id, "target": ref_id,
        "etype": "CITES", "valence": v["valence"] or "other",
        "weight": v["w"], "ewidth": 1.5 + v["w"] * 0.7}})

out = {"nodes": nodes, "edges": edges}
json.dump(out, open("/sessions/wonderful-magical-rubin/mnt/outputs/graph_data2.json", "w"))
nclaim = sum(1 for n in nodes if n["data"]["ntype"] == "claim")
nrev = sum(1 for n in nodes if n["data"].get("role") == "review")
nprim = sum(1 for n in nodes if n["data"].get("role") == "primary")
nsup = sum(1 for e in edges if e["data"]["etype"] == "SUPPORTS")
ncit = sum(1 for e in edges if e["data"]["etype"] == "CITES")
print(f"nodes={len(nodes)} (claims={nclaim} reviews={nrev} primaries={nprim}) "
      f"edges={len(edges)} (SUPPORTS={nsup} CITES={ncit})")
print("reviews:", [reviews[r] for r in reviews])
