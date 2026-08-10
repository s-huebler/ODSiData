#!/usr/bin/env python3
"""
prune_gg2_tree.py — memory-light local alternative to `qiime phylogeny filter-tree`.

Shears the full Greengenes2 id-keyed reference phylogeny (~23.4M tips) down to the
features in a merged QIIME2 feature table, using the succinct balanced-parentheses
tree library (bp / "improved-octo-waddle", PyPI package `iow`).

Why: `qiime phylogeny filter-tree` inflates the entire 23.4M-tip GG2 tree into a
scikit-bio TreeNode object graph (~80-150 GB RAM) before pruning to your ~5k
features — which is what OOM-killed the cluster job and would swap-thrash a laptop.
The bp structure holds the same tree in ~2-4 GB, so shearing runs on a laptop in
minutes.

------------------------------------------------------------------------------
Install (once). The package is `iow` on PyPI (imports as `bp`); numpy+cython must
be present BEFORE it builds. Easiest inside your existing x86 qiime2 env, or a
fresh env:

    conda create -n bp python=3.10 numpy cython -y
    conda activate bp
    pip install iow biom-format

------------------------------------------------------------------------------
Usage (run from Merging_Temp/, mirroring your filter-tree command):

    python prune_gg2_tree.py \
        --tree  ../Greengenes2/2024.09.phylogeny.id.nwk.qza \
        --table merged-table.qza \
        --out   local-merged-tree.nwk

Then (optional) wrap the small pruned tree into a .qza — this import is trivial
(only ~thousands of tips), unlike filter-tree:

    qiime tools import \
        --input-path local-merged-tree.nwk \
        --output-path local-merged-tree.qza \
        --type 'Phylogeny[Rooted]'

Inputs may be .qza (they'll be read from inside the zip) or already-extracted
.nwk / .biom files — detected by extension.
------------------------------------------------------------------------------
"""

import argparse
import os
import sys
import tempfile
import zipfile


def _find_in_qza(qza_path, suffix):
    """Return the archive member ending in `suffix` (e.g. 'data/tree.nwk')."""
    with zipfile.ZipFile(qza_path) as zf:
        hits = [n for n in zf.namelist() if n.endswith(suffix)]
    if not hits:
        sys.exit(f"ERROR: no '{suffix}' found inside {qza_path} "
                 f"(is this the right .qza?)")
    if len(hits) > 1:
        sys.exit(f"ERROR: multiple '{suffix}' entries in {qza_path}: {hits}")
    return hits[0]


def read_newick_string(tree_path):
    """Read the Newick text from a .qza (data/tree.nwk) or a raw .nwk file."""
    if tree_path.endswith(".qza"):
        member = _find_in_qza(tree_path, "data/tree.nwk")
        with zipfile.ZipFile(tree_path) as zf:
            with zf.open(member) as fh:
                return fh.read().decode("utf-8")
    # raw newick
    with open(tree_path) as fh:
        return fh.read()


def read_feature_ids(table_path):
    """Return the set of feature (observation) IDs from a table .qza or .biom."""
    import biom

    if table_path.endswith(".qza"):
        member = _find_in_qza(table_path, "data/feature-table.biom")
        with zipfile.ZipFile(table_path) as zf:
            with tempfile.NamedTemporaryFile(suffix=".biom", delete=False) as tmp:
                tmp.write(zf.read(member))
                biom_path = tmp.name
        try:
            table = biom.load_table(biom_path)
        finally:
            os.unlink(biom_path)
    else:
        table = biom.load_table(table_path)

    return set(map(str, table.ids(axis="observation")))


def main():
    ap = argparse.ArgumentParser(
        description="Shear the GG2 reference tree to a feature table's IDs (low memory).")
    ap.add_argument("--tree", required=True,
                    help="GG2 id-keyed phylogeny (.qza or .nwk), e.g. "
                         "../Greengenes2/2024.09.phylogeny.id.nwk.qza")
    ap.add_argument("--table", required=True,
                    help="Merged feature table (.qza or .biom), e.g. merged-table.qza")
    ap.add_argument("--out", default="local-merged-tree.nwk",
                    help="Output pruned Newick path (default: local-merged-tree.nwk)")
    ap.add_argument("--no-collapse", action="store_true",
                    help="Skip collapsing the unary internal nodes shearing introduces "
                         "(collapse is on by default and is what filter-tree does).")
    args = ap.parse_args()

    for p in (args.tree, args.table):
        if not os.path.exists(p):
            sys.exit(f"ERROR: input not found: {p}")

    try:
        import bp
    except ImportError:
        sys.exit("ERROR: the `bp` module is not installed. Install with:\n"
                 "    conda install numpy cython -y && pip install iow biom-format")

    print(f"[1/4] Reading feature IDs from {args.table} ...", flush=True)
    ids = read_feature_ids(args.table)
    print(f"      {len(ids):,} features in the table", flush=True)

    print(f"[2/4] Parsing reference tree {args.tree} "
          f"(this is the memory step, ~2-4 GB) ...", flush=True)
    tree = bp.parse_newick(read_newick_string(args.tree))
    print(f"      reference tree parsed: {tree.ntips():,} tips", flush=True)

    print(f"[3/4] Shearing to the {len(ids):,} cohort features ...", flush=True)
    try:
        sheared = tree.shear(ids)
    except ValueError as e:
        sys.exit(f"ERROR: {e}. None of the table's feature IDs are tips in this "
                 f"tree — check you're using the ID-keyed tree "
                 f"(2024.09.phylogeny.id.nwk.qza), not the .asv. tree.")
    if not args.no_collapse:
        sheared = sheared.collapse()

    print(f"[4/4] Writing pruned tree to {args.out} ...", flush=True)
    skbio_tree = bp.to_skbio_treenode(sheared)
    kept = {t.name for t in skbio_tree.tips()}
    skbio_tree.write(args.out)

    missing = ids - kept
    print(f"\nDone. Pruned tree: {len(kept):,} tips written to {args.out}")
    if missing:
        print(f"NOTE: {len(missing):,} of {len(ids):,} table features were NOT found "
              f"as tips in the reference tree and were dropped.")
        print("      (core-metrics-phylogenetic requires every table feature to be in "
              "the tree, so\n       filter those features out of the table before "
              "diversity, or investigate why\n       they aren't in the GG2 backbone.)")
        preview = list(missing)[:5]
        print(f"      examples: {preview}")
    else:
        print("All table features were retained in the tree.")

    print("\nOptional — wrap into a QIIME2 artifact (fast; small tree):")
    qza = os.path.splitext(args.out)[0] + ".qza"
    print(f"    qiime tools import --input-path {args.out} \\\n"
          f"        --output-path {qza} --type 'Phylogeny[Rooted]'")


if __name__ == "__main__":
    main()
