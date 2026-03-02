#!/bin/bash
set -e

# Detect current kernel version
KVER_FULL=$(uname -r)
KVER_BASE=$(echo $KVER_FULL | cut -d'-' -f1)
KVER_MINOR=$(echo $KVER_BASE | cut -d'.' -f1,2)

PKG_NAME="mediatek-bt-only"
PKG_VER="1.5"
DKMS_DIR="/usr/src/${PKG_NAME}-${PKG_VER}"
BASE_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/bluetooth"

echo "=== MT7927 Bluetooth Driver Installation Script ==="

# 1. FIRMWARE PLACEMENT
echo "[1/4] Setting up Bluetooth Firmware..."
sudo mkdir -p /lib/firmware/mediatek
BT_FILE=$(find ./firmware/bluetooth -name "BT_RAM_CODE_MT6639_2_1_hdr.bin" | head -n 1)

if [ -n "$BT_FILE" ]; then
    sudo cp "$BT_FILE" /lib/firmware/mediatek/
    sudo ln -sf /lib/firmware/mediatek/BT_RAM_CODE_MT6639_2_1_hdr.bin /lib/firmware/mediatek/BT_RAM_CODE_MT7927_2_1_hdr.bin
    sudo ln -sf /lib/firmware/mediatek/BT_RAM_CODE_MT6639_2_1_hdr.bin /lib/firmware/mediatek/BT_RAM_CODE_MT7925_2_1_hdr.bin
    echo "Bluetooth firmware placed and symlinked."
else
    echo "!!! ERROR: BT_RAM_CODE_MT6639_2_1_hdr.bin not found."
    exit 1
fi

# 2. DKMS CLEANUP
echo "[2/4] Preparing DKMS Environment..."
sudo dkms remove -m ${PKG_NAME} -v ${PKG_VER} --all 2>/dev/null || true
sudo rm -rf "${DKMS_DIR}"
sudo mkdir -p "${DKMS_DIR}/drivers/bluetooth"

# 3. KERNEL SOURCE DOWNLOADER
dl_file() {
  local filename=$1
  for ref in "v${KVER_BASE}" "linux-${KVER_MINOR}.y" "v${KVER_MINOR}" "master"; do
    if sudo curl -s -f -o "${DKMS_DIR}/drivers/bluetooth/${filename}" "${BASE_URL}/${filename}?h=${ref}"; then 
       return 0
    fi
  done
  echo "ERROR: Failed to download ${filename}"; return 1
}

echo "[3/4] Downloading Bluetooth Sources..."
for f in "btusb.c" "btmtk.c" "btmtk.h" "btintel.h" "btbcm.h" "btrtl.h"; do dl_file "$f"; done

echo "Applying Source Compatibility & Device ID Fixes..."
# 1. Add your ROG board's ID (0489:e13a) so the driver claims the card
sudo sed -i '/{ USB_DEVICE(0x0489, 0xe133) }/a \	{ USB_DEVICE(0x0489, 0xe13a), .driver_info = BTUSB_MEDIATEK | BTUSB_WIDEBAND_SPEECH | BTUSB_VALID_LE_STATES },' "${DKMS_DIR}/drivers/bluetooth/btusb.c"

# 2. Fix the kmalloc_obj / kzalloc_obj errors found in newer kernels
sudo sed -i 's/kmalloc_obj(\*\(.*\))/kmalloc(sizeof(*\1), GFP_KERNEL)/g' "${DKMS_DIR}/drivers/bluetooth/btmtk.c" || true
sudo sed -i 's/kmalloc_obj(\*\(.*\))/kmalloc(sizeof(*\1), GFP_KERNEL)/g' "${DKMS_DIR}/drivers/bluetooth/btusb.c" || true
sudo sed -i 's/kzalloc_obj(\*\(.*\))/kzalloc(sizeof(*\1), GFP_KERNEL)/g' "${DKMS_DIR}/drivers/bluetooth/btusb.c" || true

# 3. Fix the "hci_discovery_active" undefined error
sudo sed -i 's/hci_discovery_active(hdev)/ (hdev->discovery.state != DISCOVERY_STOPPED) /g' "${DKMS_DIR}/drivers/bluetooth/btusb.c" || true

echo "Applying Bluetooth Patch..."
if [ -f "mt6639-bt-6.19.patch" ]; then
    sudo cp mt6639-bt-6.19.patch "${DKMS_DIR}/"
    cd "${DKMS_DIR}"
    sudo patch -p1 < mt6639-bt-6.19.patch
else
    echo "Note: mt6639-bt-6.19.patch not found in current directory. Skipping local patch."
fi

echo "Generating Build Files..."
sudo tee "${DKMS_DIR}/Kbuild" > /dev/null <<'EOF'
obj-m += drivers/bluetooth/
EOF

sudo tee "${DKMS_DIR}/drivers/bluetooth/Kbuild" > /dev/null <<'EOF'
obj-m += btusb.o btmtk.o
ccflags-y := -I$(src)
EOF

sudo tee "${DKMS_DIR}/dkms.conf" > /dev/null <<EOF
PACKAGE_NAME="${PKG_NAME}"
PACKAGE_VERSION="${PKG_VER}"
BUILT_MODULE_NAME[0]="btusb"
BUILT_MODULE_LOCATION[0]="drivers/bluetooth/"
DEST_MODULE_LOCATION[0]="/updates/dkms/"
BUILT_MODULE_NAME[1]="btmtk"
BUILT_MODULE_LOCATION[1]="drivers/bluetooth/"
DEST_MODULE_LOCATION[1]="/updates/dkms/"
AUTOINSTALL="yes"
EOF

# 4. INSTALL
echo "[4/4] Installing Bluetooth Driver..."
sudo dkms add -m ${PKG_NAME} -v ${PKG_VER}
sudo dkms build -m ${PKG_NAME} -v ${PKG_VER}
sudo dkms install -m ${PKG_NAME} -v ${PKG_VER}
sudo update-initramfs -u

echo "=================================================================="
echo "SUCCESS! Bluetooth driver built."
echo "=================================================================="
