#!/usr/bin/env bash
#
# Convert an off-the-shelf Hugging Face model to ONNX using Olive, ready for
# bring-your-own (BYO) deployment on Foundry Local on Azure Local.
#
# This is the "pull from Hugging Face -> convert -> ONNX" path described in the
# project plan. The default target is a small time-series / sequence model; the
# script is parameterised so you can swap in other HF model IDs.
#
# Usage:
#   ./convert_hf_to_onnx.sh <hf_model_id> <output_dir> [precision]
# Example:
#   ./convert_hf_to_onnx.sh amazon/chronos-t5-small ./artifacts/chronos int8
#
set -euo pipefail

HF_MODEL_ID="${1:-amazon/chronos-t5-small}"
OUTPUT_DIR="${2:-./artifacts/hf-onnx}"
PRECISION="${3:-int8}"

echo "==> Installing conversion toolchain (Olive + Optimum)"
pip install --quiet --upgrade "olive-ai" "optimum[onnxruntime]" "transformers" "onnx" "onnxruntime"

mkdir -p "${OUTPUT_DIR}"

echo "==> Attempting Olive optimize: ${HF_MODEL_ID} (precision=${PRECISION})"
if olive optimize \
    --model_name_or_path "${HF_MODEL_ID}" \
    --output_path "${OUTPUT_DIR}" \
    --device cpu \
    --provider CPUExecutionProvider \
    --precision "${PRECISION}" \
    --log_level 1; then
  echo "==> Olive conversion succeeded"
else
  echo "==> Olive path failed; falling back to optimum-cli export"
  optimum-cli export onnx \
    --model "${HF_MODEL_ID}" \
    --task feature-extraction \
    "${OUTPUT_DIR}"
fi

echo "==> Conversion complete. Artifacts in ${OUTPUT_DIR}:"
ls -lh "${OUTPUT_DIR}"
