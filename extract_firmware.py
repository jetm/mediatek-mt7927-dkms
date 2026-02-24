#!/usr/bin/env python3

import os
import struct
import sys

# All firmware blobs to extract from mtkwlan.dat
FIRMWARE_BLOBS = [
    "BT_RAM_CODE_MT6639_2_1_hdr.bin",
    "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin",
    "WIFI_RAM_CODE_MT6639_2_1.bin",
]


def extract_by_name(data, name, output_path):
    """Extract a named firmware blob from a mtkwlan.dat container.

    The container format has entries with:
      - A null-terminated ASCII name
      - Padding nulls + a 14-digit numeric timestamp
      - 4-byte aligned offset and size fields (little-endian u32)
      - The firmware blob at the given offset
    """
    name_bytes = name.encode() if isinstance(name, str) else name
    idx = data.find(name_bytes)
    if idx == -1:
        raise RuntimeError(f"Firmware entry '{name}' not found in container")

    entry_pos = idx + len(name_bytes)

    # Skip null padding after name
    while entry_pos < len(data) and data[entry_pos] == 0x00:
        entry_pos += 1

    # Skip 14-digit numeric timestamp if present
    if all(48 <= b <= 57 for b in data[entry_pos : entry_pos + 14]):
        entry_pos += 14

    # Align to 4-byte boundary
    entry_pos = (entry_pos + 3) & ~3

    data_offset = struct.unpack_from("<I", data, entry_pos)[0]
    data_size = struct.unpack_from("<I", data, entry_pos + 4)[0]

    blob = data[data_offset : data_offset + data_size]

    if len(blob) != data_size:
        raise RuntimeError(
            f"Size mismatch for '{name}': expected {data_size}, got {len(blob)}"
        )

    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(output_path, "wb") as f:
        f.write(blob)

    print(f"Extracted {name}: {len(blob)} bytes -> {output_path}")


def extract_all(mtkwlan_path, output_dir):
    """Extract all known firmware blobs to a directory."""
    with open(mtkwlan_path, "rb") as f:
        data = f.read()

    os.makedirs(output_dir, exist_ok=True)

    for name in FIRMWARE_BLOBS:
        output_path = os.path.join(output_dir, name)
        extract_by_name(data, name, output_path)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: extract_firmware.py <mtkwlan.dat> <output-dir-or-file>")
        print(
            "  If output is a directory or has no extension: extract all firmware blobs"
        )
        print("  If output is a .bin file: extract BT firmware only (legacy mode)")
        sys.exit(1)

    mtkwlan_path = sys.argv[1]
    output = sys.argv[2]

    # Legacy mode: if output looks like a specific .bin file, extract BT only
    if output.endswith(".bin"):
        with open(mtkwlan_path, "rb") as f:
            data = f.read()
        extract_by_name(data, FIRMWARE_BLOBS[0], output)
    else:
        extract_all(mtkwlan_path, output)
