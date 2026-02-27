# mediatek-mt7927-dkms

DKMS driver for MediaTek MT7927 (Filogic 380) - WiFi 7 + Bluetooth 5.4 on Linux.

Builds out-of-tree btusb/btmtk (Bluetooth) and mt76 (WiFi) kernel modules with
device ID and firmware patches not yet in mainline. Distributed as an
[AUR package](https://aur.archlinux.org/packages/mediatek-mt7927-dkms).

## Status

| Component | Status | Details |
|-----------|--------|---------|
| Bluetooth (MT6639 via USB) | **WORKING** | Patched btusb with device ID + firmware |
| WiFi (MT7925e via PCIe) | **WORKING** | 2.4/5/6 GHz, 320MHz, PM, suspend/resume |

**Known issues:**
- 5/6 GHz WPA authentication may need 1-2 retries (EAPOL RX header translation quirk)
- TX retransmissions elevated vs baseline (firmware-side, not driver-fixable)
- AP mode and MLO not supported (firmware limitation)

## Supported hardware

| Device | BT USB ID | WiFi PCI ID |
|--------|-----------|-------------|
| ASUS ROG Crosshair X870E Hero | 0489:e13a | 14c3:7927 |
| Lenovo Legion Pro 7 16ARX9 | 0489:e0fa | 14c3:7927 |
| Lenovo Legion Pro 7 16AFR10H | - | 14c3:7927 |
| Foxconn/Azurewave modules | - | 14c3:6639 |
| AMD RZ738 (MediaTek MT7927) | - | 14c3:0738 |
| TP-Link Archer TBE550E PCIe | 0489:e116 | 14c3:7927 |
| ASUS ProArt X870E | - | 14c3:7927 |
| ASUS X870E-E | 13d3:3588 | 14c3:7927 |

Check if your hardware is detected:

```bash
lspci | grep -i 14c3          # WiFi (PCIe)
lsusb | grep -iE '0489|13d3'  # Bluetooth (USB)
```

## Naming guide

MediaTek naming is confusing - see
[MT7927 WiFi: The Missing Piece](https://jetm.github.io/blog/posts/mt7927-wifi-the-missing-piece/)
for the full story. Here's the short version:

```
MT7927 = combo module on the motherboard (WiFi 7 + BT 5.4, Filogic 380)
  ├─ BT side:   internally MT6639, connects via USB
  └─ WiFi side: architecturally MT7925, connects via PCIe
```

**MT7902** is a separate WiFi 6E chip (different product line, uses mt7921 driver).
It's included in this package at zero cost because it shares the mt76 dependency
chain with mt7925e.

## Install

### AUR (Arch Linux)

```bash
yay -S mediatek-mt7927-dkms
# or
paru -S mediatek-mt7927-dkms
```

### Manual (Arch Linux)

```bash
git clone https://aur.archlinux.org/mediatek-mt7927-dkms.git
cd mediatek-mt7927-dkms
makepkg -si
```

### Other distributions

- **NixOS:** [cmspam/mt7927-nixos](https://github.com/cmspam/mt7927-nixos), [clemenscodes/linux-mt7927](https://github.com/clemenscodes/linux-mt7927)
- **Ubuntu:** [giosal/mediatek-mt7927-dkms](https://github.com/giosal/mediatek-mt7927-dkms)

## Post-install

Reload kernel modules to pick up new builds without rebooting:

```bash
sudo modprobe -r mt7925e mt7921e btusb
sudo modprobe mt7925e btusb
```

Or just reboot.

## Verification

Quick validation (<30 seconds, non-destructive):

```bash
./test-driver.sh              # auto-detect interface
./test-driver.sh wlp9s0       # specify interface
```

Long-running stability monitor (8 hours default):

```bash
./stability-test.sh                   # 8-hour test, auto-detect
./stability-test.sh -d 2h             # 2-hour test
./stability-test.sh -s 192.168.1.50   # with iperf3 server
```

## Troubleshooting

**5/6 GHz authentication retries:** WPA handshake may fail on the first attempt.
Configure NetworkManager to retry automatically:

```bash
nmcli connection modify <ssid> connection.auth-retries 3
```

**Bluetooth rfkill soft-block:** If Bluetooth appears blocked after reboot:

```bash
rfkill unblock bluetooth
```

To fix permanently, add a udev rule that auto-unblocks on device attach (replace
the USB ID with yours from `lsusb | grep -iE '0489|13d3'`):

```bash
echo 'ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0489", ATTR{idProduct}=="e13a", RUN+="/usr/bin/rfkill unblock bluetooth"' \
  | sudo tee /etc/udev/rules.d/99-mt6639-bt-rfkill.rules
sudo udevadm control --reload-rules
```

**DKMS not built for current kernel:**

```bash
sudo dkms install mediatek-mt7927/2.1
```

## Upstream tracking

Patches are prepared for upstream submission but not yet sent to linux-wireless@.
See the [mt76#927](https://github.com/openwrt/mt76/issues/927) tracking issue.

## License

GPL-2.0-only
