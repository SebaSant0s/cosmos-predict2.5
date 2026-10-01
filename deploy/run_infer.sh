#!/usr/bin/env bash
# Runs INSIDE the Cosmos container / Kubernetes pod. Generates one sample.
#
# Configurable via env vars (the k8s Job sets these):
#   INPUT       path to an inference json   (default: assets/base/shovel_example.json)
#   MODEL       model name                  (default: 2B/post-trained)
#   OUTPUT_DIR  where to write results       (default: outputs)
#   NUM_GPUS    GPUs to split one run across (default: 1; >1 uses torchrun)
#
# Model names: 2B/post-trained, 2B/pre-trained, 2B/distilled (text2world only),
#              14B/post-trained, 14B/pre-trained
set -euo pipefail

INPUT="${INPUT:-assets/base/shovel_example.json}"
MODEL="${MODEL:-2B/post-trained}"
OUTPUT_DIR="${OUTPUT_DIR:-outputs}"
NUM_GPUS="${NUM_GPUS:-1}"
NAME="$(basename "${INPUT%.*}")"

echo "=============================================="
echo " Cosmos-Predict2.5 inference"
echo "   input:  $INPUT"
echo "   model:  $MODEL"
echo "   gpus:   $NUM_GPUS"
echo "   output: $OUTPUT_DIR/$NAME"
echo "   HF_HOME: ${HF_HOME:-<default>}"
echo "=============================================="
nvidia-smi || true

if [[ "$NUM_GPUS" -gt 1 ]]; then
  LAUNCH=(torchrun --standalone --nproc_per_node="$NUM_GPUS")
else
  LAUNCH=(python)
fi

"${LAUNCH[@]}" examples/inference.py \
  -i "$INPUT" \
  -o "$OUTPUT_DIR/$NAME" \
  --model="$MODEL"

echo "Done. Results in $OUTPUT_DIR/$NAME"
