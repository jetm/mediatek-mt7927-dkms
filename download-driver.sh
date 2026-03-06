#!/usr/bin/env bash
# Download the MediaTek MT7925/MT7927 WiFi driver ZIP from ASUS CDN.
# Extracts a CloudFront signed URL via the ASUS token API.
#
# Usage: ./download-driver.sh [output-dir]
#
# Based on code by Eadinator:
#   https://github.com/openwrt/mt76/issues/927#issuecomment-3936022734

set -euo pipefail

DRIVER_FILENAME="${DRIVER_FILENAME:-DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip}"
OUTPUT_DIR="${1:-.}"

if [[ -f "${OUTPUT_DIR}/${DRIVER_FILENAME}" ]]; then
  echo "Driver ZIP already exists: ${OUTPUT_DIR}/${DRIVER_FILENAME}"
  exit 0
fi

TOKEN_URL="https://cdnta.asus.com/api/v1/TokenHQ?filePath=https:%2F%2Fdlcdnta.asus.com%2Fpub%2FASUS%2Fmb%2F08WIRELESS%2F${DRIVER_FILENAME}%3Fmodel%3DROG%2520CROSSHAIR%2520X870E%2520HERO&systemCode=rog"

echo "Fetching download token from ASUS CDN..."
json="$(curl -sf "${TOKEN_URL}" -X POST -H 'Origin: https://rog.asus.com')"

if [[ -z "${json}" ]]; then
  echo >&2 "Failed to retrieve download token from ASUS CDN"
  exit 1
fi

expires=${json#*\"expires\":\"}
expires=${expires%%\"*}

signature=${json#*\"signature\":\"}
signature=${signature%%\"*}

key_pair_id=${json#*\"keyPairId\":\"}
key_pair_id=${key_pair_id%%\"*}

download_url="https://dlcdnta.asus.com/pub/ASUS/mb/08WIRELESS/${DRIVER_FILENAME}?model=ROG%20CROSSHAIR%20X870E%20HERO&Signature=${signature}&Expires=${expires}&Key-Pair-Id=${key_pair_id}"

mkdir -p "${OUTPUT_DIR}"
echo "Downloading ${DRIVER_FILENAME}..."
if ! curl -L -f -o "${OUTPUT_DIR}/${DRIVER_FILENAME}" "${download_url}"; then
  echo >&2 "Failed to download driver ZIP"
  exit 1
fi

echo "Downloaded: ${OUTPUT_DIR}/${DRIVER_FILENAME}"
