#!/usr/bin/env python3
"""
extract_read_counts.py — per-sample read-attrition table from QIIME2 artifacts,
without running QIIME2.

Reads six visualizer/artifact zips per study and stitches their per-sample counts
into one wide table (input -> trimmed -> filtered -> denoised -> merged ->
non_chimeric -> qc -> mapped). Every artifact QIIME2 produces is a zip whose
payload lives under a single random UUID directory (<uuid>/data/<file>), so
members are matched by suffix, never by a hardcoded UUID.

Dependencies: python3 stdlib only (zipfile, csv, argparse, pathlib). No h5py, no
numpy, no biom, no qiime, no vsearch — run under the plain login-node python3,
no modules loaded. If a required artifact is missing, this script says so and
stops; it does not install or build anything to work around it.

Sources per column:
  input                          <- QiimeData/demux_viz.qzv
  trimmed                        <- QiimeData/demux_trimmed_viz.qzv (may not exist)
  filtered/denoised/merged/
    non_chimeric                 <- QiimeData/stats.qza (DADA2 stats.tsv, all three
                                     arms, or a Deblur stats.csv)
  qc                             <- Mapped/qc-table_viz.qzv
  mapped                         <- Mapped/mapped-table_viz.qzv
  (cross-check only)             <- QiimeData/table_viz.qzv, must match the
                                     stats.qza non-chimeric column

Usage:
    python3 chpc/lib/extract_read_counts.py <Study> \
        [--repo-root PATH] [--work-base PATH] [--out-dir PATH]

Defaults: --repo-root = `git rev-parse --show-toplevel` (falls back to the
parent of this script's chpc/ dir, same rule chpc/config.sh uses); --work-base =
$WORK_BASE (falls back to $SCRATCH_BASE/ODSiData, mirroring config.sh's own
default); --out-dir = Merging/ReadCounts (resolved under --repo-root if
relative).

Writes, under --out-dir:
    <Study>_read_counts.tsv       one row per sample, gaps filled (see below)
    <Study>_read_counts_raw.tsv   same columns minus stages_imputed, gaps blank

Outer-joins on sample-id across all sources, then fills gaps left-to-right in
pipeline order. Two kinds of gap, filled differently:
  - stage-level absent: the study's arm never produces this column at all (no
    demux_trimmed_viz.qzv; denoise-single/denoise-pyro have no 'merged' column;
    a Deblur arm has no 'filtered'/'merged' column). Detected from the sources
    themselves. Carries the previous stage's value forward for every sample, so
    the missing step draws flat instead of dropping to zero. Recorded in
    stages_imputed.
  - sample-level absent: the column DOES exist for the study, but this sample
    has no row in that particular artifact — it lost all its reads at that
    stage. Written as 0, not carried forward. Once a sample hits 0 it stays 0
    for every later stage.

'input' is the first stage: if QiimeData/demux_viz.qzv doesn't exist at all,
there is nothing to carry forward from, so that is a hard error, not a guess.
"""
import argparse
import csv
import io
import os
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

PIPELINE = ["input", "trimmed", "filtered", "denoised", "merged", "non_chimeric", "qc", "mapped"]


def default_repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=Path(__file__).resolve().parent,
            capture_output=True, text=True, check=True,
        )
        return Path(out.stdout.strip())
    except Exception:
        # chpc/lib/extract_read_counts.py -> parents[1] is chpc/, parents[2] is the repo root.
        return Path(__file__).resolve().parents[2]


def default_work_base() -> Path:
    wb = os.environ.get("WORK_BASE")
    if wb:
        return Path(wb)
    scratch_base = os.environ.get("SCRATCH_BASE") or f"/scratch/general/vast/{os.environ.get('USER', '')}"
    return Path(scratch_base) / "ODSiData"


def find_source(repo_root: Path, work_base: Path, study: str, relpath: str) -> Optional[Path]:
    for root in (repo_root, work_base):
        p = root / study / relpath
        if p.is_file():
            return p
    return None


def find_member(zf: zipfile.ZipFile, suffix: str) -> str:
    matches = [n for n in zf.namelist() if n.endswith(suffix)]
    if not matches:
        raise LookupError(f"no member ending in '{suffix}' inside {zf.filename}")
    if len(matches) > 1:
        raise LookupError(f"ambiguous members ending in '{suffix}' inside {zf.filename}: {matches}")
    return matches[0]


def read_fastq_counts(path: Path) -> Dict[str, int]:
    """QiimeData/demux*_viz.qzv -> {sample-id: forward sequence count}."""
    with zipfile.ZipFile(path) as zf:
        member = find_member(zf, "data/per-sample-fastq-counts.tsv")
        with zf.open(member) as fh:
            text = io.TextIOWrapper(fh, encoding="utf-8", newline="")
            reader = csv.DictReader(text, delimiter="\t")
            counts = {}
            for row in reader:
                counts[row["sample ID"]] = int(float(row["forward sequence count"]))
    return counts


def read_stats(path: Path) -> Tuple[Dict[str, Dict[str, int]], Set[str]]:
    """QiimeData/stats.qza -> ({stage: {sample-id: count}}, {stages present})."""
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        tsv_matches = [n for n in names if n.endswith("data/stats.tsv")]
        csv_matches = [n for n in names if n.endswith("data/stats.csv")]
        if tsv_matches and csv_matches:
            raise LookupError(f"{path} has both data/stats.tsv and data/stats.csv — ambiguous arm")

        if tsv_matches:
            if len(tsv_matches) > 1:
                raise LookupError(f"ambiguous data/stats.tsv members in {path}: {tsv_matches}")
            with zf.open(tsv_matches[0]) as fh:
                text = io.TextIOWrapper(fh, encoding="utf-8", newline="")
                reader = csv.reader(text, delimiter="\t")
                header = next(reader)
                col = {name: i for i, name in enumerate(header)}
                sid_i = col["sample-id"]
                col_map = {"filtered": "filtered", "denoised": "denoised", "non_chimeric": "non-chimeric"}
                if "merged" in col:
                    col_map["merged"] = "merged"
                present = set(col_map)
                data = {stage: {} for stage in present}
                for row in reader:
                    if not row or row[0] == "#q2:types":
                        continue
                    sid = row[sid_i]
                    for stage, colname in col_map.items():
                        data[stage][sid] = int(float(row[col[colname]]))
            return data, present

        if csv_matches:
            if len(csv_matches) > 1:
                raise LookupError(f"ambiguous data/stats.csv members in {path}: {csv_matches}")
            with zf.open(csv_matches[0]) as fh:
                text = io.TextIOWrapper(fh, encoding="utf-8", newline="")
                reader = csv.DictReader(text)
                fieldnames = reader.fieldnames or []
                sid_field = "sample-id" if "sample-id" in fieldnames else fieldnames[0]
                data = {"denoised": {}, "non_chimeric": {}}
                for row in reader:
                    sid = row[sid_field]
                    data["denoised"][sid] = int(float(row["reads-deblur"]))
                    data["non_chimeric"][sid] = int(float(row["reads-hit-reference"]))
            return data, {"denoised", "non_chimeric"}

        raise LookupError(f"no data/stats.tsv or data/stats.csv member found in {path}")


def read_sample_frequency_detail(path: Path) -> Dict[str, int]:
    """Mapped/*-table_viz.qzv or QiimeData/table_viz.qzv -> {sample-id: frequency}.

    data/sample-frequency-detail.csv has no real header (first line is ',0');
    skip it and read the rest as (sample-id, frequency).
    """
    with zipfile.ZipFile(path) as zf:
        member = find_member(zf, "data/sample-frequency-detail.csv")
        with zf.open(member) as fh:
            lines = fh.read().decode("utf-8").splitlines()
    counts = {}
    for line in lines[1:]:
        if not line.strip():
            continue
        sid, freq = line.split(",", 1)
        counts[sid] = int(round(float(freq)))
    return counts


def cross_check_table(table_counts: Dict[str, int], non_chimeric: Dict[str, int], study: str) -> None:
    problems = []
    for sid, val in table_counts.items():
        if sid not in non_chimeric:
            problems.append(f"  {sid}: in table_viz (freq={val}) but absent from stats.qza non-chimeric")
        elif non_chimeric[sid] != val:
            problems.append(f"  {sid}: table_viz={val} vs stats.qza non-chimeric={non_chimeric[sid]}")
    total_table = sum(table_counts.values())
    total_stats = sum(non_chimeric.values())
    if total_table != total_stats:
        problems.append(f"  TOTAL: table_viz sum={total_table} vs stats.qza non-chimeric sum={total_stats}")
    if problems:
        msg = "\n".join(problems)
        raise RuntimeError(
            f"[{study}] table_viz.qzv disagrees with stats.qza non-chimeric column:\n{msg}"
        )


def build_rows(study: str, stage_sources: Dict[str, Tuple[Dict[str, int], bool]]):
    all_samples = sorted({sid for counts, _ in stage_sources.values() for sid in counts})

    raw_rows, final_rows = [], []
    stage_level_absent = [s for s in PIPELINE if stage_sources[s][1]]
    sample_level_zero = {s: 0 for s in PIPELINE}
    raw_value_n = {s: 0 for s in PIPELINE}
    final_total = {s: 0 for s in PIPELINE}

    for sid in all_samples:
        raw_row = {"sample-id": sid, "study": study}
        final_row = {"sample-id": sid, "study": study}
        imputed = []
        prev_value = None
        zero_hit = False
        for stage in PIPELINE:
            counts, absent = stage_sources[stage]
            raw_val = counts.get(sid)
            raw_row[stage] = "" if raw_val is None else raw_val

            if absent:
                value = prev_value
                imputed.append(stage)
            elif zero_hit:
                value = 0
            elif raw_val is None:
                value = 0
                zero_hit = True
                sample_level_zero[stage] += 1
            else:
                value = raw_val
                raw_value_n[stage] += 1
                if value == 0:
                    zero_hit = True

            prev_value = value
            final_row[stage] = value
            final_total[stage] += value

        final_row["stages_imputed"] = ";".join(imputed)
        raw_rows.append(raw_row)
        final_rows.append(final_row)

    stats = {
        "n_samples": len(all_samples),
        "stage_level_absent": stage_level_absent,
        "sample_level_zero": sample_level_zero,
        "raw_value_n": raw_value_n,
        "final_total": final_total,
    }
    return raw_rows, final_rows, stats


def write_tsv(path: Path, rows: List[dict], fieldnames: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


def print_summary(study: str, stats: dict) -> None:
    absent = ", ".join(stats["stage_level_absent"]) or "none"
    print(f"[{study}] stage-level absent columns: {absent}")
    for stage in PIPELINE:
        n0 = stats["sample_level_zero"][stage]
        if n0:
            print(f"[{study}] sample-level zeros at {stage}: {n0}")
    n_samples = stats["n_samples"]
    for stage in PIPELINE:
        total = stats["final_total"][stage]
        n_with_value = stats["raw_value_n"][stage]
        print(f"[{study}] {stage:12s} n_samples={n_samples:5d}  total_reads={total:12d}  n_with_source_value={n_with_value:5d}")


def run(study: str, repo_root: Path, work_base: Path, out_dir: Path) -> None:
    def resolve(relpath: str) -> Optional[Path]:
        return find_source(repo_root, work_base, study, relpath)

    demux_path = resolve("QiimeData/demux_viz.qzv")
    if demux_path is None:
        raise RuntimeError(
            f"[{study}] QiimeData/demux_viz.qzv not found in {repo_root / study} or "
            f"{work_base / study} — 'input' is the first pipeline stage, so there is "
            f"nothing to carry forward from. Aborting rather than guessing."
        )
    input_counts = read_fastq_counts(demux_path)

    trimmed_path = resolve("QiimeData/demux_trimmed_viz.qzv")
    trimmed_absent = trimmed_path is None
    trimmed_counts = read_fastq_counts(trimmed_path) if trimmed_path else {}

    stats_path = resolve("QiimeData/stats.qza")
    if stats_path is None:
        raise RuntimeError(f"[{study}] QiimeData/stats.qza not found in {repo_root / study} or {work_base / study}")
    stats_data, stats_present = read_stats(stats_path)
    filtered_counts = stats_data.get("filtered", {})
    denoised_counts = stats_data.get("denoised", {})
    merged_counts = stats_data.get("merged", {})
    nonchim_counts = stats_data.get("non_chimeric", {})

    qc_path = resolve("Mapped/qc-table_viz.qzv")
    qc_absent = qc_path is None
    qc_counts = read_sample_frequency_detail(qc_path) if qc_path else {}

    mapped_path = resolve("Mapped/mapped-table_viz.qzv")
    mapped_absent = mapped_path is None
    mapped_counts = read_sample_frequency_detail(mapped_path) if mapped_path else {}

    table_path = resolve("QiimeData/table_viz.qzv")
    if table_path is None:
        raise RuntimeError(f"[{study}] QiimeData/table_viz.qzv not found — needed for the non-chimeric cross-check")
    table_counts = read_sample_frequency_detail(table_path)
    cross_check_table(table_counts, nonchim_counts, study)

    stage_sources = {
        "input": (input_counts, False),
        "trimmed": (trimmed_counts, trimmed_absent),
        "filtered": (filtered_counts, "filtered" not in stats_present),
        "denoised": (denoised_counts, "denoised" not in stats_present),
        "merged": (merged_counts, "merged" not in stats_present),
        "non_chimeric": (nonchim_counts, "non_chimeric" not in stats_present),
        "qc": (qc_counts, qc_absent),
        "mapped": (mapped_counts, mapped_absent),
    }

    raw_rows, final_rows, stats = build_rows(study, stage_sources)

    fieldnames_final = ["sample-id", "study"] + PIPELINE + ["stages_imputed"]
    fieldnames_raw = ["sample-id", "study"] + PIPELINE

    out_final = out_dir / f"{study}_read_counts.tsv"
    out_raw = out_dir / f"{study}_read_counts_raw.tsv"
    write_tsv(out_final, final_rows, fieldnames_final)
    write_tsv(out_raw, raw_rows, fieldnames_raw)

    print_summary(study, stats)
    print(f"[{study}] wrote {out_final}")
    print(f"[{study}] wrote {out_raw}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("study", help="Study directory name, e.g. Fujimoto2024")
    ap.add_argument("--repo-root", help="Default: git rev-parse --show-toplevel")
    ap.add_argument("--work-base", help="Default: $WORK_BASE ($SCRATCH_BASE/ODSiData if unset)")
    ap.add_argument("--out-dir", default="Merging/ReadCounts",
                     help="Default: Merging/ReadCounts (resolved under --repo-root if relative)")
    args = ap.parse_args()

    repo_root = Path(args.repo_root).resolve() if args.repo_root else default_repo_root()
    work_base = Path(args.work_base).resolve() if args.work_base else default_work_base()
    out_dir = Path(args.out_dir)
    if not out_dir.is_absolute():
        out_dir = repo_root / out_dir

    try:
        run(args.study, repo_root, work_base, out_dir)
    except (RuntimeError, LookupError, FileNotFoundError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
