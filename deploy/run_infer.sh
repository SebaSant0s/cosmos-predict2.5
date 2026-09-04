#!/usr/bin/env bash
# Runs INSIDE the Cosmos container / Kubernetes pod. Generates one sample.
#
# Configurable via env vars (the k8s Job sets these):
#   INPUT       path to an inference json   (default: assets/base/shovel_example.json)
#   MODEL       model name                  (default: 2B/post-trained)
#   OUTPUT_DIR  where to write results       (default: outputs)
#
# Model names: 2B/post-trained, 2B/pre-trained, 2B/distilled (text2world only),
#              14B/post-trained, 14B/pre-trained
set -euo pipefail

INPUT="${INPUT:-assets/base/shovel_example.json}"
MODEL="${MODEL:-2B/post-trained}"
OUTPUT_DIR="${OUTPUT_DIR:-outputs}"
NAME="$(basename "${INPUT%.*}")"

echo "=============================================="
echo " Cosmos-Predict2.5 inference"
echo "   input:  $INPUT"
echo "   model:  $MODEL"
echo "   output: $OUTPUT_DIR/$NAME"
echo "   HF_HOME: ${HF_HOME:-<default>}"
echo "=============================================="
nvidia-smi || true

python examples/inference.py \
  -i "$INPUT" \
  -o "$OUTPUT_DIR/$NAME" \
  --model="$MODEL"

echo "Done. Results in $OUTPUT_DIR/$NAME"
