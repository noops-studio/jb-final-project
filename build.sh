#!/usr/bin/env bash
# SUPERSEDED: image build + push now happens in GitHub Actions
# (.github/workflows/build-and-deploy.yml), which pushes to GHCR.
# This script pushed a MUTABLE tag to Docker Hub and would diverge the
# deployed image from what ArgoCD tracks. Kept for local reference only.
if [ "${ALLOW_LEGACY_BUILD:-0}" != "1" ]; then
  echo "build.sh is superseded by GitHub Actions (GHCR)."
  echo "Set ALLOW_LEGACY_BUILD=1 to run it anyway (not recommended)."
  exit 1
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR/uptime-kuma"
DOCKER_USER="${DOCKER_USER:-snoopa}"
IMAGE_NAME="${IMAGE_NAME:-uptime-kuma}"
IMAGE_TAG="${IMAGE_TAG:-1}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-multiarch}"
REMOTE_IMAGE="${DOCKER_USER}/${IMAGE_NAME}:${IMAGE_TAG}"

cd "$APP_DIR"

echo ">> npm install"
npm install

echo ">> npm run build"
npm run build

if ! docker buildx inspect "${BUILDER}" >/dev/null 2>&1; then
  echo ">> creating buildx builder ${BUILDER}"
  docker buildx create --name "${BUILDER}" --driver docker-container --use
else
  docker buildx use "${BUILDER}"
fi
docker buildx inspect --bootstrap >/dev/null

echo ">> docker buildx build ${REMOTE_IMAGE} (${PLATFORMS}, rootless) + push"
docker buildx build \
  --platform "${PLATFORMS}" \
  -t "${REMOTE_IMAGE}" \
  -f docker/dockerfile \
  --target rootless \
  --push \
  .

echo ">> done: ${REMOTE_IMAGE} (${PLATFORMS})"
