#!/usr/bin/env bash
# Run a command inside the replication container with Repro/ mounted at /work.
#
#   ./docker/run.sh bash                          # interactive shell
#   ./docker/run.sh bash scripts/02_trim.sh       # run a pipeline step
#   ./docker/run.sh Rscript scripts/03_dada2.R
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPRO="$(cd "${HERE}/.." && pwd)"
IMAGE="jarosch2023-repro:1.0"

docker run --rm -it \
  --platform linux/amd64 \
  -v "${REPRO}:/work" \
  -w /work \
  "${IMAGE}" \
  "$@"
