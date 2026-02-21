# Maintainer: floss@jetm.me
#
# DKMS package for MediaTek MT7927 / MT6639 combo chip (Filogic 380):
#   - Bluetooth (MT6639 via USB): WORKING — patches btusb with MT6639 device ID
#     and installs firmware extracted from the MediaTek driver package.
#   - WiFi (MT7925e via PCIe): NOT YET WORKING — driver binds but firmware init
#     fails ("patch semaphore" timeout). MT7927 WiFi requires DMA init changes
#     not yet in mainline mt76. Tracking:
#       https://github.com/openwrt/mt76/issues/927
#       https://github.com/ehausig/mt7927
#
# Known hardware using MT7927/MT6639:
#   - ASUS ROG Crosshair X870E Hero (BT USB 0489:e13a, WiFi PCI 14c3:7927)
#   - Lenovo Legion Pro 7 16ARX9      (BT USB 0489:e0fa, WiFi PCI 14c3:7927)
#   - Foxconn/Azurewave modules        (WiFi PCI 14c3:6639)
#   - AMD RZ738 (MediaTek MT7927)      (WiFi PCI 14c3:0738)
#
# MediaTek naming is confusing. Here's the map:
#   MT7927 = combo module on the motherboard (WiFi 7 + BT 5.4, Filogic 380)
#     ├─ BT side:   internally MT6639, connects via USB
#     └─ WiFi side: architecturally MT7925, connects via PCIe
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
# Firmware sourcing (in priority order):
#   1. Pre-placed BT_RAM_CODE_MT6639_2_1_hdr.bin — skip extraction entirely
#   2. Pre-placed mtkwlan.dat — extract firmware from it directly
#   3. Any MediaTek MT7925/MT7927 WiFi driver ZIP in this directory
#   4. Auto-download from ASUS CDN (fallback)
#
# Firmware can come from any MediaTek WiFi driver package containing mtkwlan.dat.
# Known sources:
#   - ASUS: board support page → WiFi & Bluetooth → MediaTek MT7925/MT7927
#   - Station-Drivers: https://www.station-drivers.com (search "MT7925" or "MT7927")
#   - Lenovo/Foxconn: OEM driver packages (extract mtkwlan.dat manually)
# Place the firmware blob, mtkwlan.dat, or driver ZIP in this directory before
# running makepkg.

pkgname=mediatek-mt7927-dkms
pkgver=1.0
pkgrel=2
# Keywords: MT7927 MT7925 MT6639 MT7902 RZ738 Filogic 380 WiFi 7 Bluetooth btusb mt7925e mt7921e
pkgdesc="DKMS Bluetooth and WiFi modules for MediaTek MT7927/MT6639 Filogic 380 (multi-device)"
arch=('x86_64')
url="https://github.com/clemenscodes/linux-mediatek-mt6639-bluetooth-kernel-module"
license=('GPL-2.0-only')
depends=('dkms')
makedepends=('python' 'curl')
provides=('mediatek-mt6639-bt-dkms' 'mediatek-mt7925-wifi-dkms')
conflicts=('btusb-mt7925-dkms' 'btusb-mt7927-dkms')
install=mediatek-mt7927-dkms.install

_driver_filename='DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip'
_driver_sha256='b377fffa28208bb1671a0eb219c84c62fba4cd6f92161b74e4b0909476307cc8'

# Kernel version the mt76 WiFi patches target
_mt76_kver='6.19.3'

source=(
  'mt6639-bt-6.19.patch'
  'mt7902-wifi-6.19.patch'
  'mt7927-wifi-pci-id.patch'
  'extract_firmware.py'
  'dkms.conf'
  'dkms-patchmodule.sh'
)
sha256sums=('c4187bd88174a96f6ec912963be2a472bc77989d368f6eda28fc40b04747d64f'
            'SKIP'
            'SKIP'
            'bdcada7667f84479d7deda034ebb9110f3005c80be0eccc65a3110c2eaedc335'
            'SKIP'
            'SKIP')

# Auto-download via ASUS CDN token API.
# Based on code by Eadinator: https://github.com/openwrt/mt76/issues/927#issuecomment-3936022734
_download_driver_zip() {
  local _token_url="https://cdnta.asus.com/api/v1/TokenHQ?filePath=https:%2F%2Fdlcdnta.asus.com%2Fpub%2FASUS%2Fmb%2F08WIRELESS%2F${_driver_filename}%3Fmodel%3DROG%2520CROSSHAIR%2520X870E%2520HERO&systemCode=rog"

  msg2 "Fetching download token from ASUS CDN..."
  local _json
  _json="$(curl -sf "${_token_url}" -X POST -H 'Origin: https://rog.asus.com')"

  if [[ -z "${_json}" ]]; then
    error "Failed to retrieve download token from ASUS CDN"
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

  msg2 "Downloading ${_driver_filename}..."
  if ! curl -L -f -o "${startdir}/${_driver_filename}" "${_download_url}"; then
    error "Failed to download driver ZIP"
    return 1
  fi
}

_download_mt76_source() {
  local _kver="$1"
  local _destdir="$2"

  msg2 "Downloading mt76 source for kernel v${_kver}..."

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
      error "Failed to download mt76/${file}"
      return 1
    fi
    msg2 "  ${file}"
  done

  for file in "${_mt7921_files[@]}"; do
    if ! _dl_mt76_file "mt7921/${file}" "${_destdir}"; then
      error "Failed to download mt76/mt7921/${file}"
      return 1
    fi
    msg2 "  mt7921/${file}"
  done

  for file in "${_mt7925_files[@]}"; do
    if ! _dl_mt76_file "mt7925/${file}" "${_destdir}"; then
      error "Failed to download mt76/mt7925/${file}"
      return 1
    fi
    msg2 "  mt7925/${file}"
  done
}

prepare() {
  local _fw_bin="${startdir}/BT_RAM_CODE_MT6639_2_1_hdr.bin"
  local _mtkwlan="${startdir}/mtkwlan.dat"

  # Priority 1: pre-placed firmware blob
  if [[ -f "${_fw_bin}" ]]; then
    msg2 "Using pre-placed firmware: BT_RAM_CODE_MT6639_2_1_hdr.bin"
    cp "${_fw_bin}" "${srcdir}/BT_RAM_CODE_MT6639_2_1_hdr.bin"
    return 0
  fi

  # Priority 2: pre-placed mtkwlan.dat
  if [[ -f "${_mtkwlan}" ]]; then
    msg2 "Using pre-placed mtkwlan.dat — will extract firmware in build()"
    return 0
  fi

  # Priority 3: any MediaTek WiFi driver ZIP in the directory
  local _zips=()
  for pattern in "${startdir}"/DRV_WiFi_MTK_MT7925_MT7927*.zip \
                 "${startdir}"/*MT7927*.zip \
                 "${startdir}"/*MT7925*.zip; do
    for f in $pattern; do
      [[ -f "$f" ]] && _zips+=("$f")
    done
  done
  # Deduplicate (a file may match multiple globs)
  if (( ${#_zips[@]} > 0 )); then
    local -A _seen
    local _unique=()
    for z in "${_zips[@]}"; do
      local _base
      _base="$(realpath "$z")"
      if [[ -z "${_seen[$_base]+x}" ]]; then
        _seen[$_base]=1
        _unique+=("$z")
      fi
    done
    _zips=("${_unique[@]}")
  fi

  # Priority 4: auto-download from ASUS CDN
  if (( ${#_zips[@]} == 0 )); then
    _download_driver_zip
    _zips=("${startdir}/${_driver_filename}")
  fi

  if [[ ! -f "${_zips[0]}" ]]; then
    error "No MT6639 firmware source available."
    msg2 "Provide one of the following in the PKGBUILD directory:"
    msg2 "  1. BT_RAM_CODE_MT6639_2_1_hdr.bin (firmware blob directly)"
    msg2 "  2. mtkwlan.dat (from any MediaTek WiFi driver package)"
    msg2 "  3. A MediaTek MT7925/MT7927 WiFi driver ZIP"
    msg2 ""
    msg2 "Sources: ASUS board support page, Station-Drivers.com, or OEM driver package."
    return 1
  fi

  if (( ${#_zips[@]} > 1 )); then
    error "Multiple driver ZIPs found — keep only one:"
    for z in "${_zips[@]}"; do msg2 "  $(basename "$z")"; done
    return 1
  fi

  # Verify integrity if using the known ASUS version
  if [[ "$(basename "${_zips[0]}")" == "${_driver_filename}" ]]; then
    msg2 "Verifying ${_driver_filename}..."
    echo "${_driver_sha256}  ${_zips[0]}" | sha256sum -c - || {
      error "SHA256 mismatch for ${_driver_filename}"
      return 1
    }
  fi

  msg2 "Using driver ZIP: $(basename "${_zips[0]}")"
}

build() {
  # Obtain BT firmware blob (prepare() already handled priority 1: pre-placed blob)
  if [[ ! -f "${srcdir}/BT_RAM_CODE_MT6639_2_1_hdr.bin" ]]; then
    local _mtkwlan="${srcdir}/mtkwlan.dat"

    # Priority 2: pre-placed mtkwlan.dat
    if [[ -f "${startdir}/mtkwlan.dat" ]]; then
      cp "${startdir}/mtkwlan.dat" "${_mtkwlan}"
    fi

    # Priority 3/4: extract mtkwlan.dat from driver ZIP
    if [[ ! -f "${_mtkwlan}" ]]; then
      local _zips=()
      for pattern in "${startdir}"/DRV_WiFi_MTK_MT7925_MT7927*.zip \
                     "${startdir}"/*MT7927*.zip \
                     "${startdir}"/*MT7925*.zip; do
        for f in $pattern; do
          [[ -f "$f" ]] && _zips+=("$f") && break 2
        done
      done
      msg2 "Extracting mtkwlan.dat from $(basename "${_zips[0]}")..."
      bsdtar -xf "${_zips[0]}" -C "${srcdir}" mtkwlan.dat
    fi

    msg2 "Extracting BT firmware from mtkwlan.dat..."
    python "${srcdir}/extract_firmware.py" "${_mtkwlan}" "${srcdir}/BT_RAM_CODE_MT6639_2_1_hdr.bin"
  fi

  # Download mt76 source and apply WiFi patches
  _download_mt76_source "${_mt76_kver}" "${srcdir}/mt76"

  cd "${srcdir}/mt76"

  msg2 "Applying mt7902-wifi-6.19.patch..."
  patch -p1 < "${srcdir}/mt7902-wifi-6.19.patch"

  msg2 "Applying mt7927-wifi-pci-id.patch..."
  patch -p1 < "${srcdir}/mt7927-wifi-pci-id.patch"

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

  msg2 "mt76 source prepared with MT7902 + MT7927 patches"
}

package() {
  local _dkmsdir="${pkgdir}/usr/src/mediatek-mt7927-${pkgver}"

  # Install DKMS config and scripts
  install -Dm644 "${srcdir}/dkms.conf" "${_dkmsdir}/dkms.conf"
  install -Dm755 "${srcdir}/dkms-patchmodule.sh" "${_dkmsdir}/dkms-patchmodule.sh"
  install -Dm644 "${srcdir}/mt6639-bt-6.19.patch" "${_dkmsdir}/mt6639-bt-6.19.patch"
  install -Dm644 "${srcdir}/mt7927-wifi-pci-id.patch" "${_dkmsdir}/mt7927-wifi-pci-id.patch"
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
  install -Dm644 "${srcdir}/BT_RAM_CODE_MT6639_2_1_hdr.bin" \
    "${pkgdir}/usr/lib/firmware/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin"
}
