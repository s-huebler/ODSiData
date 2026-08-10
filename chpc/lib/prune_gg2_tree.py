#!/usr/bin/env python3
"""
prune_gg2_tree.py — memory-light replacement for `qiime phylogeny filter-tree`.

Shears the full Greengenes2 id-keyed reference phylogeny (~23.4M tips) down to the
features in a merged QIIME2 feature table, using the succinct balanced-parentheses
tree library (bp / "improved-octo-waddle", PyPI package `iow`).

Why: `qiime phylogeny filter-tree` inflates the entire 23.4M-tip GG2 tree into a
scikit-bio TreeNode object graph (~80-150 GB RAM) before pruning to your ~5k
features — which is what forced 08_phylogeny onto a 240 GB big-memory node and made
the stage slow. The bp structure holds the same tree in ~2-4 GB, so shearing runs
in minutes on an ordinary shared node. The pruned tree is identical to filter-tree's
output; it is written as Newick (.nwk) rather than a .qza (the caller re-imports it).

------------------------------------------------------------------------------
Dependencies: `bp` (PyPI `iow`) and `biom` (biom-format). Both are already present
in the personal q2-greengenes2 conda env (GG2_ENV, activated by
`load_qiime2_gg2_env` in chpc/config.sh), which is what 08_phylogeny.slurm uses.
The compiled deps use AVX2, so run this on a modern node (notchpeak-shared-short),
not the old lonepeak Nehalem cores.

------------------------------------------------------------------------------
Usage (paths are supplied by the caller; nothing is hard-coded here). As invoked by
08_phylogeny.slurm from the repo root:

    python chpc/lib/prune_gg2_tree.py \
        --tree  "$GG2_PHYLOGENY" \
        --table "$MERGED_TABLE" \
        --out   "$MW/merged-tree.nwk"

The small pruned tree is then wrapped into a .qza by the job (trivial import, only
~thousands of tips — unlike filter-tree):

    qiime tools import \
        --input-path merged-tree.nwk \
        --output-path merged-tree.qza \
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
                         "$GG2_PHYLOGENY (2024.09.phylogeny.id.nwk.qza)")
    ap.add_argument("--table", required=True,
                    help="Merged feature table (.qza or .biom), e.g. merged-table.qza")
    ap.add_argument("--out", default="merged-tree.nwk",
                    help="Output pruned Newick path (default: merged-tree.nwk)")
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
        sys.exit("ERROR: the `bp` module is not installed. It ships with the "
                 "q2-greengenes2 env (GG2_ENV); activate it via load_qiime2_gg2_env, "
                 "or install with:\n"
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
