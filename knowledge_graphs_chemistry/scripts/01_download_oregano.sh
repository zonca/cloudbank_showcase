#!/usr/bin/env bash
set -euo pipefail

OREGANO_URL="${OREGANO_URL:-https://zenodo.org/records/10103842/files/oreganov2.1_metadata_complete.ttl?download=1}"
OUT_DIR="${1:-data}"
OUT_FILE="${2:-oregano_sample.ttl}"

mkdir -p "${OUT_DIR}"
curl -L "${OREGANO_URL}" -o "${OUT_DIR}/${OUT_FILE}"

echo "Downloaded: ${OUT_DIR}/${OUT_FILE}"
