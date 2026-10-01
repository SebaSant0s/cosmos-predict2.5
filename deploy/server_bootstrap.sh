#!/usr/bin/env bash
# Sanity-check the Kubernetes node before deploying Cosmos.
# Safe to run repeatedly. Does NOT install anything.
#   bash deploy/server_bootstrap.sh
set -uo pipefail

echo "== OS =="
cat /etc/os-release | grep PRETTY_NAME

echo; echo "== tools =="
for t in podman crictl kubectl git git-lfs; do
  if command -v "$t" >/dev/null; then printf '  %-10s %s\n' "$t" "$(command -v "$t")"; else echo "  $t   MISSING"; fi
done

echo; echo "== kubectl context / perms =="
kubectl config current-context
kubectl auth can-i create pods
kubectl auth can-i create jobs

echo; echo "== GPUs advertised to Kubernetes =="
kubectl get nodes -o=custom-columns=NAME:.metadata.name,'GPU:.status.allocatable.nvidia\.com/gpu','MODEL:.metadata.labels.nvidia\.com/gpu\.product'

echo; echo "== storage classes (10-pvc.yaml expects 'local-path') =="
kubectl get storageclass

echo; echo "== container storage roots (podman vs CRI-O must match to sideload images) =="
echo -n "  podman graphRoot: "; sudo podman info 2>/dev/null | awk '/graphRoot/{print $2}'
CRIO_ROOT="$(sudo crictl info 2>/dev/null | grep -o '"root": "[^"]*"' | head -1 | cut -d'"' -f4)"
echo "  crio  root:       ${CRIO_ROOT:-<not detected>}"

echo; echo "== node free disk (checkpoints are large) =="
df -h / /var/lib ${CRIO_ROOT:+"$CRIO_ROOT"} 2>/dev/null

echo; echo "done."
