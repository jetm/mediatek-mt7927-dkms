#!/usr/bin/env bash
set -euo pipefail

# DKMS PRE_BUILD script for MediaTek MT7927 (BT + WiFi)
# - Copies pre-extracted btusb + btmtk source and applies the BT patch
# - mt76 WiFi source is pre-patched and included in the DKMS tree

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Bluetooth: copy pre-extracted source and apply patch ---

BT_DIR="$SCRIPT_DIR/drivers/bluetooth"

if [[ ! -d "$BT_DIR" ]] || [[ ! -f "$BT_DIR/btusb.c" ]]; then
	echo "ERROR: Pre-extracted bluetooth source not found at $BT_DIR" >&2
	echo "The package may not have been installed correctly." >&2
	exit 1
fi

echo "==> Using pre-extracted bluetooth source from package"

# Check if MT6639 support is already present upstream (chip ID in btmtk.c + firmware path in btmtk.h)
if grep -q '0x6639' "$BT_DIR/btmtk.c" && grep -q '0x6639' "$BT_DIR/btmtk.h"; then
	echo "==> MT6639 support already present in kernel source"
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

# Create Makefile for out-of-tree btusb build
cat >"$BT_DIR/Makefile" <<'MAKEFILE'
obj-m += btusb.o btmtk.o
MAKEFILE

echo "==> Bluetooth source prepared (btusb + btmtk)"

# --- WiFi: mt76 source is pre-patched (mt7902-wifi-6.19.patch + mt6639-wifi-init.patch) ---

echo "==> WiFi mt76 source already patched and included"
echo "==> Source prepared for compilation (btusb + btmtk + mt76 + mt7921e + mt7925e)"
