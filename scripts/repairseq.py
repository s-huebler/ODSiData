#!/usr/bin/env python3
"""
repairseq.py  –  sequence-based R1/R2 re-pairing for Liu2017 scrambled samples.

Usage:
    python3 repairseq.py <r1.fastq> <r2.fastq> <out_prefix>
                         [--primer_f GTGCCAGCMGCCGCGGTAA]
                         [--primer_r GGACTACHVGGGTWTCTAAT]
                         [--max_mm 2] [--kmer_size 40]
                         [--vote_threshold 25]
                         [--fp_len 80]          # 40|80|120 – key parameter
                         [--secondary_window 96]

Strategy (variable-amplicon-length aware)
-----------------------------------------
STAGE 1 – PRIMARY fingerprint assignment (same for all fp_len values):
  R2 fingerprint = R2.amp[0:fp_len]   (first N bp of R2 amplicon; high quality)
  R2 k-mer index = k-mers from R2.amp[0:fp_len+kmer_size], mapped → fingerprint set
  R1 query       = RC(R1.amp[-r1_query_tail:-16])  (80 bp near 806R end of R1)
  R1 votes against global index → assigned to best-scoring fingerprint group

  Longer fp_len (80 or 120) produces more specific groups (fewer mixed-ASV buckets).
  The 80-bp R1 query covers R2 positions ~16..96, which overlaps with R2.amp[16:fp_len]
  for fp_len ≥ 40, providing discriminative k-mers even for longer fingerprints.

STAGE 2 – WITHIN-GROUP best-overlap pairing (replaces blind 1:1 zip):
  For each fingerprint group with both R1 and R2 reads:
    • Build a per-group secondary k-mer index from R2.amp[0:secondary_window]
    • For each R1, vote against the secondary index using the same R1 query window
      → yields a (best_r2_idx, vote_count) per R1 (vote count proxies identity)
    • Greedy 1:1 assignment by descending vote count (highest-identity R2 first)
    • Unmatched R1 / R2 in any group → orphans

  This handles residual within-group mixing after the primary assignment.

Outputs:
    <prefix>_1.repaired.fastq
    <prefix>_2.repaired.fastq
    <prefix>_orphans.repaired.fastq
"""

import sys, argparse
from collections import defaultdict, Counter

_IUPAC = {
    'A':'A','C':'C','G':'G','T':'T',
    'R':'AG','Y':'CT','S':'GC','W':'AT','K':'GT','M':'AC',
    'B':'CGT','D':'AGT','H':'ACT','V':'ACG','N':'ACGT',
}

def find_primer(seq, primer, max_mm, search_len, start=0):
    L = len(primer); pu = primer.upper()
    lim = min(start + search_len, len(seq) - L + 1)
    for i in range(start, lim):
        mm = 0
        for j in range(L):
            if seq[i+j].upper() not in _IUPAC.get(pu[j], pu[j]):
                mm += 1
                if mm > max_mm: break
        if mm <= max_mm:
            return i + L
    return None

def revcomp(s):
    t = str.maketrans('ACGTacgt', 'TGCAtgca')
    return s.translate(t)[::-1]

def canonical(s):
    return s.upper().replace('N', 'A')

def read_fastq(path):
    recs = []
    with open(path) as fh:
        while True:
            h = fh.readline()
            if not h: break
            recs.append((h.strip(), fh.readline().strip(),
                         fh.readline().strip(), fh.readline().strip()))
    return recs

def write_fastq(path, recs):
    with open(path, 'w') as fh:
        for h, s, p, q in recs:
            fh.write(f"{h}\n{s}\n{p}\n{q}\n")

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('r1'); p.add_argument('r2'); p.add_argument('prefix')
    p.add_argument('--primer_f',          default='GTGCCAGCMGCCGCGGTAA')
    p.add_argument('--primer_r',          default='GGACTACHVGGGTWTCTAAT')
    p.add_argument('--max_mm',            type=int, default=2)
    p.add_argument('--primer_search',     type=int, default=60)
    p.add_argument('--kmer_size',         type=int, default=40,
                   help='k-mer size for fingerprint voting')
    p.add_argument('--vote_threshold',    type=int, default=25,
                   help='Min k-mer votes for primary fingerprint assignment')
    p.add_argument('--fp_len',            type=int, default=40,
                   help='Fingerprint length: first N bp of R2 amplicon (try 40/80/120)')
    p.add_argument('--r1_query_tail',     type=int, default=96,
                   help='R1 query = RC(R1.amp[-tail:-16]); default 96 → 80 bp query')
    p.add_argument('--secondary_window',  type=int, default=96,
                   help='(unused placeholder; secondary index offset is now derived from fp_len)')
    p.add_argument('--max_group',         type=int, default=5000,
                   help='Groups larger than this use blind 1:1 zip and log a warning')
    p.add_argument('--purity_prefix_len', type=int, default=100,
                   help='Exact prefix length for purity deduplication of R2 amplicons')
    return p.parse_args()


# ── Stage-2: within-group best-overlap pairing ────────────────────────────────

def pair_group(r1_data, r2_data, K, FPL):
    """
    Pair R1 and R2 within one fingerprint group using secondary k-mer voting.

    r1_data : list of (rec, query)  where query = RC(R1.amp[-tail:-16]) ~80 bp
    r2_data : list of (rec, amp)    where amp   = R2 amplicon after primer trim
    K       : k-mer size (same as primary)
    FPL     : fingerprint length; secondary index starts here (discriminative zone)

    Secondary k-mer index uses R2.amp[FPL : FPL+64], which is:
      • Fully discriminative (beyond the shared fingerprint region)
      • Covered by R1.query at roughly position (FPL-16) onward
    If the discriminative window is too short for K-mers (len < K), falls back to
    blind 1:1 zip in arrival order (groups should be pure at large FPL anyway).

    Returns (paired_r1_recs, paired_r2_recs, orphan_r1_recs, orphan_r2_recs)
    """
    if not r1_data or not r2_data:
        return [], [], [d[0] for d in r1_data], [d[0] for d in r2_data]

    # Fast path: trivial 1-vs-1
    if len(r1_data) == 1 and len(r2_data) == 1:
        return [r1_data[0][0]], [r2_data[0][0]], [], []

    # Discriminative zone in R2: starts right after the shared fingerprint.
    # R1.query[i] ≈ R2.amp[16+i] (at n=253), so the slice of R1.query that
    # aligns with R2.amp[FPL:] starts at index max(0, FPL-16).
    DISC_R2_START = FPL
    DISC_R2_END   = FPL + 64      # 64 bp window beyond the fingerprint
    DISC_Q_START  = max(0, FPL - 16)   # corresponding R1.query offset

    # Check if we have enough discriminative bp to build k-mers
    disc_len = DISC_R2_END - DISC_R2_START   # = 64 bp always
    q_disc_len = max(0, 80 - DISC_Q_START)   # remaining R1 query bp

    if disc_len < K or q_disc_len < K:
        # FPL so large that R1 query doesn't extend past fingerprint →
        # groups are expected to be pure; use blind 1:1 zip.
        n = min(len(r1_data), len(r2_data))
        return ([d[0] for d in r1_data[:n]],
                [d[0] for d in r2_data[:n]],
                [d[0] for d in r1_data[n:]],
                [d[0] for d in r2_data[n:]])

    # Build per-group R2 secondary k-mer index (discriminative zone only)
    r2_kmi = defaultdict(set)
    for j, (_rec, amp) in enumerate(r2_data):
        target = canonical(amp[DISC_R2_START:min(DISC_R2_END, len(amp))])
        for pos in range(max(0, len(target) - K + 1)):
            r2_kmi[target[pos:pos+K]].add(j)

    # Vote: each R1 queries secondary index with the discriminative slice
    candidates = []   # (vote_count, r1_i, r2_j)
    for i, (_rec, query) in enumerate(r1_data):
        if not query:
            continue
        q_slice = query[DISC_Q_START:]
        if len(q_slice) < K:
            continue
        votes = Counter()
        for pos in range(len(q_slice) - K + 1):
            for j in r2_kmi.get(q_slice[pos:pos+K], ()):
                votes[j] += 1
        if votes:
            best_j, best_v = votes.most_common(1)[0]
            candidates.append((best_v, i, best_j))

    # Greedy 1:1 assignment by descending vote count (proxy for sequence identity)
    candidates.sort(reverse=True)
    used_r1 = set(); used_r2 = set()
    paired_r1, paired_r2 = [], []
    for _v, i, j in candidates:
        if i not in used_r1 and j not in used_r2:
            paired_r1.append(r1_data[i][0])
            paired_r2.append(r2_data[j][0])
            used_r1.add(i); used_r2.add(j)

    orphan_r1 = [r1_data[i][0] for i in range(len(r1_data)) if i not in used_r1]
    orphan_r2 = [r2_data[j][0] for j in range(len(r2_data)) if j not in used_r2]
    return paired_r1, paired_r2, orphan_r1, orphan_r2


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()
    MM = args.max_mm; PS = args.primer_search
    K = args.kmer_size; VT = args.vote_threshold
    FPL = args.fp_len; TAIL = args.r1_query_tail
    MAX_GROUP = args.max_group; PPL = args.purity_prefix_len
    WINDOW = FPL + K    # R2 amplicon window indexed for primary k-mer index

    print(f"[repairseq] R1={args.r1}", flush=True)
    print(f"[repairseq] R2={args.r2}", flush=True)
    print(f"[repairseq] k={K}  vote_thresh={VT}  fp_len={FPL}  "
          f"r1_query=RC(amp[-{TAIL}:-16])  max_group={MAX_GROUP}", flush=True)

    print("[repairseq] Reading R1 ...", flush=True)
    r1_recs = read_fastq(args.r1)
    print("[repairseq] Reading R2 ...", flush=True)
    r2_recs = read_fastq(args.r2)
    print(f"[repairseq] {len(r1_recs):,} R1  |  {len(r2_recs):,} R2", flush=True)

    # ── STAGE 1a: Build R2 fingerprint groups + primary k-mer index ──────────
    print("[repairseq] Building R2 fingerprint index ...", flush=True)
    r2_by_fp  = defaultdict(list)   # fp → [(rec, amp)]
    kmi_fp    = defaultdict(set)    # kmer → set of fingerprints
    r2_no_key = []

    for rec in r2_recs:
        p = find_primer(rec[1], args.primer_r, MM, PS)
        if p is None:
            r2_no_key.append(rec); continue
        amp = rec[1][p:]
        if len(amp) < FPL:
            r2_no_key.append(rec); continue
        fp = canonical(amp[:FPL])
        r2_by_fp[fp].append((rec, amp))             # store amp for stage-2
        window = amp[:min(WINDOW, len(amp))]
        for j in range(len(window) - K + 1):
            kmi_fp[window[j:j+K].upper()].add(fp)

    r2_keyed = sum(len(v) for v in r2_by_fp.values())
    print(f"[repairseq] R2: {r2_keyed:,} keyed ({len(r2_no_key):,} no-primer) | "
          f"{len(r2_by_fp):,} unique fingerprints | {len(kmi_fp):,} k-mers", flush=True)

    # ── Group purity: distinct 100-bp R2 amplicon prefixes per group ──────────
    print(f"[repairseq] Computing group purity (distinct {PPL}-bp prefix per group) ...",
          flush=True)
    purity_stats = []   # (group_size, n_distinct)
    for fp, data in r2_by_fp.items():
        distinct = len(set(canonical(amp[:PPL]) if len(amp) >= PPL else canonical(amp)
                          for _, amp in data))
        purity_stats.append((len(data), distinct))

    n_mixed   = sum(1 for sz, nd in purity_stats if nd > 1)
    rd_mixed  = sum(sz for sz, nd in purity_stats if nd > 1)
    mean_dist = sum(nd for _, nd in purity_stats) / len(purity_stats) if purity_stats else 0
    top5      = sorted(purity_stats, key=lambda x: x[0], reverse=True)[:5]
    print(f"[repairseq] Purity: {n_mixed:,} mixed groups ({rd_mixed:,} reads = "
          f"{rd_mixed/max(1,r2_keyed):.1%} of keyed R2)", flush=True)
    print(f"[repairseq] Purity: mean distinct/group={mean_dist:.2f} | "
          f"top-5 groups (size, distinct): {top5}", flush=True)

    # ── STAGE 1b: Vote each R1 → best primary fingerprint ────────────────────
    print("[repairseq] Voting R1 → fingerprint ...", flush=True)
    r1_by_fp   = defaultdict(list)  # fp → [(rec, query)]
    r1_no_vote = []

    for rec in r1_recs:
        p = find_primer(rec[1], args.primer_f, MM, PS)
        if p is None:
            r1_no_vote.append(rec); continue
        amp = rec[1][p:]
        q_start = max(0, len(amp) - TAIL)
        q_end   = max(0, len(amp) - 16)
        query   = revcomp(amp[q_start:q_end]).upper()

        if len(query) < K:
            r1_no_vote.append(rec); continue

        votes = Counter()
        for j in range(len(query) - K + 1):
            fps = kmi_fp.get(query[j:j+K])
            if fps:
                votes.update(fps)

        if not votes:
            r1_no_vote.append(rec); continue

        best_fp, best_v = votes.most_common(1)[0]
        if best_v < VT:
            r1_no_vote.append(rec); continue

        r1_by_fp[best_fp].append((rec, query))      # store query for stage-2

    r1_keyed = sum(len(v) for v in r1_by_fp.values())
    print(f"[repairseq] R1: {r1_keyed:,} assigned ({len(r1_no_vote):,} no-vote) | "
          f"{len(r1_by_fp):,} fingerprint groups used", flush=True)

    # ── STAGE 2: Within-group best-overlap pairing ────────────────────────────
    print("[repairseq] Pairing within groups (secondary k-mer vote + greedy) ...",
          flush=True)
    paired_r1, paired_r2, orphan = [], [], []
    common_fps = set(r1_by_fp) & set(r2_by_fp)
    print(f"[repairseq] Common fingerprint groups: {len(common_fps):,}", flush=True)

    n_large_groups = 0
    for fp in common_fps:
        g1 = r1_by_fp[fp]; g2 = r2_by_fp[fp]
        if max(len(g1), len(g2)) > MAX_GROUP:
            # Size cap: blind 1:1 zip to avoid O(n²) stall; log the group
            n = min(len(g1), len(g2))
            paired_r1.extend(d[0] for d in g1[:n])
            paired_r2.extend(d[0] for d in g2[:n])
            orphan.extend(d[0] for d in g1[n:])
            orphan.extend(d[0] for d in g2[n:])
            n_large_groups += 1
            continue
        pr1, pr2, or1, or2 = pair_group(g1, g2, K, FPL)
        paired_r1.extend(pr1); paired_r2.extend(pr2)
        orphan.extend(or1);    orphan.extend(or2)
    if n_large_groups:
        print(f"[repairseq] WARNING: {n_large_groups} groups exceeded max_group={MAX_GROUP} "
              f"and used blind 1:1 zip", flush=True)

    # Groups present in only R1 or only R2 → orphans
    for fp, data in r1_by_fp.items():
        if fp not in r2_by_fp:
            orphan.extend(d[0] for d in data)
    for fp, data in r2_by_fp.items():
        if fp not in r1_by_fp:
            orphan.extend(d[0] for d in data)

    orphan.extend(r1_no_vote)
    orphan.extend(r2_no_key)

    # ── Write output ──────────────────────────────────────────────────────────
    out1   = f"{args.prefix}_1.repaired.fastq"
    out2   = f"{args.prefix}_2.repaired.fastq"
    out_or = f"{args.prefix}_orphans.repaired.fastq"

    print("[repairseq] Writing ...", flush=True)
    write_fastq(out1, paired_r1)
    write_fastq(out2, paired_r2)
    write_fastq(out_or, orphan)

    total = len(r1_recs)
    frac  = len(paired_r1) / total if total else 0
    print()
    print("=" * 56)
    print(f"  Input R1 reads       : {total:>10,}")
    print(f"  Input R2 reads       : {len(r2_recs):>10,}")
    print(f"  Re-paired pairs      : {len(paired_r1):>10,}  ({frac:.1%} of R1)")
    print(f"  Orphan records       : {len(orphan):>10,}")
    print(f"  -> {out1}")
    print(f"  -> {out2}")
    print(f"  -> {out_or}")
    print("=" * 56)


if __name__ == '__main__':
    main()
