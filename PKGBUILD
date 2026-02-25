# Maintainer: floss@jetm.me
#
# DKMS package for MediaTek MT7927 / MT6639 combo chip (Filogic 380):
#   - Bluetooth (MT6639 via USB): WORKING - patches btusb with MT6639 device ID
#     and installs firmware extracted from the MediaTek driver package.
#   - WiFi (MT7925e via PCIe): WORKING - patches mt7925e driver with MT6639
#     CBTOP remap, DMA ring layout, DBDC dual-band, and CNM channel context.
#     Both 2.4GHz and 5GHz tested. Tracking:
#       https://github.com/openwrt/mt76/issues/927
#
# Known hardware using MT7927/MT6639:
#   - ASUS ROG Crosshair X870E Hero (BT USB 0489:e13a, WiFi PCI 14c3:7927)
#   - Lenovo Legion Pro 7 16ARX9      (BT USB 0489:e0fa, WiFi PCI 14c3:7927)
#   - Foxconn/Azurewave modules        (WiFi PCI 14c3:6639)
#   - AMD RZ738 (MediaTek MT7927)      (WiFi PCI 14c3:0738)
#   - ASUS ROG Zephyrus G14          (aftermarket MT7927 swap)
#   - TP-Link Archer TBE550E PCIe    (E-key MT7927, extractable for laptop use)
#   - ASUS ProArt X870E              (WiFi PCI 14c3:7927)
#
# MediaTek naming is confusing. Here's the map:
#   MT7927 = combo module on the motherboard (WiFi 7 + BT 5.4, Filogic 380)
#     ├─ BT side:   internally MT6639, connects via USB (0489:e13a)
#     └─ WiFi side: architecturally MT7925, connects via PCIe (14c3:7927)
#   MT7925 = standalone WiFi 7 chip — same silicon as MT7927's WiFi half
#   MT7902 = separate WiFi 6E chip (different product line, uses mt7921 driver)
#
# MT7902 WiFi modules (mt7921e) are included because:
#   - The mt76 driver framework is shared: building mt7925e already requires the
#     mt76 core, mt76-connac-lib, and mt792x-lib modules.
#   - mt7921e (which serves MT7902) shares the exact same dependency chain.
#   - Including it costs nothing extra and helps users with MT7902 hardware who
#     need the WiFi 6E patches from lore.kernel.org (Sean Wang's series).
#
# The ASUS driver ZIP is automatically downloaded from the ASUS CDN.
# Alternatively, manually download from your board's ASUS support page:
#   https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-x870e-hero/helpdesk_download/
#   → WiFi & Bluetooth → MediaTek MT7925/MT7927 WiFi driver
# Place the ZIP in this directory before running makepkg.

pkgname=mediatek-mt7927-dkms
pkgver=2.1
pkgrel=5
# Keywords: MT7927 MT7925 MT6639 MT7902 Filogic 380 WiFi 7 Bluetooth btusb mt7925e mt7921e
pkgdesc="DKMS Bluetooth (MT6639) and WiFi (MT7925e/MT7902) modules for MediaTek MT7927 Filogic 380"
arch=('x86_64')
url="https://github.com/jetm/mediatek-mt7927-dkms"
license=('GPL-2.0-only')
depends=('dkms')
makedepends=('python' 'curl')
provides=('mediatek-mt6639-bt-dkms' 'mediatek-mt7925-wifi-dkms')
conflicts=('btusb-mt7925-dkms' 'btusb-mt7927-dkms')
install=mediatek-mt7927-dkms.install

# NOTE: Newer firmware exists (WLAN 5.7.3.5312, 2026-01-23) but is only available
# as a driver-only package from station-drivers.com - no ASUS consumer ZIP on CDN yet.
# When ASUS publishes a newer ZIP, update _driver_filename and _driver_sha256 below.
#   https://station-drivers.com/index.php/en/component/remository/Drivers/MediaTek/MediaTek-MT7927-MT7925-Wireless-Lan/
_driver_filename='DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip'
_driver_sha256='b377fffa28208bb1671a0eb219c84c62fba4cd6f92161b74e4b0909476307cc8'

# Kernel version the mt76 WiFi patches target
_mt76_kver='6.19.3'

source=(
  'mt6639-bt-6.19.patch'
  'mt7902-wifi-6.19.patch'
  'mt6639-wifi-init.patch'
  'mt6639-wifi-dma.patch'
  'extract_firmware.py'
  'dkms.conf'
  'dkms-patchmodule.sh'
)
sha256sums=('c4187bd88174a96f6ec912963be2a472bc77989d368f6eda28fc40b04747d64f'
            '736d3fcd477e380a1b3e9f2a3d424ec4473535ead44e8c8ac8f515d886b8fdfa'
            'a54284178855f1a9120d3d36f76a60cb83491097da86eb316b4f557b9db04476'
            '450004fc75ec076217a1bac4dc85abe68920d0377a4248d01cbe5f8c8f98819a'
            'e94c77671abe0d589faa01c1a9451f626b1fc45fb04f765b43fd0e126d01a436'
            '9f4a0d13e782582c3f0cf59f66cfa0084d08473ada76067dbcb85ee8d9988b26'
            '72216f5a821858fac0d616c8b3c12fb5ee09887c809e3815c6dbaace5d3b557f')

# Auto-download via ASUS CDN token API.
# Based on code by Eadinator: https://github.com/openwrt/mt76/issues/927#issuecomment-3936022734
_download_driver_zip() {
  local _token_url="https://cdnta.asus.com/api/v1/TokenHQ?filePath=https:%2F%2Fdlcdnta.asus.com%2Fpub%2FASUS%2Fmb%2F08WIRELESS%2F${_driver_filename}%3Fmodel%3DROG%2520CROSSHAIR%2520X870E%2520HERO&systemCode=rog"

  echo "Fetching download token from ASUS CDN..."
  local _json
  _json="$(curl -sf "${_token_url}" -X POST -H 'Origin: https://rog.asus.com')"

  if [[ -z "${_json}" ]]; then
    echo >&2 "Failed to retrieve download token from ASUS CDN"
    return 1
  fi

  local _expires _signature _key_pair_id
  _expires=${_json#*\"expires\":\"}
  _expires=${_expires%%\"*}

  _signature=${_json#*\"signature\":\"}
  _signature=${_signature%%\"*}

  _key_pair_id=${_json#*\"keyPairId\":\"}
  _key_pair_id=${_key_pair_id%%\"*}

  local _download_url="https://dlcdnta.asus.com/pub/ASUS/mb/08WIRELESS/${_driver_filename}?model=ROG%20CROSSHAIR%20X870E%20HERO&Signature=${_signature}&Expires=${_expires}&Key-Pair-Id=${_key_pair_id}"

  echo "Downloading ${_driver_filename}..."
  if ! curl -L -f -o "${SRCDEST:-.}/${_driver_filename}" "${_download_url}"; then
    echo >&2 "Failed to download driver ZIP"
    return 1
  fi
}

_download_mt76_source() {
  local _kver="$1"
  local _destdir="$2"

  echo "Downloading mt76 source for kernel v${_kver}..."

  local _base="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/net/wireless/mediatek/mt76"

  # Try exact version first, fall back to major.minor
  local _major_minor=${_kver%.*}
  local _refs=(
    "v${_kver}"
    "linux-${_major_minor}.y"
    "v${_major_minor}"
  )

  _dl_mt76_file() {
    local file="$1" destdir="$2"
    for ref in "${_refs[@]}"; do
      if curl -sS -f -o "${destdir}/${file}" "${_base}/${file}?h=${ref}"; then
        return 0
      fi
    done
    return 1
  }

  mkdir -p "${_destdir}/mt7921" "${_destdir}/mt7925"

  # Core mt76 files
  local _mt76_files=(
    mt76.h mt76_connac.h mt76_connac2_mac.h mt76_connac3_mac.h
    mt76_connac_mcu.h mt76_connac_mcu.c mt76_connac_mac.c mt76_connac3_mac.c
    mmio.c util.c util.h trace.c trace.h dma.c dma.h mac80211.c
    debugfs.c eeprom.c tx.c agg-rx.c mcu.c wed.c scan.c channel.c pci.c
    testmode.h
    mt792x.h mt792x_regs.h mt792x_core.c mt792x_mac.c
    mt792x_trace.c mt792x_trace.h mt792x_debugfs.c mt792x_dma.c
    mt792x_acpi_sar.c mt792x_acpi_sar.h
    sdio.h
  )

  # mt7921 files
  local _mt7921_files=(
    mt7921.h mac.c mcu.c main.c init.c debugfs.c
    pci.c pci_mac.c pci_mcu.c sdio.c sdio_mac.c sdio_mcu.c
    regs.h mcu.h
  )

  # mt7925 files
  local _mt7925_files=(
    mt7925.h mac.c mac.h mcu.c mcu.h main.c init.c debugfs.c
    pci.c pci_mac.c pci_mcu.c
    regd.c regd.h regs.h
  )

  for file in "${_mt76_files[@]}"; do
    if ! _dl_mt76_file "$file" "${_destdir}"; then
      echo >&2 "Failed to download mt76/${file}"
      return 1
    fi
    echo "  ${file}"
  done

  for file in "${_mt7921_files[@]}"; do
    if ! _dl_mt76_file "mt7921/${file}" "${_destdir}"; then
      echo >&2 "Failed to download mt76/mt7921/${file}"
      return 1
    fi
    echo "  mt7921/${file}"
  done

  for file in "${_mt7925_files[@]}"; do
    if ! _dl_mt76_file "mt7925/${file}" "${_destdir}"; then
      echo >&2 "Failed to download mt76/mt7925/${file}"
      return 1
    fi
    echo "  mt7925/${file}"
  done
}

prepare() {
  local _zips=("${SRCDEST:-.}"/DRV_WiFi_MTK_MT7925_MT7927*.zip)

  # Auto-download if no ZIP found
  if [[ ! -f "${_zips[0]}" ]]; then
    _download_driver_zip
    _zips=("${SRCDEST:-.}/${_driver_filename}")
  fi

  if [[ ! -f "${_zips[0]}" ]]; then
    echo >&2 "No ASUS MT7925/MT7927 WiFi driver ZIP available"
    echo "Download manually from your board's ASUS support page:"
    echo "  https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-x870e-hero/helpdesk_download/"
    echo "Select: WiFi & Bluetooth → MediaTek MT7925/MT7927 WiFi driver"
    echo "Place the ZIP in the PKGBUILD directory, then run makepkg again."
    return 1
  fi

  if (( ${#_zips[@]} > 1 )); then
    echo >&2 "Multiple ASUS driver ZIPs found — keep only one:"
    for z in "${_zips[@]}"; do echo "  $(basename "$z")"; done
    return 1
  fi

  # Verify integrity if using the known version
  if [[ "$(basename "${_zips[0]}")" == "${_driver_filename}" ]]; then
    echo "Verifying ${_driver_filename}..."
    echo "${_driver_sha256}  ${_zips[0]}" | sha256sum -c - || {
      echo >&2 "SHA256 mismatch for ${_driver_filename}"
      return 1
    }
  fi

  echo "Using driver ZIP: $(basename "${_zips[0]}")"
}

build() {
  local _zips=("${SRCDEST:-.}"/DRV_WiFi_MTK_MT7925_MT7927*.zip)

  # Extract BT + WiFi firmware from ASUS driver ZIP
  bsdtar -xf "${_zips[0]}" -C "${srcdir}" mtkwlan.dat
  python "${srcdir}/extract_firmware.py" "${srcdir}/mtkwlan.dat" "${srcdir}/firmware"

  # Download mt76 source and apply WiFi patches
  _download_mt76_source "${_mt76_kver}" "${srcdir}/mt76"

  cd "${srcdir}/mt76"

  echo "Applying mt7902-wifi-6.19.patch..."
  patch -p1 < "${srcdir}/mt7902-wifi-6.19.patch"

  echo "Applying mt6639-wifi-init.patch..."
  patch -p1 < "${srcdir}/mt6639-wifi-init.patch"

  echo "Applying mt6639-wifi-dma.patch..."
  patch -p1 < "${srcdir}/mt6639-wifi-dma.patch"

  # Create Kbuild files for out-of-tree mt76 build
  cat > "${srcdir}/mt76/Kbuild" <<'EOF'
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

  cat > "${srcdir}/mt76/mt7921/Kbuild" <<'EOF'
obj-m += mt7921-common.o
obj-m += mt7921e.o

mt7921-common-y := mac.o mcu.o main.o init.o debugfs.o
mt7921e-y := pci.o pci_mac.o pci_mcu.o
EOF

  cat > "${srcdir}/mt76/mt7925/Kbuild" <<'EOF'
obj-m += mt7925-common.o
obj-m += mt7925e.o

mt7925-common-y := mac.o mcu.o regd.o main.o init.o debugfs.o
mt7925e-y := pci.o pci_mac.o pci_mcu.o
EOF

  echo "mt76 source prepared with MT7902 + MT7927 patches"
}

package() {
  local _dkmsdir="${pkgdir}/usr/src/mediatek-mt7927-${pkgver}"

  # Install DKMS config and scripts
  install -Dm644 "${srcdir}/dkms.conf" "${_dkmsdir}/dkms.conf"
  install -Dm755 "${srcdir}/dkms-patchmodule.sh" "${_dkmsdir}/dkms-patchmodule.sh"
  install -Dm644 "${srcdir}/mt6639-bt-6.19.patch" "${_dkmsdir}/mt6639-bt-6.19.patch"
  install -Dm644 "${srcdir}/mt6639-wifi-init.patch" "${_dkmsdir}/mt6639-wifi-init.patch"
  install -Dm755 "${srcdir}/extract_firmware.py" "${_dkmsdir}/extract_firmware.py"

  # Install patched mt76 WiFi source tree
  install -dm755 "${_dkmsdir}/mt76/mt7921" "${_dkmsdir}/mt76/mt7925"
  install -m644 "${srcdir}/mt76"/*.{c,h} "${_dkmsdir}/mt76/"
  install -m644 "${srcdir}/mt76/Kbuild" "${_dkmsdir}/mt76/"
  install -m644 "${srcdir}/mt76/mt7921"/*.{c,h} "${_dkmsdir}/mt76/mt7921/"
  install -m644 "${srcdir}/mt76/mt7921/Kbuild" "${_dkmsdir}/mt76/mt7921/"
  install -m644 "${srcdir}/mt76/mt7925"/*.{c,h} "${_dkmsdir}/mt76/mt7925/"
  install -m644 "${srcdir}/mt76/mt7925/Kbuild" "${_dkmsdir}/mt76/mt7925/"

  # Install BT firmware
  install -Dm644 "${srcdir}/firmware/BT_RAM_CODE_MT6639_2_1_hdr.bin" \
    "${pkgdir}/usr/lib/firmware/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin"

  # Install WiFi firmware
  install -Dm644 "${srcdir}/firmware/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin" \
    "${pkgdir}/usr/lib/firmware/mediatek/mt7927/WIFI_MT6639_PATCH_MCU_2_1_hdr.bin"
  install -Dm644 "${srcdir}/firmware/WIFI_RAM_CODE_MT6639_2_1.bin" \
    "${pkgdir}/usr/lib/firmware/mediatek/mt7927/WIFI_RAM_CODE_MT6639_2_1.bin"
}
