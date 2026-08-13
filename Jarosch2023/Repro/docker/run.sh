#!/usr/bin/env bash
# Run a command inside the replication container with Repro/ mounted at /work.
#
#   ./docker/run.sh bash                          # interactive shell
#   ./docker/run.sh bash scripts/02_trim.sh       # run a pipeline step
#   ./docker/run.sh Rscript scripts/03_dada2.R
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPRO="$(cd "${HERE}/.." && pwd)"
STUDY="$(cd "${REPRO}/.." && pwd)"     # Jarosch2023/ — holds Metadata/
IMAGE="jarosch2023-repro:1.0"

# Repro/ is mounted read-write at /work; the study folder is mounted read-only
# at /study so scripts can reach Metadata/jarosch_alpha_diversity.tsv. A bind
# mount does not expose its parent, so /work/.. is NOT the study folder.
docker run --rm -it \
  --platform linux/amd64 \
  -e NCORES="${NCORES:-1}" \
  -e THREADS="${THREADS:-4}" \
  -e PAIRED="${PAIRED:-0}" \
  -e PUB_ALPHA="${PUB_ALPHA:-}" \
  -e TRIMMOMATIC_ARGS="${TRIMMOMATIC_ARGS:-}" \
  -v "${REPRO}:/work" \
  -v "${STUDY}:/study:ro" \
  -w /work \
  "${IMAGE}" \
  "$@"
