#!/usr/bin/env bash
set -euo pipefail

# DKMS PRE_BUILD script for btusb MT7927/MT6639 patch
# Downloads btusb + btmtk source from kernel.org stable tree and applies the patch

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KERNEL_VERSION="${kernelver:-$(uname -r)}"
# Extract base version (e.g., 6.19.0-2-cachyos -> 6.19.0)
BASE_VERSION=$(echo "$KERNEL_VERSION" | grep -oP '^\d+\.\d+\.\d+')
MAJOR_MINOR=$(echo "$BASE_VERSION" | grep -oP '^\d+\.\d+')

BT_DIR="$SCRIPT_DIR/drivers/bluetooth"
mkdir -p "$BT_DIR"

echo "==> Downloading bluetooth source for kernel v${BASE_VERSION}..."

# Try exact version first, then fall back to major.minor branch
URLS_PREFIX=(
  "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/bluetooth/%s?h=v${BASE_VERSION}"
  "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/bluetooth/%s?h=linux-${MAJOR_MINOR}.y"
  "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/bluetooth/%s?h=v${MAJOR_MINOR}"
)

download_file() {
  local file="$1"
  for url_fmt in "${URLS_PREFIX[@]}"; do
    local url
    url=$(printf "$url_fmt" "$file")
    if curl -sS -f -o "$BT_DIR/${file}" "$url"; then
      echo "==> Downloaded ${file}"
      return 0
    fi
  done
  return 1
}

# Required source files for btusb + btmtk build
REQUIRED_FILES=(btusb.c btmtk.c btmtk.h)
OPTIONAL_FILES=(btbcm.h btbcm.c btintel.h btrtl.h)

for file in "${REQUIRED_FILES[@]}"; do
  if ! download_file "$file"; then
    echo "ERROR: Failed to download ${file} for kernel ${BASE_VERSION}" >&2
    exit 1
  fi
done

for file in "${OPTIONAL_FILES[@]}"; do
  download_file "$file" 2>/dev/null || true
done

# Check if MT6639 support is already present upstream (all three layers)
if grep -q "0x6639" "$BT_DIR/btmtk.c" && grep -q "0xe13a" "$BT_DIR/btusb.c"; then
  echo "==> MT6639 support already present in kernel ${BASE_VERSION}"
  echo "==> Patch not needed - building unmodified modules"
else
  echo "==> Applying mt6639-bt-6.19.patch..."
  cd "$SCRIPT_DIR"
  if ! patch -p1 --forward <"$SCRIPT_DIR/mt6639-bt-6.19.patch"; then
    echo "==> Patch failed to apply cleanly, attempting fuzzy match..."
    patch -p1 --forward --fuzz=3 <"$SCRIPT_DIR/mt6639-bt-6.19.patch"
  fi
  echo "==> Patch applied successfully"
fi

# Create Makefile for out-of-tree build
cat >"$BT_DIR/Makefile" <<'MAKEFILE'
obj-m += btusb.o btmtk.o
MAKEFILE

echo "==> Source prepared for compilation (btusb + btmtk)"
