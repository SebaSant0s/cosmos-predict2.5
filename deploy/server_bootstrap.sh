#!/usr/bin/env bash
# Sanity-check the Kubernetes node before deploying Cosmos.
# Safe to run repeatedly. Does NOT install anything.
#   bash deploy/server_bootstrap.sh
set -uo pipefail

sudo -v   # ask for the password up front so it doesn't interleave with output

echo "== OS =="
cat /etc/os-release | grep PRETTY_NAME

echo; echo "== tools =="
for t in podman crictl kubectl git git-lfs; do
  if command -v "$t" >/dev/null; then printf '  %-10s %s\n' "$t" "$(command -v "$t")"; else echo "  $t   MISSING"; fi
done

echo; echo "== Git LFS assets (must be real files, not pointers) =="
if head -c 40 assets/base/shovel_example.json 2>/dev/null | grep -q '^version https://git-lfs'; then
  echo "  NOT PULLED - run: sudo dnf install -y git-lfs && git lfs install && git lfs pull --include='assets/base/**'"
else
  echo "  ok"
fi

echo; echo "== kubectl context / perms =="
kubectl config current-context
kubectl auth can-i create pods
kubectl auth can-i create jobs

echo; echo "== GPUs advertised to Kubernetes =="
kubectl get nodes -o=custom-columns=NAME:.metadata.name,'GPU:.status.allocatable.nvidia\.com/gpu','MODEL:.metadata.labels.nvidia\.com/gpu\.product'

echo; echo "== storage classes (10-pvc.yaml expects 'local-path') =="
kubectl get storageclass

echo; echo "== container storage roots (podman vs CRI-O must match to sideload images) =="
echo "  podman graphRoot: $(sudo podman info --format '{{.Store.GraphRoot}}' 2>/dev/null)"
CRIO_ROOT="$(sudo bash "$(dirname "$0")/crio_root.sh")"
echo "  crio  root:       $CRIO_ROOT"

echo; echo "== node free disk (checkpoints are large) =="
sudo df -h / "$CRIO_ROOT" 2>/dev/null

echo; echo "done."
