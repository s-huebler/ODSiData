#!/usr/bin/env python3
"""
Jarosch2023 — per-sample alpha diversity + clinical fingerprint match.

Computes Observed richness, Shannon (natural log) and Gini-Simpson (1 - sum p^2)
for each sequenced sample straight from QiimeData/table.qza, maps the ENA run
IDs (ERR...) to the submitter Sample_name codes (R000... / ADM5 ...), and tries
to match each sample to a clinical stool sample by its (Shannon, Simpson)
fingerprint — the only bridge available, since the two files share no ID column.

Definitions are chosen to match the paper's R (dada2 -> vegan/phyloseq) workflow:
  * Shannon  = -sum(p*ln(p))         (natural log; vegan/phyloseq default)
  * Simpson  = 1 - sum(p^2)          (Gini-Simpson; vegan index="simpson")
  * Richness = number of ASVs > 0    (Observed)
Clinical Simpson is in 0-1 (Gini) and Shannon max ~3.8 (ln), consistent with these.

Usage:
    python3 alpha_diversity_match.py [STUDY_DIR]
STUDY_DIR defaults to ~/Documents/ODSi/ODSiData/Jarosch2023
Requires: numpy, pandas, biom-format  (all in the qiime2 env; or pip install)
"""
import sys, os, glob, zipfile, tempfile
import numpy as np, pandas as pd

STUDY_DIR = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1
                               else "~/Documents/ODSi/ODSiData/Jarosch2023")
TABLE_QZA = os.path.join(STUDY_DIR, "QiimeData", "table.qza")
META_SAMP = os.path.join(STUDY_DIR, "Metadata", "Raw_metadata", "meta_samples.csv")
META_CLIN = os.path.join(STUDY_DIR, "Metadata", "Raw_metadata", "meta_clinical.csv")
OUT_DIV   = os.path.join(STUDY_DIR, "Metadata", "jarosch_alpha_diversity.tsv")
OUT_MATCH = os.path.join(STUDY_DIR, "Metadata", "jarosch_sample_to_clinical.tsv")

SHANNON_LOG = np.log        # natural log; swap to np.log2 / np.log10 to test bases

# --- 1. load the feature table (features x samples) from the .qza ------------
def load_biom_from_qza(qza):
    tmp = tempfile.mkdtemp()
    with zipfile.ZipFile(qza) as z:
        z.extractall(tmp)
    biom = glob.glob(f"{tmp}/*/data/feature-table.biom")[0]
    from biom import load_table
    t = load_table(biom)
    M = t.matrix_data.toarray()                     # features x samples
    return M, list(map(str, t.ids("sample")))

M, samples = load_biom_from_qza(TABLE_QZA)

# --- 2. alpha diversity per sample ------------------------------------------
def alpha(counts):
    counts = counts[counts > 0].astype(float)
    n = counts.sum()
    p = counts / n
    richness = int((counts > 0).sum())
    shannon  = float(-(p * SHANNON_LOG(p)).sum())
    simpson  = float(1.0 - (p * p).sum())           # Gini-Simpson
    return richness, shannon, simpson, int(n)

div = pd.DataFrame(
    [alpha(M[:, j]) for j in range(M.shape[1])],
    columns=["Richness", "Shannon", "Simpson", "depth"],
    index=samples,
).rename_axis("Run").reset_index()

# --- 3. map ENA Run (ERR...) -> submitter Sample_name (R000.../ADM5) ---------
ms = pd.read_csv(META_SAMP)
run2name = dict(zip(ms["Run"].astype(str), ms["Sample_name"].astype(str)))
div.insert(1, "Sample_name", div["Run"].map(run2name))
div.to_csv(OUT_DIV, sep="\t", index=False)
print(f"[wrote] {OUT_DIV}  ({len(div)} samples)")

# --- 4. clinical fingerprints: collapse biopsies -> unique stool samples -----
clin = pd.read_csv(META_CLIN)
clin = clin[clin["16S data"].astype(str).str.strip() == "yes"].copy()
for c in ["Richness", "Simpson", "Shannon"]:
    clin[c] = pd.to_numeric(clin[c], errors="coerce")
# one stool sample == one unique (Richness, Simpson, Shannon) triplet
agg = (clin.groupby(["Richness", "Simpson", "Shannon"], as_index=False)
            .agg(Patients=("Patient", lambda s: ";".join(sorted(set(s)))),
                 Biopsies=("Biopsy", lambda s: ";".join(sorted(set(s))))))
print(f"[info] {len(clin)} clinical 16S rows -> {len(agg)} unique stool fingerprints")

# --- 5. OPTIMAL one-to-one match on standardized (Shannon, Simpson) ----------
# richness excluded from the distance (systematic pipeline offset); reported only.
# Each stool sample should map to exactly one clinical fingerprint, so we solve a
# global assignment (Hungarian) minimizing total distance rather than letting
# samples independently grab the same nearest clinical point. There are more
# sequenced samples (53) than clinical stools (46), so the 7 worst-fit samples
# are left unassigned (the extra longitudinal stools with no 16S=yes biopsy).
from scipy.optimize import linear_sum_assignment

def zpair(sh, si):
    return np.array([(sh - mu[0]) / sd[0], (si - mu[1]) / sd[1]])

both_sh = np.concatenate([div["Shannon"].values, agg["Shannon"].values])
both_si = np.concatenate([div["Simpson"].values, agg["Simpson"].values])
mu = (both_sh.mean(), both_si.mean())
sd = (both_sh.std() or 1, both_si.std() or 1)

dv = div.dropna(subset=["Shannon", "Simpson"]).reset_index(drop=True)
S = np.vstack([zpair(r.Shannon, r.Simpson) for r in dv.itertuples()])       # samples
C = np.vstack([zpair(r.Shannon, r.Simpson) for r in agg.itertuples()])      # clinical
D = np.linalg.norm(S[:, None, :] - C[None, :, :], axis=2)                   # n_samp x n_clin

row_ix, col_ix = linear_sum_assignment(D)          # optimal 1:1 (min over 46 pairs)
assigned = {int(r): int(c) for r, c in zip(row_ix, col_ix)}

rows = []
for i, r in enumerate(dv.itertuples()):
    if i in assigned:
        j = assigned[i]; a = agg.iloc[j]
        dist = float(D[i, j])
        # runner-up distance for THIS sample -> confidence margin
        second = float(np.sort(D[i])[1]) if D.shape[1] > 1 else dist
        margin = second - dist
        conf = "high" if dist < 0.10 else "medium" if dist < 0.30 else "low"
        rows.append(dict(
            Run=r.Run, Sample_name=r.Sample_name,
            our_Shannon=round(r.Shannon, 4), our_Simpson=round(r.Simpson, 4),
            our_Richness=r.Richness,
            match_Patients=a.Patients, match_Biopsies=a.Biopsies,
            clin_Shannon=a.Shannon, clin_Simpson=a.Simpson, clin_Richness=int(a.Richness),
            dist=round(dist, 4), margin=round(margin, 4),
            richness_diff=r.Richness - int(a.Richness), confidence=conf))
    else:
        rows.append(dict(
            Run=r.Run, Sample_name=r.Sample_name,
            our_Shannon=round(r.Shannon, 4), our_Simpson=round(r.Simpson, 4),
            our_Richness=r.Richness, match_Patients="(unassigned)", match_Biopsies="",
            clin_Shannon=np.nan, clin_Simpson=np.nan, clin_Richness=np.nan,
            dist=np.nan, margin=np.nan, richness_diff=np.nan, confidence="unmatched"))

order = {"high":0, "medium":1, "low":2, "unmatched":3}
match = (pd.DataFrame(rows)
           .sort_values(["confidence", "dist"], key=lambda s: s.map(order) if s.name=="confidence" else s))
match.to_csv(OUT_MATCH, sep="\t", index=False)
print(f"[wrote] {OUT_MATCH}")
print(match["confidence"].value_counts().reindex(order).dropna().to_string())
