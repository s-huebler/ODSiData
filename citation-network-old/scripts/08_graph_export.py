"""Export citation/concept graphs to GEXF (Gephi) and optional HTML.

Two graphs are produced:

paper_graph.gexf
    Directed paper -> paper. One edge per (claim, resolved citation), with
    concept_id on each edge so Gephi can colour by concept. Multi-edges
    are preserved (MultiDiGraph) -- collapse in Gephi by 'concept_id' if
    you want concept-weighted bundles.

concept_paper.gexf
    Bipartite directed graph of concepts and papers:
      AUTHORED_BY   citing paper -> concept   ("paper expresses idea")
      ATTRIBUTED_TO concept       -> cited paper ("idea originates here")
    Reading the in/out degree of each concept tells you which ideas are
    original to a paper vs which are inherited and propagated.

Usage (from citation-network/):
    python scripts/08_graph_export.py
    python scripts/08_graph_export.py --html
    python scripts/08_graph_export.py --out-dir outputs/graphs --html
"""

import argparse
import sqlite3
from pathlib import Path

import networkx as nx
import pandas as pd


def _add_paper_nodes(g: nx.Graph, conn: sqlite3.Connection) -> None:
    papers = pd.read_sql("SELECT paper_id, title, year FROM papers", conn)
    for _, p in papers.iterrows():
        if p["paper_id"] in g:
            g.nodes[p["paper_id"]]["title"] = p["title"] or ""
            g.nodes[p["paper_id"]]["year"] = (
                int(p["year"]) if pd.notna(p["year"]) else 0
            )
            g.nodes[p["paper_id"]].setdefault("kind", "paper")
            g.nodes[p["paper_id"]].setdefault("label", p["paper_id"])


def build_paper_graph(conn: sqlite3.Connection) -> nx.MultiDiGraph:
    df = pd.read_sql(
        """SELECT c.citing_paper_id AS src,
                  r.resolved_paper_id AS dst,
                  cc.concept_id      AS concept_id
             FROM claims c
             JOIN citations ci ON ci.claim_id = c.claim_id
             JOIN refs r       ON r.ref_id    = ci.ref_id
        LEFT JOIN claim_concepts cc ON cc.claim_id = c.claim_id
            WHERE r.resolved_paper_id IS NOT NULL""",
        conn,
    )
    g = nx.MultiDiGraph()
    for _, row in df.iterrows():
        concept_id = (
            int(row["concept_id"]) if pd.notna(row["concept_id"]) else -1
        )
        g.add_edge(row["src"], row["dst"], concept_id=concept_id)
    _add_paper_nodes(g, conn)
    return g


def build_concept_paper_graph(conn: sqlite3.Connection) -> nx.DiGraph:
    df = pd.read_sql(
        """SELECT c.citing_paper_id    AS citing,
                  r.resolved_paper_id  AS cited,
                  cc.concept_id        AS concept_id,
                  cn.label             AS concept_label
             FROM claims c
             JOIN claim_concepts cc ON cc.claim_id  = c.claim_id
             JOIN concepts cn       ON cn.concept_id = cc.concept_id
        LEFT JOIN citations ci      ON ci.claim_id  = c.claim_id
        LEFT JOIN refs r            ON r.ref_id     = ci.ref_id""",
        conn,
    )
    g = nx.DiGraph()
    for _, row in df.iterrows():
        c_node = f"C{int(row['concept_id'])}"
        if c_node not in g:
            label = row["concept_label"] or c_node
            g.add_node(c_node, kind="concept", label=str(label)[:60])
        if row["citing"] and row["citing"] not in g:
            g.add_node(row["citing"], kind="paper", label=row["citing"])
        if pd.notna(row["cited"]) and row["cited"] not in g:
            g.add_node(row["cited"], kind="paper", label=row["cited"])
        if row["citing"]:
            g.add_edge(row["citing"], c_node, kind="AUTHORED_BY")
        if pd.notna(row["cited"]):
            g.add_edge(c_node, row["cited"], kind="ATTRIBUTED_TO")
    return g


def write_html(g: nx.DiGraph, out_path: Path) -> None:
    try:
        from pyvis.network import Network
    except ImportError:
        print("pyvis not installed; skipping HTML "
              "(pip install pyvis to enable)")
        return
    net = Network(
        directed=True, height="800px", width="100%",
        bgcolor="#ffffff", font_color="#222",
    )
    for node, data in g.nodes(data=True):
        label = data.get("label", str(node))
        kind = data.get("kind", "paper")
        color = "#f59e0b" if kind == "concept" else "#3b82f6"
        shape = "dot" if kind == "concept" else "ellipse"
        net.add_node(str(node), label=label, color=color,
                     title=label, shape=shape)
    for u, v, data in g.edges(data=True):
        kind = data.get("kind", "")
        color = "#fbbf24" if kind == "ATTRIBUTED_TO" else "#93c5fd"
        net.add_edge(str(u), str(v), title=kind, color=color)
    net.toggle_physics(True)
    net.write_html(str(out_path), notebook=False, open_browser=False)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="db/citations.sqlite")
    ap.add_argument("--out-dir", default="outputs/graphs")
    ap.add_argument("--html", action="store_true",
                    help="also write concept_paper.html via pyvis")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(args.db)
    try:
        paper_g = build_paper_graph(conn)
        concept_g = build_concept_paper_graph(conn)
    finally:
        conn.close()

    nx.write_gexf(paper_g, str(out_dir / "paper_graph.gexf"))
    nx.write_gexf(concept_g, str(out_dir / "concept_paper.gexf"))
    print(f"paper_graph.gexf:   {paper_g.number_of_nodes()} nodes, "
          f"{paper_g.number_of_edges()} edges")
    print(f"concept_paper.gexf: {concept_g.number_of_nodes()} nodes, "
          f"{concept_g.number_of_edges()} edges")

    if args.html:
        html_path = out_dir / "concept_paper.html"
        write_html(concept_g, html_path)
        if html_path.exists():
            print(f"wrote {html_path}")


if __name__ == "__main__":
    main()
