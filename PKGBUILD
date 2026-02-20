# Maintainer: floss@jetm.me
#
# This package requires an ASUS WiFi/BT driver ZIP to extract BT firmware.
# Download from your board's ASUS support page, e.g.:
#   https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-x870e-hero/helpdesk_download/
#   → WiFi & Bluetooth → MediaTek MT7925/MT7927 WiFi driver
# Place the ZIP (any version) in this directory before running makepkg.

pkgname=btusb-mt7927-dkms
pkgver=1.0
pkgrel=2
pkgdesc="DKMS bluetooth module and firmware for MediaTek MT7927 (MT6639)"
arch=('x86_64')
url="https://github.com/clemenscodes/linux-mediatek-mt6639-bluetooth-kernel-module"
license=('GPL-2.0-only')
depends=('dkms')
makedepends=('python')
conflicts=('btusb-mt7925-dkms')
install=btusb-mt7927-dkms.install
source=(
  'mt6639-bt-6.19.patch'
  'extract_firmware.py'
  'dkms.conf'
  'dkms-patchmodule.sh'
)
sha256sums=(
  'a112542296d49640c317a1af7bc57fcdd1b54d2cf1fe8646e4e46f736ff7bfd6'
  'bdcada7667f84479d7deda034ebb9110f3005c80be0eccc65a3110c2eaedc335'
  '35926348bd559e440a3ca5c22ff898d548529cd096f4869e6070a57b3abaf699'
  'ecc4f7251834422c0bff716c6aad9576bd7653d233d025267d2035d35b34dd05'
)

prepare() {
  local _zips=("${startdir}"/DRV_WiFi_MTK_MT7925_MT7927*.zip)

  if [[ ! -f "${_zips[0]}" ]]; then
    error "No ASUS MT7925/MT7927 WiFi driver ZIP found in PKGBUILD directory"
    msg2 "Download from your board's ASUS support page, e.g.:"
    msg2 "  https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-x870e-hero/helpdesk_download/"
    msg2 "Select: WiFi & Bluetooth → MediaTek MT7925/MT7927 WiFi driver"
    msg2 "Place the ZIP in the PKGBUILD directory, then run makepkg again."
    return 1
  fi

  if (( ${#_zips[@]} > 1 )); then
    error "Multiple ASUS driver ZIPs found — keep only one:"
    for z in "${_zips[@]}"; do msg2 "  $(basename "$z")"; done
    return 1
  fi

  msg2 "Using driver ZIP: $(basename "${_zips[0]}")"
}

build() {
  local _zips=("${startdir}"/DRV_WiFi_MTK_MT7925_MT7927*.zip)

  # Extract mtkwlan.dat from ASUS driver ZIP and extract BT firmware
  bsdtar -xf "${_zips[0]}" -C "${srcdir}" mtkwlan.dat
  python "${srcdir}/extract_firmware.py" "${srcdir}/mtkwlan.dat" "${srcdir}/BT_RAM_CODE_MT6639_2_1_hdr.bin"
}

package() {
  local _dkmsdir="${pkgdir}/usr/src/btusb-mt7927-${pkgver}"

  # Install DKMS source tree
  install -Dm644 "${srcdir}/dkms.conf" "${_dkmsdir}/dkms.conf"
  install -Dm755 "${srcdir}/dkms-patchmodule.sh" "${_dkmsdir}/dkms-patchmodule.sh"
  install -Dm644 "${srcdir}/mt6639-bt-6.19.patch" "${_dkmsdir}/mt6639-bt-6.19.patch"
  install -Dm755 "${srcdir}/extract_firmware.py" "${_dkmsdir}/extract_firmware.py"

  # Install firmware
  install -Dm644 "${srcdir}/BT_RAM_CODE_MT6639_2_1_hdr.bin" \
    "${pkgdir}/usr/lib/firmware/mediatek/mt6639/BT_RAM_CODE_MT6639_2_1_hdr.bin"
}
