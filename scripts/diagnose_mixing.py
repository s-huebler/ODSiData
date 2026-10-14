"""
Diagnose: for each fp_len=40 fingerprint group, count distinct 120-bp R2 amplicon prefixes.
"""
import sys
sys.path.insert(0, '/uufs/chpc.utah.edu/common/home/u1477302/Documents/ODSiData/scripts')
from repairseq import read_fastq, find_primer, canonical
from collections import defaultdict, Counter

PRIMER_R = 'GGACTACHVGGGTWTCTAAT'
MM=2; PS=60; FPL=40; PREFIX_LEN=120

r2_recs = read_fastq('/scratch/general/vast/u1477302/ODSiData/Liu2017/RawData/SAMEA4506927_2.fastq')
print(f"Total R2: {len(r2_recs):,}", flush=True)

r2_by_fp = defaultdict(list)
n_no_primer = 0
for rec in r2_recs:
    p = find_primer(rec[1], PRIMER_R, MM, PS)
    if p is None:
        n_no_primer += 1; continue
    amp = rec[1][p:]
    if len(amp) < FPL:
        n_no_primer += 1; continue
    fp = canonical(amp[:FPL])
    prefix = canonical(amp[:PREFIX_LEN]) if len(amp) >= PREFIX_LEN else canonical(amp)
    r2_by_fp[fp].append(prefix)

print(f"No-primer: {n_no_primer:,}  |  Unique fingerprints: {len(r2_by_fp):,}", flush=True)

n_reads_per_group = []
n_distinct_per_group = []
for fp, prefixes in r2_by_fp.items():
    n_reads_per_group.append(len(prefixes))
    n_distinct_per_group.append(len(set(prefixes)))

mixed = [(nr, nd) for nr, nd in zip(n_reads_per_group, n_distinct_per_group) if nd > 1]
pure  = [(nr, nd) for nr, nd in zip(n_reads_per_group, n_distinct_per_group) if nd == 1]

print(f"\nGroups with 1 distinct amplicon (pure):  {len(pure):,}  ({sum(r for r,d in pure):,} reads)")
print(f"Groups with >1 distinct amplicon (mixed): {len(mixed):,}  ({sum(r for r,d in mixed):,} reads)")

mixed_sizes = sorted([r for r,d in mixed], reverse=True)
if mixed_sizes:
    print(f"Mixed group sizes (top 10): {mixed_sizes[:10]}")
    print(f"Mixed group distinct prefixes (top 10): {sorted([d for r,d in mixed], reverse=True)[:10]}")

reads_in_mixed = sum(r for r,d in mixed)
print(f"\nReads in mixed groups: {reads_in_mixed:,} / {len(r2_recs):,} = {reads_in_mixed/len(r2_recs):.1%}")

size_counter = Counter(n_reads_per_group)
print("\nGroup size distribution (by read count in group):")
for sz in sorted(size_counter)[:25]:
    print(f"  size {sz:4d}: {size_counter[sz]:5,} groups")
