#!/usr/bin/env bash
# Build the Cosmos-Predict2.5 image ON THE KUBERNETES NODE with podman.
#
# podman and CRI-O may keep their image stores in DIFFERENT places. We build
# straight into CRI-O's store so Kubernetes pods can use the image with
# imagePullPolicy: IfNotPresent / Never, and so it lands on whatever disk CRI-O uses.
# CRI-O's root is auto-detected; override with CRIO_ROOT=... if detection fails.
# Build temp files go next to it (override with BIG_TMP=...).
#
# Run from the repo root on the node:
#   bash deploy/build.sh
set -euo pipefail

IMAGE="localhost/cosmos-predict2.5:local"

if [[ "$(id -u)" -ne 0 ]]; then
  echo ">> re-running under sudo"
  exec sudo -E bash "$0" "$@"
fi

CRIO_ROOT="${CRIO_ROOT:-$(crictl info 2>/dev/null | grep -o '"root": "[^"]*"' | head -1 | cut -d'"' -f4)}"
if [[ -z "$CRIO_ROOT" ]]; then
  echo "!! could not detect CRI-O's storage root; rerun with CRIO_ROOT=/path bash deploy/build.sh"
  exit 1
fi
BIG_TMP="${BIG_TMP:-$(dirname "$CRIO_ROOT")/tmp}"

mkdir -p "$BIG_TMP"
export TMPDIR="$BIG_TMP"

echo ">> building $IMAGE into CRI-O's store ($CRIO_ROOT)"
echo ">> this is long: pulls the CUDA base image + PyTorch, ~20-40 min"

podman --root="$CRIO_ROOT" --runroot=/run/containers/storage \
  build \
  -f Dockerfile \
  --build-arg STANDALONE=true \
  -t "$IMAGE" \
  .

echo
echo ">> checking CRI-O sees it:"
crictl images | grep -E 'cosmos-predict2.5|^IMAGE' || {
  echo "!! not visible to CRI-O - fall back to the local registry (deploy/README.md)"
  exit 1
}
echo ">> OK - image ready. Next: kubectl apply -f deploy/k8s/20-job.yaml"
