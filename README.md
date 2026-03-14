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
- TX retransmissions elevated vs baseline (firmware-side, not driver-fixable) ([#26](https://github.com/jetm/mediatek-mt7927-dkms/issues/26))
- Bluetooth USB device may disappear after module reload or DKMS upgrade, persists
  across reboots. Workaround: shut down, unplug PSU / switch off at back, wait 10
  seconds, power back on. A regular reboot is not enough - the MT6639 BT firmware
  locks up and only recovers with a full power drain.
  ([#23](https://github.com/jetm/mediatek-mt7927-dkms/issues/23))

**Recently fixed:**
- 5/6 GHz WPA 4WAY_HANDSHAKE_TIMEOUT - fixed by explicit band_idx assignment ([#24](https://github.com/jetm/mediatek-mt7927-dkms/issues/24))

## Supported hardware

| Device | BT USB ID | WiFi PCI ID |
|--------|-----------|-------------|
| ASUS ROG Crosshair X870E Hero | 0489:e13a | 14c3:7927 |
| ASUS ProArt X870E-Creator WiFi | 13d3:3588 | 14c3:6639 |
| ASUS ROG Strix X870-I | 0489:e13a | 14c3:7927 |
| ASUS X870E-E | 13d3:3588 | 14c3:7927 |
| Gigabyte X870E Aorus Master X3D | 0489:e10f | 14c3:7927 |
| Gigabyte Z790 AORUS MASTER X | 0489:e10f | 14c3:7927 |
| Lenovo Legion Pro 7 16ARX9 | 0489:e0fa | 14c3:7927 |
| Lenovo Legion Pro 7 16AFR10H | 0489:e0fa | 14c3:7927 |
| TP-Link Archer TBE550E PCIe | 0489:e116 | 14c3:7927 |
| EDUP EP-MT7927BE M.2 | - | 14c3:7927 |
| Foxconn/Azurewave M.2 modules | - | 14c3:6639 |
| AMD RZ738 (MediaTek MT7927) | - | 14c3:0738 |

Check if your hardware is detected:

```bash
lspci | grep -i 14c3          # WiFi (PCIe)
lsusb | grep -iE '0489|13d3|0e8d'  # Bluetooth (USB)
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

### Ubuntu (kernel < 6.19) — automated script

```bash
git clone https://github.com/jetm/mediatek-mt7927-dkms.git
cd mediatek-mt7927-dkms
sudo ./install-ubuntu.sh
```

The script handles prerequisites, the airoha stub header, DKMS build/install, and
module reload automatically. See below for manual steps if you prefer.

### Manual install on Ubuntu (kernel < 6.19)

The mt76 source is extracted from kernel 6.19.6. On Ubuntu 24.04 HWE (kernel 6.17),
the build fails because `linux/soc/airoha/airoha_offload.h` doesn't exist yet.
Fix by creating a stub header before building:

```bash
# 1. Install prerequisites
sudo apt install dkms linux-headers-$(uname -r)

# 2. Create /var/lib/dkms if it doesn't exist
sudo mkdir -p /var/lib/dkms

# 3. Download sources and firmware
git clone https://github.com/jetm/mediatek-mt7927-dkms.git
cd mediatek-mt7927-dkms
make download
make sources

# 4. Create stub airoha_offload.h (only needed for kernel < 6.19)
sudo mkdir -p /lib/modules/$(uname -r)/build/include/linux/soc/airoha
sudo tee /lib/modules/$(uname -r)/build/include/linux/soc/airoha/airoha_offload.h > /dev/null << 'EOF'
#ifndef _AIROHA_OFFLOAD_H
#define _AIROHA_OFFLOAD_H
#include <linux/types.h>
#include <linux/gfp.h>
#include <linux/skbuff.h>
struct airoha_ppe_dev;
struct airoha_npu;
enum airoha_npu_wlan_set_cmd { __AIROHA_NPU_WLAN_SET_DUMMY };
enum airoha_npu_wlan_get_cmd { __AIROHA_NPU_WLAN_GET_DUMMY };
struct airoha_npu_tx_dma_desc { __le32 d[8]; };
struct airoha_npu_rx_dma_desc { __le32 d[8]; };
static inline int airoha_npu_wlan_send_msg(struct airoha_npu *npu, int ifindex,
    enum airoha_npu_wlan_set_cmd cmd, void *val, int len, gfp_t gfp)
{ return -EOPNOTSUPP; }
static inline int airoha_npu_wlan_get_msg(struct airoha_npu *npu, int ifindex,
    enum airoha_npu_wlan_get_cmd cmd, void *val, int len, gfp_t gfp)
{ return -EOPNOTSUPP; }
static inline int airoha_npu_wlan_get_irq_status(struct airoha_npu *npu, int index)
{ return 0; }
static inline void airoha_npu_wlan_set_irq_status(struct airoha_npu *npu, int status) {}
static inline void airoha_npu_wlan_disable_irq(struct airoha_npu *npu, int index) {}
static inline bool airoha_ppe_dev_check_skb(struct airoha_ppe_dev *dev,
    struct sk_buff *skb, u32 hash, bool flag) { return false; }
#endif
EOF

# 5. Install, build, and load
sudo make install
sudo dkms add mediatek-mt7927/2.4
sudo dkms build mediatek-mt7927/2.4
sudo dkms install mediatek-mt7927/2.4

# 6. Unload old mt76 modules first, then load new ones
sudo modprobe -r mt7921u mt792x_usb mt7921e mt7921_common mt7925e mt7925_common \
    mt792x_lib mt76_connac_lib mt76_usb mt76 btusb btmtk 2>/dev/null
sudo modprobe mt7925e btusb
```

**Note:** If `modprobe mt7925e` fails with "disagrees about version of symbol", old
in-kernel mt76 modules are still loaded. Unload the entire mt76 stack (see step 6)
or reboot.

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


**Bluetooth USB device disappeared:**

The MT6639 BT firmware can lock up during module reload or DKMS upgrade, causing the
USB device to vanish from `lsusb`. This persists across reboots and affects all OSes
(Linux and Windows). See [#23](https://github.com/jetm/mediatek-mt7927-dkms/issues/23).

Fix: shut down completely, unplug the PSU cable (or switch off at the back), wait at
least 10 seconds, then power back on. A CMOS reset also works but is more disruptive.

**DKMS not built for current kernel:**

```bash
sudo dkms install mediatek-mt7927/2.3
```

## Upstream tracking

| Submission | Status | Tracking |
|-----------|--------|----------|
| WiFi patches (linux-wireless@) | Under review | [#15](https://github.com/jetm/mediatek-mt7927-dkms/issues/15) |
| BT driver patches (linux-bluetooth@) | v2 pending | [#16](https://github.com/jetm/mediatek-mt7927-dkms/issues/16) |
| BT firmware (linux-firmware) | MR open | [#17](https://github.com/jetm/mediatek-mt7927-dkms/issues/17) |

See [mt76#927](https://github.com/openwrt/mt76/issues/927) for the community tracking issue.

## Roadmap

### Upstream submission

Submit WiFi patches to linux-wireless@, BT driver patches to linux-bluetooth@,
and BT firmware to linux-firmware. Once merged, this package becomes unnecessary
for kernels that include MT7927 support.

- **WiFi** ([#15](https://github.com/jetm/mediatek-mt7927-dkms/issues/15)) -
  18-patch series on linux-wireless@, under review.
- **BT driver** ([#16](https://github.com/jetm/mediatek-mt7927-dkms/issues/16)) -
  2-patch series on linux-bluetooth@, v2 pending per reviewer feedback (split
  USB IDs into per-device commits, add Tested-by + lsusb/dmesg).
- **BT firmware** ([#17](https://github.com/jetm/mediatek-mt7927-dkms/issues/17)) -
  GitLab MR [!946](https://gitlab.com/kernel-firmware/linux-firmware/-/merge_requests/946)
  on linux-firmware, pipeline passes, awaiting review.

### After the base series

These are planned as follow-up patches once the 18-patch base series lands:

- **MLO (Multi-Link Operation)** ([#25](https://github.com/jetm/mediatek-mt7927-dkms/issues/25)) -
  STR dual-link verified working (5GHz+2.4GHz) with three targeted fixes:
  cfg80211 BSS flag relaxation, ROC timer extension, and 5GHz/6GHz band
  exclusion. Needs more testing before upstream submission.
- **mac_reset recovery** ([#28](https://github.com/jetm/mediatek-mt7927-dkms/issues/28)) -
  full DMA reinitialization on firmware crash. Has unguarded paths on
  mt7925 standalone that need fixing first.
- **Kernel < 6.19 compatibility** ([#27](https://github.com/jetm/mediatek-mt7927-dkms/issues/27)) -
  backport support for older kernels (Fedora/Bazzite use case).

### Firmware dependencies

These issues are firmware-controlled and cannot be fixed in the driver:

- **TX retransmissions** ([#26](https://github.com/jetm/mediatek-mt7927-dkms/issues/26)) -
  ~35% retry rate at 320MHz, firmware manages rate adaptation and retry logic
- **BT USB disappearance** ([#23](https://github.com/jetm/mediatek-mt7927-dkms/issues/23)) -
  MT6639 BT firmware locks up during module reload, requires full power cycle
  (PSU unplug). Affects Linux and Windows.
- **6GHz MLO link** - passive scan and ML probe limitations prevent 6GHz
  link discovery (cfg80211/wpa_supplicant limitation)

See [mt76#927](https://github.com/openwrt/mt76/issues/927) for detailed discussion.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## License

GPL-2.0-only
