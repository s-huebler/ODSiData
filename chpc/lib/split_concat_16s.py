#!/usr/bin/env python3
"""
split_concat_16s.py — recover paired R1/R2 from concatenated SRA reads.

Some SRA records (e.g. D'Amico 2019) were deposited with the paired-end mates
already joined into a SINGLE read per spot:

    concatenated_read = forward_R1 (fixed length) + reverse_complement(raw_R2)

Because the join happens *inside the archive*, `fasterq-dump --split-files`
returns one file (SRA sees 1 read/spot) and cannot separate the mates. This
script reconstructs proper raw R1 and R2 FASTQs that import cleanly into QIIME2
as paired-end and denoise with DADA2:

    R1 = first <r1_len> bases, kept as-is (still carries the 341F forward primer)
    R2 = reverse-complement of the remaining bases, with the quality string
         reversed to match — restoring the raw reverse read, which begins at the
         805R reverse primer (GACTAC...GGGTATCTAATCC)

Output is plain (uncompressed) .fastq named <sample>_1.fastq / <sample>_2.fastq
so it matches chpc/lib/make_manifest_paired.sh (which globs *_1.fastq) and the
fasterq-dump outputs the rest of the pipeline expects.

Usage:
    python3 split_concat_16s.py INPUT.fastq[.gz] OUTDIR [--r1-len 250] [--min-r2 20] [--gzip]

Exit status is non-zero if no pairs were written.
"""
import argparse, gzip, os, sys

COMP = str.maketrans("ACGTNacgtn", "TGCANtgcan")

def rc(s: str) -> str:
    return s.translate(COMP)[::-1]

def opener_in(path):
    return gzip.open(path, "rt") if path.endswith(".gz") else open(path, "rt")

def opener_out(path, use_gzip):
    return gzip.open(path, "wt") if use_gzip else open(path, "wt")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input")
    ap.add_argument("outdir")
    ap.add_argument("--r1-len", type=int, default=250,
                    help="fixed forward-read length / split point (default 250). "
                         "Confirm against the demux quality plot per study.")
    ap.add_argument("--min-r2", type=int, default=20,
                    help="drop the pair if the reverse read is shorter than this, "
                         "keeping R1/R2 in sync (default 20; 0 keeps all).")
    ap.add_argument("--gzip", action="store_true",
                    help="write .fastq.gz instead of plain .fastq")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    stem = os.path.basename(args.input)
    for ext in (".gz", ".fastq", ".fq"):
        if stem.endswith(ext):
            stem = stem[: -len(ext)]
    suffix = ".fastq.gz" if args.gzip else ".fastq"
    r1_path = os.path.join(args.outdir, f"{stem}_1{suffix}")
    r2_path = os.path.join(args.outdir, f"{stem}_2{suffix}")

    n_in = n_out = n_dropped = 0
    r2_lens = []
    L = args.r1_len
    with opener_in(args.input) as fin, \
         opener_out(r1_path, args.gzip) as o1, opener_out(r2_path, args.gzip) as o2:
        while True:
            h = fin.readline()
            if not h:
                break
            seq = fin.readline().rstrip("\n")
            fin.readline()                       # '+' separator
            qual = fin.readline().rstrip("\n")
            n_in += 1

            rid = h[1:].split()[0]               # read id token; drop '@' and length=
            f_seq, f_qual = seq[:L], qual[:L]
            r_seq  = rc(seq[L:])
            r_qual = qual[L:][::-1]

            if len(f_seq) < L or len(r_seq) < args.min_r2:
                n_dropped += 1
                continue

            o1.write(f"@{rid} 1:N:0:1\n{f_seq}\n+\n{f_qual}\n")
            o2.write(f"@{rid} 2:N:0:1\n{r_seq}\n+\n{r_qual}\n")
            r2_lens.append(len(r_seq))
            n_out += 1

    r2_lens.sort()
    def q(p):
        return r2_lens[min(len(r2_lens) - 1, int(p * len(r2_lens)))] if r2_lens else 0
    sys.stderr.write(
        f"[{stem}] reads in={n_in}  pairs out={n_out}  dropped(short R2)={n_dropped}\n"
        f"          R2 length  min={r2_lens[0] if r2_lens else 0} "
        f"median={q(0.5)} max={r2_lens[-1] if r2_lens else 0}\n"
        f"          wrote {r1_path}\n          wrote {r2_path}\n")

    if n_out == 0:
        sys.stderr.write(f"ERROR: no pairs written from {args.input}\n")
        sys.exit(2)

if __name__ == "__main__":
    main()
