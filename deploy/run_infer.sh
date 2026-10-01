#!/usr/bin/env bash
# Runs INSIDE the Cosmos container / Kubernetes pod. Generates one sample.
#
# Configurable via env vars (the k8s Job sets these):
#   INPUT       path to an inference json   (default: assets/base/shovel_example.json)
#   MODEL       model name                  (default: 2B/post-trained)
#   OUTPUT_DIR  where to write results       (default: outputs)
#   NUM_GPUS    GPUs to split one run across (default: 1; >1 uses torchrun)
#
# Runs are only allowed in the GPU window 19:00-03:00 Chile time: outside it the
# script refuses to start, and inside it the run is killed when 03:00 arrives.
#   WINDOW_TZ        (default: America/Santiago, follows Chile's DST)
#   ENFORCE_WINDOW   set to 0 to bypass (e.g. a quick test agreed with the team)
#
# Model names: 2B/post-trained, 2B/pre-trained, 2B/distilled (text2world only),
#              14B/post-trained, 14B/pre-trained
set -euo pipefail

INPUT="${INPUT:-assets/base/shovel_example.json}"
MODEL="${MODEL:-2B/post-trained}"
OUTPUT_DIR="${OUTPUT_DIR:-outputs}"
NUM_GPUS="${NUM_GPUS:-1}"
WINDOW_TZ="${WINDOW_TZ:-America/Santiago}"
ENFORCE_WINDOW="${ENFORCE_WINDOW:-1}"
NAME="$(basename "${INPUT%.*}")"

# --- GPU time window (19:00-03:00 local) ---
TIME_LIMIT=()
if [[ "$ENFORCE_WINDOW" != "0" ]]; then
  if [[ ! -f "/usr/share/zoneinfo/$WINDOW_TZ" ]]; then
    echo "!! time zone data for $WINDOW_TZ not found (tzdata missing?) - refusing to run"
    exit 1
  fi
  hour=$((10#$(TZ="$WINDOW_TZ" date +%H)))
  if (( hour >= 3 && hour < 19 )); then
    echo "!! outside the GPU window: it is $(TZ="$WINDOW_TZ" date '+%H:%M') in $WINDOW_TZ;"
    echo "   runs are allowed 19:00-03:00. Re-apply the Job after 19:00."
    exit 1
  fi
  if (( hour >= 19 )); then end_day="tomorrow"; else end_day="today"; fi
  end_epoch="$(TZ="$WINDOW_TZ" date -d "$end_day 03:00" +%s)"
  remaining=$(( end_epoch - $(date +%s) ))
  echo ">> GPU window open; this run will be stopped at 03:00 $WINDOW_TZ (in $((remaining / 60)) min)"
  TIME_LIMIT=(timeout --signal=TERM --kill-after=60 "$remaining")
fi

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

status=0
"${TIME_LIMIT[@]}" "${LAUNCH[@]}" examples/inference.py \
  -i "$INPUT" \
  -o "$OUTPUT_DIR/$NAME" \
  --model="$MODEL" || status=$?

if (( status == 124 )); then
  echo "!! stopped: reached 03:00 $WINDOW_TZ, end of the GPU window"
  exit "$status"
elif (( status != 0 )); then
  exit "$status"
fi

echo "Done. Results in $OUTPUT_DIR/$NAME"
