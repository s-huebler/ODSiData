#!/usr/bin/env bash
# Build the Jarosch2023 replication image.
# Run from anywhere; paths are resolved relative to this script.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="jarosch2023-repro:1.0"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found. Install Docker Desktop for Mac first:" >&2
  echo "  https://www.docker.com/products/docker-desktop/" >&2
  exit 1
fi

echo "Building ${IMAGE} for linux/amd64 (this will take 20-40 min on Apple Silicon)..."
docker build \
  --platform linux/amd64 \
  -t "${IMAGE}" \
  -f "${HERE}/Dockerfile" \
  "${HERE}"

echo
echo "Done. Verify with:"
echo "  docker run --rm --platform linux/amd64 ${IMAGE} \\"
echo "    R -q -e \"cat(R.version.string, as.character(packageVersion('dada2')))\""
