"""Embed claims, cluster with HDBSCAN, populate concepts + claim_concepts.

Embedding text precedence:
  paraphrased_claim if non-empty, else verbatim_sentence.

Re-runs are destructive on the concept tables: claim_concepts and concepts
are wiped before rewriting, so iterating on min_cluster_size or model is
cheap. The xlsx export is sorted by cluster so you can scan/merge labels.

Suggested workflow:
  1. Run with defaults; inspect concepts_review.xlsx.
  2. If too many clusters / too granular, raise --min-cluster-size.
  3. If too much noise (cluster = -1), lower --min-cluster-size or try a
     different model.

Usage (from citation-network/):
    python scripts/07_cluster_concepts.py
    python scripts/07_cluster_concepts.py --min-cluster-size 4 \
        --model BAAI/bge-small-en-v1.5 --out concepts_review.xlsx
"""

import argparse
import sqlite3

import hdbscan
import numpy as np
import pandas as pd
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_distances


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="db/citations.sqlite")
    ap.add_argument("--model", default="BAAI/bge-small-en-v1.5")
    ap.add_argument("--min-cluster-size", type=int, default=3)
    ap.add_argument("--min-samples", type=int, default=1)
    ap.add_argument("--out", default="concepts_review.xlsx")
    args = ap.parse_args()

    conn = sqlite3.connect(args.db)
    df = pd.read_sql(
        """SELECT claim_id, citing_paper_id,
                  COALESCE(NULLIF(TRIM(paraphrased_claim), ''),
                           verbatim_sentence) AS text
             FROM claims
            WHERE COALESCE(NULLIF(TRIM(paraphrased_claim), ''),
                           verbatim_sentence) IS NOT NULL
              AND TRIM(COALESCE(NULLIF(TRIM(paraphrased_claim), ''),
                                verbatim_sentence)) != ''""",
        conn,
    )
    if df.empty:
        print("no claims to cluster")
        conn.close()
        return
    print(f"embedding {len(df)} claims with {args.model}")

    model = SentenceTransformer(args.model)
    emb = model.encode(
        df["text"].tolist(),
        normalize_embeddings=True,
        show_progress_bar=True,
    )

    # HDBSCAN over precomputed cosine distance.
    dist = cosine_distances(emb).astype(np.float64)
    clusterer = hdbscan.HDBSCAN(
        metric="precomputed",
        min_cluster_size=args.min_cluster_size,
        min_samples=args.min_samples,
        cluster_selection_method="eom",
    )
    labels = clusterer.fit_predict(dist)
    df["cluster"] = labels
    n_clusters = int(labels.max() + 1) if (labels >= 0).any() else 0
    n_noise = int((labels == -1).sum())
    print(f"clusters: {n_clusters}   noise: {n_noise}")

    # Rewrite concept tables from scratch.
    cur = conn.cursor()
    cur.execute("DELETE FROM claim_concepts")
    cur.execute("DELETE FROM concepts")
    conn.commit()

    cluster_to_concept = {}
    for cid in sorted(set(int(c) for c in labels) - {-1}):
        idxs = np.where(labels == cid)[0]
        centroid = emb[idxs].mean(axis=0)
        centroid /= np.linalg.norm(centroid) + 1e-12
        sims = emb[idxs] @ centroid
        medoid_idx = idxs[int(np.argmax(sims))]
        auto_label = str(df.iloc[medoid_idx]["text"])[:140]
        cur.execute(
            "INSERT INTO concepts (label, definition) VALUES (?, ?)",
            (auto_label, None),
        )
        cluster_to_concept[cid] = cur.lastrowid

    for claim_id, cid in zip(df["claim_id"], labels):
        cid = int(cid)
        if cid == -1:
            continue
        cur.execute(
            "INSERT OR IGNORE INTO claim_concepts (claim_id, concept_id) "
            "VALUES (?, ?)",
            (int(claim_id), cluster_to_concept[cid]),
        )
    conn.commit()
    conn.close()

    df["concept_id"] = df["cluster"].map(
        lambda c: cluster_to_concept.get(int(c)) if c != -1 else None
    )
    out_df = (
        df.sort_values(["concept_id", "claim_id"], na_position="last")
          [["concept_id", "cluster", "claim_id", "citing_paper_id", "text"]]
    )
    out_df.to_excel(args.out, index=False)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
