#!/usr/bin/env python3

import os
import struct
import sys

FIRMWARE_NAME = b"BT_RAM_CODE_MT6639_2_1_hdr.bin"


def extract(mtkbt_path, output_path):
    with open(mtkbt_path, "rb") as f:
        data = f.read()

    idx = data.find(FIRMWARE_NAME)
    if idx == -1:
        raise RuntimeError("Firmware entry not found")

    entry_pos = idx + len(FIRMWARE_NAME)

    while entry_pos < len(data) and data[entry_pos] == 0x00:
        entry_pos += 1

    if all(48 <= b <= 57 for b in data[entry_pos : entry_pos + 14]):
        entry_pos += 14

    entry_pos = (entry_pos + 3) & ~3

    data_offset = struct.unpack_from("<I", data, entry_pos)[0]
    data_size = struct.unpack_from("<I", data, entry_pos + 4)[0]

    blob = data[data_offset : data_offset + data_size]

    if len(blob) != data_size:
        raise RuntimeError("Size mismatch")

    out_dir = os.path.dirname(output_path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(output_path, "wb") as f:
        f.write(blob)

    print("Extracted firmware:", len(blob), "bytes")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: extract_firmware.py <mtkbt.dat> <output-file>")
        sys.exit(1)

    extract(sys.argv[1], sys.argv[2])
