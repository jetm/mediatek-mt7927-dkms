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
- TX retransmissions elevated vs baseline (firmware-side, not driver-fixable)

**Recently fixed:**
- 5/6 GHz WPA 4WAY_HANDSHAKE_TIMEOUT - fixed by explicit band_idx assignment
- EAPOL connection state progression for reliable WPA handshake

## Supported hardware

| Device | BT USB ID | WiFi PCI ID |
|--------|-----------|-------------|
| ASUS ROG Crosshair X870E Hero | 0489:e13a | 14c3:7927 |
| Lenovo Legion Pro 7 16ARX9 | 0489:e0fa | 14c3:7927 |
| Lenovo Legion Pro 7 16AFR10H | - | 14c3:7927 |
| Foxconn/Azurewave modules | - | 14c3:6639 |
| AMD RZ738 (MediaTek MT7927) | - | 14c3:0738 |
| TP-Link Archer TBE550E PCIe | 0489:e116 | 14c3:7927 |
| ASUS ProArt X870E | 0489:e13a | 14c3:7927 |
| ASUS X870E-E | 13d3:3588 | 14c3:7927 |
| Gigabyte X870E Aorus Master X3D | 0489:e10f | 14c3:7927 |
| Gigabyte Z790 AORUS MASTER X | 0489:e10f | 14c3:7927 |

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
- **Bazzite (Fedora Atomic):** [samutoljamo/bazzite-mt7927](https://github.com/samutoljamo/bazzite-mt7927)

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


**DKMS not built for current kernel:**

```bash
sudo dkms install mediatek-mt7927/2.1
```

## Upstream tracking

WiFi patches under review at [#15](https://github.com/jetm/mediatek-mt7927-dkms/issues/15).
BT patches sent to linux-bluetooth@ ([#16](https://github.com/jetm/mediatek-mt7927-dkms/issues/16)).
See [mt76#927](https://github.com/openwrt/mt76/issues/927) for the tracking issue.

## Roadmap

### Upstream submission

Submit WiFi patches to linux-wireless@ and BT firmware to linux-firmware. Once
merged, this package becomes unnecessary for kernels that include MT7927 support.

### Firmware dependencies

These issues are firmware-controlled and cannot be fixed in the driver:

- **TX retransmissions** - ~35% retry rate at 320MHz, firmware manages rate
  adaptation and retry logic

See [mt76#927](https://github.com/openwrt/mt76/issues/927) for detailed discussion.

## License

GPL-2.0-only
