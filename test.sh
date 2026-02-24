#!/usr/bin/env bash
set -euo pipefail

PKG="mediatek-mt7927-dkms-2.0-1-x86_64.pkg.tar.zst"
LOG="/tmp/mt7927-test.log"
WAIT=45

if [[ ! -f "$PKG" ]]; then
    echo "ERROR: $PKG not found. Run makepkg -f first."
    exit 1
fi

echo "=== Installing package ==="
sudo pacman -U --noconfirm "$PKG"

echo "=== Reloading driver ==="
# Remove all mt76 modules so mt792x-lib etc. get reloaded too
for mod in mt7925e mt7925_common mt792x_lib mt76_connac_lib mt76; do
    sudo modprobe -r "$mod" 2>/dev/null || true
done
sudo modprobe mt7925e

echo "=== Waiting ${WAIT}s for init ==="
sleep "$WAIT"

echo "=== Capturing dmesg ==="
sudo rm -f "$LOG"
sudo sh -c "dmesg | grep -E 'mt7925e|MT6639' > $LOG"
sudo chmod 644 "$LOG"

# Extract only the latest init cycle (after last "disabling ASPM")
last_aspm=$(grep -n "disabling ASPM" "$LOG" | tail -1 | cut -d: -f1)
if [[ -n "$last_aspm" ]]; then
    cycle=$(tail -n +"$last_aspm" "$LOG")
else
    cycle=$(cat "$LOG")
fi

echo "--- Full log: $LOG ($(wc -l < "$LOG") lines) ---"
echo "--- Latest init cycle ---"

# Show milestones, errors, DMA config, firmware versions, interface creation.
# Skip noisy cmd=0xee (MCU event reads) and bulk cmd=0x2002c (channel config).
# Show first+last MCU TX per CIDX batch to track DMA progress without spam.
echo "$cycle" | grep -Ev "cmd=0xee |cmd=0x2002c " \
    | grep -E "ASPM|CBTOP|CHIPID|chip init|DMA:|prefetch:|TX15:|RX[46]:|MCU TX:|Version|wlan|wlp|timeout|semaphore|not ready|hardware init|error|fail|mac_reset|SCAN_REQ|reset queued|reset_work" \
    | head -60
