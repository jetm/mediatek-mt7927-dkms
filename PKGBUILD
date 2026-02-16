# Maintainer: floss@jetm.me
#
# This package requires the ASUS WiFi/BT driver ZIP to extract BT firmware.
# Download it from:
#   https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-x870e-hero/helpdesk_download/
#   → WiFi & Bluetooth → MediaTek MT7925/MT7927 WiFi driver
# Place the ZIP in this directory before running makepkg.

pkgname=btusb-mt7927-dkms
pkgver=1.0
pkgrel=1
pkgdesc="DKMS bluetooth module and firmware for MediaTek MT7927 (MT6639)"
arch=('x86_64')
url="https://github.com/clemenscodes/linux-mediatek-mt6639-bluetooth-kernel-module"
license=('GPL-2.0-only')
depends=('dkms')
makedepends=('python')
conflicts=('btusb-mt7925-dkms')
install=btusb-mt7927-dkms.install
_asus_zip='DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip'
_asus_sha256='b377fffa28208bb1671a0eb219c84c62fba4cd6f92161b74e4b0909476307cc8'
source=(
  'mt6639-bt-6.19.patch'
  'extract_firmware.py'
  'dkms.conf'
  'dkms-patchmodule.sh'
)
sha256sums=(
  'a112542296d49640c317a1af7bc57fcdd1b54d2cf1fe8646e4e46f736ff7bfd6'
  'bdcada7667f84479d7deda034ebb9110f3005c80be0eccc65a3110c2eaedc335'
  'aeb0b98511abcda328d3104f619e9105ff27272fe84261f2f1d267a07d979560'
  'ecc4f7251834422c0bff716c6aad9576bd7653d233d025267d2035d35b34dd05'
)

prepare() {
  if [[ ! -f "${_asus_zip}" ]]; then
    error "Missing ${_asus_zip}"
    msg2 "Download from: https://rog.asus.com/motherboards/rog-crosshair/rog-crosshair-x870e-hero/helpdesk_download/"
    msg2 "Select: WiFi & Bluetooth → MediaTek MT7925/MT7927 WiFi driver"
    msg2 "Place the ZIP in the PKGBUILD directory, then run makepkg again."
    return 1
  fi

  msg2 "Verifying ${_asus_zip} checksum..."
  echo "${_asus_sha256}  ${_asus_zip}" | sha256sum -c --quiet || {
    error "Checksum mismatch for ${_asus_zip}"
    return 1
  }
}

build() {
  # Extract mtkwlan.dat from ASUS driver ZIP and extract BT firmware
  bsdtar -xf "${startdir}/${_asus_zip}" -C "${srcdir}" mtkwlan.dat
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
