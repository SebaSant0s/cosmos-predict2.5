#!/usr/bin/env bash
set -euo pipefail
# quick first test: distilled 2B, text -> video (fastest, lowest VRAM)
python examples/inference.py \
  -i assets/base/robot_pouring.json \
  -o outputs/base_text2world \
  --inference-type=text2world \
  --model=2B/distilled
