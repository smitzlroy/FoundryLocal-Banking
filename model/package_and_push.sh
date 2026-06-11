#!/usr/bin/env bash
#
# Package an ONNX model directory as a .tar.gz OCI artifact and push it to an
# OCI-compatible registry (Azure Container Registry) using ORAS, so Foundry
# Local on Azure Local can pull it as a bring-your-own model.
#
# Layout expected in <model_dir> for an ONNX predictive workload:
#   model.onnx (or rate_forecast.onnx) + model_metadata.json
#
# Usage:
#   ./package_and_push.sh <model_dir> <acr_name> <repository> <tag>
# Example:
#   ./package_and_push.sh ./artifacts flbankingacr models/rate-forecast v1
#
set -euo pipefail

MODEL_DIR="${1:?model dir required}"
ACR_NAME="${2:?acr name required}"
REPOSITORY="${3:?repository required}"
TAG="${4:-v1}"

REGISTRY="${ACR_NAME}.azurecr.io"
ARCHIVE="$(mktemp -d)/model.tar.gz"

echo "==> Creating archive from ${MODEL_DIR}"
tar -czf "${ARCHIVE}" -C "${MODEL_DIR}" .
echo "    archive: ${ARCHIVE} ($(du -h "${ARCHIVE}" | cut -f1))"

echo "==> Logging in to ${REGISTRY} via ORAS (using az token)"
TOKEN="$(az acr login --name "${ACR_NAME}" --expose-token --query accessToken -o tsv)"
oras login "${REGISTRY}" -u "00000000-0000-0000-0000-000000000000" -p "${TOKEN}"

echo "==> Pushing ${REGISTRY}/${REPOSITORY}:${TAG}"
oras push "${REGISTRY}/${REPOSITORY}:${TAG}" \
  --artifact-type "application/vnd.foundrylocal.model.v1+tar" \
  "$(basename "${ARCHIVE}"):application/gzip" \
  -C "$(dirname "${ARCHIVE}")"

echo "==> Done. Reference in ModelDeployment:"
echo "    registry: ${REGISTRY}"
echo "    repository: ${REPOSITORY}"
echo "    tag: ${TAG}"
