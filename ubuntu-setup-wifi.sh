#!/bin/bash
set -e

# Detect current kernel version
KVER_FULL=$(uname -r)
KVER_BASE=$(echo $KVER_FULL | cut -d'-' -f1)
KVER_MINOR=$(echo $KVER_BASE | cut -d'.' -f1,2)

PKG_NAME="mediatek-mt7927"
PKG_VER="2.1"
DKMS_DIR="/usr/src/${PKG_NAME}-${PKG_VER}"
BASE_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/net/wireless/mediatek/mt76"

echo "=== MT7927 WiFi-Only Restoration Script ==="

# 1. FIRMWARE PLACEMENT
echo "[1/4] Setting up Firmware..."
sudo mkdir -p /lib/firmware/mediatek/mt7927
# Locate firmware in your current local 'firmware/wifi' directory
W_PATCH=$(find ./firmware/wifi -name "WIFI_MT6639_PATCH_MCU_2_1_hdr.bin" | head -n 1)
W_RAM=$(find ./firmware/wifi -name "WIFI_RAM_CODE_MT6639_2_1.bin" | head -n 1)

if [ -n "$W_PATCH" ] && [ -n "$W_RAM" ]; then
    # Driver patches expect MT7927 in the filename for handshaking
    sudo cp "$W_PATCH" /lib/firmware/mediatek/WIFI_MT7927_PATCH_MCU_2_1_hdr.bin
    sudo cp "$W_RAM" /lib/firmware/mediatek/WIFI_RAM_CODE_MT7927_2_1.bin
    sudo cp "$W_PATCH" /lib/firmware/mediatek/mt7927/WIFI_MT7927_PATCH_MCU_2_1_hdr.bin
    sudo cp "$W_RAM" /lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT7927_2_1.bin
    echo "WiFi Firmware (MT7927) successfully placed."
else
    echo "!!! ERROR: Firmware files not found in ./firmware/wifi/"
    exit 1
fi

# 2. DKMS CLEANUP
echo "[2/4] Preparing DKMS Environment..."
sudo dkms remove -m ${PKG_NAME} -v ${PKG_VER} --all 2>/dev/null || true
sudo rm -rf "${DKMS_DIR}"
sudo mkdir -p "${DKMS_DIR}/mt76/mt7921" "${DKMS_DIR}/mt76/mt7925"

# 3. KERNEL SOURCE DOWNLOADER
dl_file() {
  local path=$1
  local destdir=$2
  local filename=$(basename "$path")
  # Try stable tag, then minor version branch, then master
  for ref in "v${KVER_BASE}" "linux-${KVER_MINOR}.y" "v${KVER_MINOR}" "master"; do
    if sudo curl -s -f -o "${destdir}/${filename}" "${BASE_URL}/${path}?h=${ref}"; then
      return 0
    fi
  done
  echo "ERROR: Failed to download ${path}"
  return 1
}

echo "[3/4] Downloading mt76 WiFi Sources..."
MT76_FILES=("mt76.h" "mt76_connac.h" "mt76_connac2_mac.h" "mt76_connac3_mac.h" "mt76_connac_mcu.h" "mt76_connac_mcu.c" "mt76_connac_mac.c" "mt76_connac3_mac.c" "mmio.c" "util.c" "util.h" "trace.c" "trace.h" "dma.c" "dma.h" "mac80211.c" "debugfs.c" "eeprom.c" "tx.c" "agg-rx.c" "mcu.c" "wed.c" "scan.c" "channel.c" "pci.c" "testmode.h" "mt792x.h" "mt792x_regs.h" "mt792x_core.c" "mt792x_mac.c" "mt792x_trace.c" "mt792x_trace.h" "mt792x_debugfs.c" "mt792x_dma.c" "mt792x_acpi_sar.c" "mt792x_acpi_sar.h" "sdio.h")
for f in "${MT76_FILES[@]}"; do dl_file "${f}" "${DKMS_DIR}/mt76"; done

MT7921_FILES=("mt7921.h" "mac.c" "mcu.c" "main.c" "init.c" "debugfs.c" "pci.c" "pci_mac.c" "pci_mcu.c" "sdio.c" "sdio_mac.c" "sdio_mcu.c" "regs.h" "mcu.h")
for f in "${MT7921_FILES[@]}"; do dl_file "mt7921/${f}" "${DKMS_DIR}/mt76/mt7921"; done

MT7925_FILES=("mt7925.h" "mac.c" "mac.h" "mcu.c" "main.c" "init.c" "debugfs.c" "pci.c" "pci_mac.c" "pci_mcu.c" "regd.c" "regd.h" "regs.h" "mcu.h")
for f in "${MT7925_FILES[@]}"; do dl_file "mt7925/${f}" "${DKMS_DIR}/mt76/mt7925"; done

echo "Applying WiFi Patches..."
sudo cp mt6639-wifi-init.patch mt6639-wifi-dma.patch mt7902-wifi-6.19.patch "${DKMS_DIR}/"
cd "${DKMS_DIR}/mt76"
sudo patch -p1 < "${DKMS_DIR}/mt7902-wifi-6.19.patch"
sudo patch -p1 < "${DKMS_DIR}/mt6639-wifi-init.patch"
sudo patch -p1 < "${DKMS_DIR}/mt6639-wifi-dma.patch"
sudo sed -i 's/kzalloc_flex(\*tid, reorder_buf, size)/kzalloc(struct_size(tid, reorder_buf, size), GFP_ATOMIC)/g' "${DKMS_DIR}/mt76/agg-rx.c"

echo "Generating Build Files..."
sudo tee "${DKMS_DIR}/Kbuild" > /dev/null <<'EOF'
obj-m += mt76/
EOF

sudo tee "${DKMS_DIR}/mt76/Kbuild" > /dev/null <<'EOF'
obj-m += mt76.o mt76-connac-lib.o mt792x-lib.o mt7921/ mt7925/
mt76-y := mmio.o util.o trace.o dma.o mac80211.o debugfs.o eeprom.o tx.o agg-rx.o mcu.o wed.o scan.o channel.o pci.o
mt76-connac-lib-y := mt76_connac_mcu.o mt76_connac_mac.o mt76_connac3_mac.o
mt792x-lib-y := mt792x_core.o mt792x_mac.o mt792x_trace.o mt792x_debugfs.o mt792x_dma.o mt792x_acpi_sar.o
ccflags-y := -I$(src)
EOF

sudo tee "${DKMS_DIR}/mt76/mt7921/Kbuild" > /dev/null <<'EOF'
obj-m += mt7921-common.o mt7921e.o
mt7921-common-y := mac.o mcu.o main.o init.o debugfs.o
mt7921e-y := pci.o pci_mac.o pci_mcu.o
ccflags-y := -I$(src) -I$(src)/..
EOF

sudo tee "${DKMS_DIR}/mt76/mt7925/Kbuild" > /dev/null <<'EOF'
obj-m += mt7925-common.o mt7925e.o
mt7925-common-y := mac.o mcu.o regd.o main.o init.o debugfs.o
mt7925e-y := pci.o pci_mac.o pci_mcu.o
ccflags-y := -I$(src) -I$(src)/..
EOF

sudo tee "${DKMS_DIR}/dkms.conf" > /dev/null <<EOF
PACKAGE_NAME="${PKG_NAME}"
PACKAGE_VERSION="${PKG_VER}"
BUILT_MODULE_NAME[0]="mt76"
BUILT_MODULE_LOCATION[0]="mt76/"
DEST_MODULE_LOCATION[0]="/updates/dkms/"
BUILT_MODULE_NAME[1]="mt76-connac-lib"
BUILT_MODULE_LOCATION[1]="mt76/"
DEST_MODULE_LOCATION[1]="/updates/dkms/"
BUILT_MODULE_NAME[2]="mt792x-lib"
BUILT_MODULE_LOCATION[2]="mt76/"
DEST_MODULE_LOCATION[2]="/updates/dkms/"
BUILT_MODULE_NAME[3]="mt7921-common"
BUILT_MODULE_LOCATION[3]="mt76/mt7921/"
DEST_MODULE_LOCATION[3]="/updates/dkms/"
BUILT_MODULE_NAME[4]="mt7921e"
BUILT_MODULE_LOCATION[4]="mt76/mt7921/"
DEST_MODULE_LOCATION[4]="/updates/dkms/"
BUILT_MODULE_NAME[5]="mt7925-common"
BUILT_MODULE_LOCATION[5]="mt76/mt7925/"
DEST_MODULE_LOCATION[5]="/updates/dkms/"
BUILT_MODULE_NAME[6]="mt7925e"
BUILT_MODULE_LOCATION[6]="mt76/mt7925/"
DEST_MODULE_LOCATION[6]="/updates/dkms/"
AUTOINSTALL="yes"
EOF

# 4. INSTALL
echo "[4/4] Finalizing Installation..."
sudo dkms add -m ${PKG_NAME} -v ${PKG_VER}
sudo dkms build -m ${PKG_NAME} -v ${PKG_VER}
sudo dkms install -m ${PKG_NAME} -v ${PKG_VER}
# Clean up early boot trap
sudo sed -i '/mt7925e/d' /etc/initramfs-tools/modules
sudo update-initramfs -u

echo "=================================================================="
echo "SUCCESS! WiFi-only driver is restored."
echo "Perform a standard REBOOT now."
echo "=================================================================="
