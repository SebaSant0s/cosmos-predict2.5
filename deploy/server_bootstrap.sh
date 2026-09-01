#!/usr/bin/env bash
set -euo pipefail
nvidia-smi
sudo apt-get update
sudo apt-get -y install git git-lfs curl
git lfs install
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "Log out and back in, then re-run the rest."
fi
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
