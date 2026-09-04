#!/usr/bin/env bash
# Build the Cosmos-Predict2.5 image ON THE KUBERNETES NODE with podman,
# into the container storage that CRI-O also reads, so pods can use it
# with  image: localhost/cosmos-predict2.5:local  +  imagePullPolicy: IfNotPresent
#
# Run from the repo root on the node:
#   bash deploy/build.sh
set -euo pipefail

IMAGE="localhost/cosmos-predict2.5:local"

# Must build as root so the image lands in /var/lib/containers/storage (shared with CRI-O).
if [[ "$(id -u)" -ne 0 ]]; then
  echo ">> re-running under sudo so the image is visible to CRI-O"
  exec sudo -E bash "$0" "$@"
fi

echo ">> podman build $IMAGE  (STANDALONE=true bakes all deps into the image)"
podman build \
  -f Dockerfile \
  --build-arg STANDALONE=true \
  -t "$IMAGE" \
  .

echo
echo ">> built. verifying CRI-O can see it:"
crictl images | grep -E 'cosmos-predict2.5|IMAGE' || {
  echo "!! CRI-O does not see the image - podman and CRI-O are not sharing storage."
  echo "!! See deploy/README.md 'If CRI-O cannot see the image'."
  exit 1
}
echo ">> OK"
