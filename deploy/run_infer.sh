#!/usr/bin/env bash
set -euo pipefail
# quick first test: distilled 2B, text -> video (fastest, lowest VRAM)
python examples/inference.py \
  -i assets/base/shovel_example.json \
  -o outputs/base_image2world \
  --inference-type=image2world \
  --model=2B/distilled
