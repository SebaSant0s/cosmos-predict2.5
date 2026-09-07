#!/usr/bin/env bash
# Build the Cosmos-Predict2.5 image ON THE KUBERNETES NODE with podman.
#
# This node keeps podman and CRI-O image stores in DIFFERENT places:
#   podman default : /var/lib/containers/storage        (small root disk - avoid)
#   CRI-O          : /opt/showroom/data/containers-storage  (2.4 TB disk)
# We build straight into CRI-O's store so (a) it lands on the big disk and
# (b) Kubernetes pods can use it with imagePullPolicy: IfNotPresent / Never.
#
# Run from the repo root on the node:
#   bash deploy/build.sh
set -euo pipefail

IMAGE="localhost/cosmos-predict2.5:local"
CRIO_ROOT="/opt/showroom/data/containers-storage"
BIG_TMP="/opt/showroom/data/tmp"

if [[ "$(id -u)" -ne 0 ]]; then
  echo ">> re-running under sudo"
  exec sudo -E bash "$0" "$@"
fi

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
