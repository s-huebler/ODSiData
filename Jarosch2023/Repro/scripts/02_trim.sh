#!/usr/bin/env bash
# Step 2 — quality trimming (Trimmomatic) then primer removal (cutadapt).
#
# Run INSIDE the container:
#   ./docker/run.sh bash scripts/02_trim.sh
#
# Reads are single-end Ion Torrent (V1-V3, ~500 bp amplicon, 600 bp protocol),
# already demultiplexed by ENA — so the "demultiplexed using cutadapt" clause in
# the methods reduces to primer stripping here.
#
# Inputs:  data/raw/*.fastq.gz
# Outputs: data/trimmed/*.fastq.gz    (post-Trimmomatic)
#          data/cutadapt/*.fastq.gz   (post-primer-removal, input to DADA2)
#          logs/02_trim.log, results/02_cutadapt_summary.tsv
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="${HERE}/data/raw"
TRIM="${HERE}/data/trimmed"
CUT="${HERE}/data/cutadapt"
mkdir -p "${TRIM}" "${CUT}" "${HERE}/logs" "${HERE}/results"

exec > >(tee "${HERE}/logs/02_trim.log") 2>&1

# ---------------------------------------------------------------------------
# PRIMERS (Klindworth-style names given in the paper)
#   S-D-Bact-0008-c-S-20  = 27F   forward, 20 nt
#   S-D-Bact-0517-a-A-18  = 519R  reverse, 18 nt
# Reads are forward-oriented, so we expect 27F at the 5' end and, for short
# amplicons that read through, the reverse complement of 519R at the 3' end.
# ---------------------------------------------------------------------------
FWD_PRIMER="AGRGTTYGATYMTGGCTCAG"
REV_PRIMER_RC="GCCAGCMGCCGCGGTAAT"

# ---------------------------------------------------------------------------
# TRIMMOMATIC PARAMETERS — INFERRED, NOT REPORTED.
# The paper states only "quality trimming with Trimmomatic (0.9)".
#
# The Illumina-conventional SLIDINGWINDOW:4:15 is WRONG for Ion Torrent, whose
# per-base quality is noisier. Measured on the raw reads (median length 449):
#
#   config                  kept    median len
#   SLIDINGWINDOW:4:15      66.3%      321      <- destroys the V1-V3 amplicon
#   SLIDINGWINDOW:4:20      43.8%      233
#   SLIDINGWINDOW:10:15     88.1%      445
#   SLIDINGWINDOW:20:15     98.7%      448      <- current setting
#   no sliding window      100.0%      449
#
# A 4-base window trips on isolated low-quality bases and truncates mid-
# amplicon. A 20-base window smooths over them and only cuts where quality
# genuinely collapses. MINLEN:200 discards fragments too short to be a real
# V1-V3 read; the expected-error filter (maxEE=5) in step 3 does the rest,
# which is how the authors describe their filtering.
# ---------------------------------------------------------------------------
TRIMMOMATIC_ARGS="${TRIMMOMATIC_ARGS:-LEADING:3 TRAILING:3 SLIDINGWINDOW:20:15 MINLEN:200}"

THREADS="${THREADS:-4}"

echo "=== Step 2: trim ==="
date
echo "Trimmomatic args : ${TRIMMOMATIC_ARGS}"
echo "Forward primer   : ${FWD_PRIMER}"
echo "Reverse primer RC: ${REV_PRIMER_RC}"
echo "Threads          : ${THREADS}"
echo

shopt -s nullglob
FILES=("${RAW}"/*.fastq.gz)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR: no fastq.gz in ${RAW}. Run scripts/01_download.sh first." >&2
  exit 1
fi
echo "Found ${#FILES[@]} input files."
echo

SUMMARY="${HERE}/results/02_cutadapt_summary.tsv"
printf "sample\traw_reads\ttrimmomatic_reads\tcutadapt_reads\tfwd_primer_found\trev_primer_found\traw_median_len\tfinal_median_len\n" > "${SUMMARY}"

# median read length of a fastq.gz
medlen() {
  zcat "$1" | awk 'NR%4==2{print length($0)}' | sort -n | \
    awk '{a[NR]=$1} END{if(NR==0){print 0}else{print a[int((NR+1)/2)]}}'
}

for f in "${FILES[@]}"; do
  s="$(basename "${f}" .fastq.gz)"
  echo "--- ${s} ---"

  raw_n=$(( $(zcat "${f}" | wc -l) / 4 ))

  # --- Trimmomatic (single-end) ---
  trimmomatic SE -threads "${THREADS}" -phred33 \
    "${f}" "${TRIM}/${s}.fastq.gz" \
    ${TRIMMOMATIC_ARGS}

  trim_n=$(( $(zcat "${TRIM}/${s}.fastq.gz" | wc -l) / 4 ))

  # --- cutadapt: strip 27F from 5', read-through 519R-rc from 3' ---
  # --discard-untrimmed is deliberately NOT set: Ion Torrent 5' ends are noisy
  # and dropping every read without a clean primer match would bias depth.
  #
  # -O 12 is essential. cutadapt's default minimum overlap is 3, so ANY 3-base
  # coincidental match triggers a trim -- and for a 5' (-g) adapter cutadapt
  # removes everything BEFORE the match, so a spurious internal hit decapitates
  # the read. With the default the median length collapsed from 335 to 201 bp.
  # Requiring 12 of the 18-20 primer bases makes false hits vanishingly rare
  # while still catching genuine read-through.
  ca_report="${HERE}/logs/cutadapt_${s}.txt"
  cutadapt \
    -g "${FWD_PRIMER}" \
    -a "${REV_PRIMER_RC}" \
    -e 0.15 -n 2 -O 12 \
    --minimum-length 200 \
    -j "${THREADS}" \
    -o "${CUT}/${s}.fastq.gz" \
    "${TRIM}/${s}.fastq.gz" > "${ca_report}"

  cut_n=$(( $(zcat "${CUT}/${s}.fastq.gz" | wc -l) / 4 ))
  # cutadapt's per-adapter block reads:
  #   Sequence: <seq>; Type: regular 5'; Length: 20; Trimmed: 9512 times
  # so pull the token immediately after "Trimmed:" under each adapter header.
  fwd_hit=$(awk '/=== Adapter 1 ===/{f=1} f && /Trimmed:/{for(i=1;i<=NF;i++) if($i=="Trimmed:"){gsub(/,/,"",$(i+1)); print $(i+1); exit}}' "${ca_report}")
  rev_hit=$(awk '/=== Adapter 2 ===/{f=1} f && /Trimmed:/{for(i=1;i<=NF;i++) if($i=="Trimmed:"){gsub(/,/,"",$(i+1)); print $(i+1); exit}}' "${ca_report}")

  raw_len=$(medlen "${f}")
  cut_len=$(medlen "${CUT}/${s}.fastq.gz")

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "${s}" "${raw_n}" "${trim_n}" "${cut_n}" \
    "${fwd_hit:-NA}" "${rev_hit:-NA}" "${raw_len}" "${cut_len}" >> "${SUMMARY}"
  echo "raw=${raw_n} trimmomatic=${trim_n} cutadapt=${cut_n} | median len ${raw_len} -> ${cut_len}"
  echo
done

echo "=== done ==="
echo "Per-sample read survival written to ${SUMMARY}"

# --------------------------------------------------------------------------
# QC GATE — the V1-V3 amplicon is ~490 bp. If trimming has chewed reads down
# to a few hundred bases the ASVs will be fragments, not amplicons, and every
# downstream diversity number is meaningless. Catch that here, loudly.
# --------------------------------------------------------------------------
echo
echo "=== length QC ==="
awk -F'\t' 'NR>1 {rk += $7; ck += $8; n++; if ($8 < 350) short++}
  END {
    printf "  mean median length: raw %.0f -> final %.0f  (retained %.0f%%)\n", rk/n, ck/n, 100*ck/rk;
    printf "  samples with final median < 350 bp: %d / %d\n", short+0, n;
    if (short+0 > 0 || ck/rk < 0.75) {
      print "";
      print "  *** WARNING: reads are being over-trimmed. ***";
      print "  Expected final median ~400-490 bp for a V1-V3 amplicon.";
      print "  Loosen TRIMMOMATIC_ARGS (widen the SLIDINGWINDOW) and confirm";
      print "  cutadapt -O is high enough to prevent spurious internal matches.";
      exit 3;
    } else {
      print "  OK: amplicon length preserved.";
    }
  }' "${SUMMARY}"

date
