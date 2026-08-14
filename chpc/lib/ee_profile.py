#!/usr/bin/env python3
"""
chpc/lib/ee_profile.py — profile expected errors in a demux artifact BEFORE
committing to a DADA2 run.

DADA2's `--p-max-ee` filter is a whole-read expected-error ceiling:

    EE = sum over bases of 10^(-Q/10)

A read is DISCARDED at the `filtered` step if EE > max_ee. Crucially, EE
accumulates with read LENGTH, so the conventional max-ee=2.0 — a value calibrated
on ~250 nt Illumina reads — is far stricter when applied to a ~420 nt joined
amplicon. This script reports the actual EE distribution so max-ee can be chosen
from the data (and from read length) rather than by tuning until retention looks
acceptable.

It also counts ambiguous bases: QIIME 2's `dada2 denoise-single` does NOT expose
maxN, and DADA2 hard-discards ANY read containing an N. Mergers such as PANDASeq
can emit N at unresolved overlap positions, which silently destroys reads at the
`filtered` step for a reason unrelated to quality.

Reads .fastq.gz members straight out of the .qza (it is a zip) — no export, no
scratch copy. Safe to run on a login node.

Usage:
    python3 chpc/lib/ee_profile.py <demux.qza> [--max-files N] [--max-reads N]

Example:
    python3 chpc/lib/ee_profile.py \
        /scratch/general/vast/$USER/ODSiData/DAmico2019/QiimeData/demux_trimmed.qza
"""
import argparse
import gzip
import io
import sys
import zipfile


def quantile(sorted_vals, p):
    if not sorted_vals:
        return float("nan")
    return sorted_vals[min(len(sorted_vals) - 1, int(p * len(sorted_vals)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("qza")
    ap.add_argument("--max-files", type=int, default=20,
                    help="sample this many fastq.gz members (default 20)")
    ap.add_argument("--max-reads", type=int, default=40000,
                    help="stop after this many reads total (default 40000)")
    ap.add_argument("--phred-offset", type=int, default=33)
    args = ap.parse_args()

    # EE contribution per Phred score, precomputed.
    ee_of = {chr(q + args.phred_offset): 10 ** (-q / 10.0) for q in range(0, 94)}

    zf = zipfile.ZipFile(args.qza)
    members = sorted(n for n in zf.namelist() if n.endswith(".fastq.gz"))
    if not members:
        sys.exit("no .fastq.gz members found — is this a demux artifact?")

    # Spread the sample ACROSS runs rather than taking the first few
    # alphabetically, so the profile is not dominated by one sample.
    if len(members) > args.max_files:
        step = len(members) / args.max_files
        members = [members[int(i * step)] for i in range(args.max_files)]

    per_read = args.max_reads // len(members)
    ees, lens = [], []
    n_with_N = 0

    for m in members:
        taken = 0
        with gzip.open(io.BytesIO(zf.read(m)), "rt") as fh:
            seq = None
            for i, line in enumerate(fh):
                if i % 4 == 1:
                    seq = line.strip()
                elif i % 4 == 3:
                    q = line.strip()
                    lens.append(len(q))
                    ees.append(sum(ee_of.get(c, 1.0) for c in q))
                    if seq and "N" in seq:
                        n_with_N += 1
                    taken += 1
                    if taken >= per_read:
                        break

    n = len(ees)
    if not n:
        sys.exit("no reads read")
    ees.sort()
    lens.sort()
    med_len = quantile(lens, 0.50)

    print(f"artifact : {args.qza}")
    print(f"sampled  : {n} reads across {len(members)} of "
          f"{len([x for x in zf.namelist() if x.endswith('.fastq.gz')])} run(s)")
    print()
    print("length   : " + "  ".join(
        f"{int(p*100)}%={quantile(lens, p)}" for p in (.02, .25, .50, .75, .98)))
    print("EE       : " + "  ".join(
        f"{int(p*100)}%={quantile(ees, p):.2f}" for p in (.02, .25, .50, .75, .98)))
    print(f"mean EE  : {sum(ees)/n:.2f}")
    print()

    if n_with_N:
        print(f"*** {n_with_N}/{n} reads ({100*n_with_N/n:.2f}%) contain an N. ***")
        print("    DADA2 discards every one of these regardless of max-ee, and")
        print("    QIIME 2's denoise-single does not expose maxN to relax it.")
    else:
        print(f"ambiguous bases: 0/{n} reads contain an N — good, none lost to maxN.")
    print()

    print("retention at the `filtered` step by --p-max-ee:")
    print(f"  {'max-ee':>7}  {'% reads kept':>12}   equivalent on a 250 nt read")
    for thr in (1.0, 2.0, 3.0, 4.0, 5.0, 7.0, 10.0):
        kept = sum(1 for e in ees if e <= thr)
        scaled = thr * 250.0 / med_len if med_len else float("nan")
        print(f"  {thr:>7.1f}  {100*kept/n:>11.2f}%   max-ee {scaled:.2f}")
    print()
    print(f"Read length here is ~{med_len} nt. The community-standard max-ee=2.0 is")
    print(f"calibrated on 250 nt reads; the length-equivalent ceiling here is")
    print(f"max-ee {2.0*med_len/250.0:.1f}. A paired-end workflow allowing max-ee 2.0 on")
    print(f"EACH mate effectively permits ~4.0 across the merged product.")
    print()
    print("Choose max-ee from read length and this table BEFORE running DADA2 —")
    print("deciding in advance is defensible; tuning until retention looks good is not.")


if __name__ == "__main__":
    main()
