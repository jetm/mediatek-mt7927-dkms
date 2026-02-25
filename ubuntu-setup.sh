#!/bin/bash
set -e

PKG_NAME="mediatek-mt7927"
PKG_VER="2.1"
KVER="6.19.3"
KVER_MINOR="6.19"
DKMS_DIR="/usr/src/${PKG_NAME}-${PKG_VER}"
BASE_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/net/wireless/mediatek/mt76"

echo "Cleaning up previous failed attempts..."
sudo dkms remove -m ${PKG_NAME} -v ${PKG_VER} --all 2>/dev/null || true
sudo rm -rf "${DKMS_DIR}"

echo "Creating DKMS directory..."
sudo mkdir -p "${DKMS_DIR}/mt76/mt7921" "${DKMS_DIR}/mt76/mt7925"

echo "Copying base DKMS files..."
sudo cp dkms.conf dkms-patchmodule.sh mt6639-bt-6.19.patch mt6639-wifi-init.patch mt6639-wifi-dma.patch mt7902-wifi-6.19.patch "${DKMS_DIR}/"

echo "Downloading mt76 source files..."

# Broken into multiple lines to prevent copy-paste truncation!
MT76_FILES=(
    "mt76.h" "mt76_connac.h" "mt76_connac2_mac.h" "mt76_connac3_mac.h"
    "mt76_connac_mcu.h" "mt76_connac_mcu.c" "mt76_connac_mac.c" "mt76_connac3_mac.c"
    "mmio.c" "util.c" "util.h" "trace.c" "trace.h" "dma.c" "dma.h"
    "mac80211.c" "debugfs.c" "eeprom.c" "tx.c" "agg-rx.c" "mcu.c" "wed.c"
    "scan.c" "channel.c" "pci.c" "testmode.h" "mt792x.h" "mt792x_regs.h"
    "mt792x_core.c" "mt792x_mac.c" "mt792x_trace.c" "mt792x_trace.h"
    "mt792x_debugfs.c" "mt792x_dma.c" "mt792x_acpi_sar.c" "mt792x_acpi_sar.h" "sdio.h"
)

MT7921_FILES=(
    "mt7921.h" "mac.c" "mcu.c" "main.c" "init.c" "debugfs.c"
    "pci.c" "pci_mac.c" "pci_mcu.c" "sdio.c" "sdio_mac.c" "sdio_mcu.c" "regs.h" "mcu.h"
)

MT7925_FILES=(
    "mt7925.h" "mac.c" "mac.h" "mcu.c" "mcu.h" "main.c" "init.c" "debugfs.c"
    "pci.c" "pci_mac.c" "pci_mcu.c" "regd.c" "regd.h" "regs.h"
)

dl_file() {
  local file=$1
  local destdir=$2
  for ref in "v${KVER}" "linux-${KVER_MINOR}.y" "v${KVER_MINOR}"; do
    if sudo curl -s -f -o "${destdir}/${file}" "${BASE_URL}/${file}?h=${ref}"; then
      return 0
    fi
  done
  echo "ERROR: Failed to download ${file}"
  return 1
}

for f in "${MT76_FILES[@]}"; do dl_file "${f}" "${DKMS_DIR}/mt76"; done
for f in "${MT7921_FILES[@]}"; do dl_file "mt7921/${f}" "${DKMS_DIR}/mt76"; done
for f in "${MT7925_FILES[@]}"; do dl_file "mt7925/${f}" "${DKMS_DIR}/mt76"; done

echo "Applying WiFi patches..."
cd "${DKMS_DIR}/mt76"

sudo sed -i 's/\r$//' "${DKMS_DIR}/"*.patch

sudo patch -l -p1 < "${DKMS_DIR}/mt7902-wifi-6.19.patch"
sudo patch -l -p1 < "${DKMS_DIR}/mt6639-wifi-init.patch"
sudo patch -l -p1 < "${DKMS_DIR}/mt6639-wifi-dma.patch"

echo "Generating Kbuild files..."
sudo tee "${DKMS_DIR}/mt76/Kbuild" > /dev/null <<'EOF'
obj-m += mt76.o
obj-m += mt76-connac-lib.o
obj-m += mt792x-lib.o
obj-m += mt7921/
obj-m += mt7925/

mt76-y := \
    mmio.o util.o trace.o dma.o mac80211.o debugfs.o eeprom.o \
    tx.o agg-rx.o mcu.o wed.o scan.o channel.o pci.o

mt76-connac-lib-y := mt76_connac_mcu.o mt76_connac_mac.o mt76_connac3_mac.o

mt792x-lib-y := mt792x_core.o mt792x_mac.o mt792x_trace.o \
        mt792x_debugfs.o mt792x_dma.o mt792x_acpi_sar.o

CFLAGS_trace.o := -I$(src)
CFLAGS_mt792x_trace.o := -I$(src)
EOF

sudo tee "${DKMS_DIR}/mt76/mt7921/Kbuild" > /dev/null <<'EOF'
obj-m += mt7921-common.o
obj-m += mt7921e.o

mt7921-common-y := mac.o mcu.o main.o init.o debugfs.o
mt7921e-y := pci.o pci_mac.o pci_mcu.o
EOF

sudo tee "${DKMS_DIR}/mt76/mt7925/Kbuild" > /dev/null <<'EOF'
obj-m += mt7925-common.o
obj-m += mt7925e.o

mt7925-common-y := mac.o mcu.o regd.o main.o init.o debugfs.o
mt7925e-y := pci.o pci_mac.o pci_mcu.o
EOF

echo "Source preparation complete! Starting DKMS build..."

sudo dkms add -m ${PKG_NAME} -v ${PKG_VER}
sudo dkms build -m ${PKG_NAME} -v ${PKG_VER}
sudo dkms install -m ${PKG_NAME} -v ${PKG_VER}

echo "DKMS installation finished successfully!"
