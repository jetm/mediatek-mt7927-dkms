# Ubuntu 22.04 Bluetooth backport for Linux 6.8

This work backports the Linux 7.2 `btusb`/`btmtk` drivers with driver-local
compatibility changes. It does not backport the Bluetooth core or add Linux
6.8 support to the WiFi modules. The upstream 6.17+ support statement is unchanged.

## Implementation

- `BUILD_WIFI=no` prepares and stages Bluetooth independently of mt76.
  DKMS module declarations and MAKE follow the selected module groups.
- Both the default and Bluetooth-only packages require DKMS to provide the
  target `kernelver`; a missing value is an error rather than a fallback to
  the running kernel. CLEAN is not assigned because DKMS 3.x deprecated it
  and no longer executes it.
- `PREPARE_FIRMWARE=no` allows source-only builds and staging; this option does
  not supply the firmware needed by the device.
- Compatibility patches handle unaligned headers, the 6.8 quirk bitmap, the
  optional HCI driver command interface and QCA diagnostic packet reception.
- Firmware header/section/payload bounds are checked. Runtime PM references
  cover the WMT command and reply, and reset paths release their references.
  Failed WMT transactions cancel control receive polling and release events.
  The payload-bounds, usb-pm and wmt-pm patches apply to every build through
  the `mt6639-bt-compat-*.patch` glob, not only the Linux 6.8 path.
- `btmtk.mt6639_diagnostics` defaults to false. Enabling it logs bounded MT6639
  initialization details and suppresses automatic hardware reset for diagnosis.
  It is not the recommended operating mode or a claim that reset is unnecessary.
- `BT_MODULE_VERSION` optionally assigns a numeric local MODULE_VERSION through
  a generated header. Without it, upstream versions remain unchanged. This
  avoids DKMS 2.8.7 skipping replacement because module versions match.
- `DKMS_KERNEL_PATTERN` optionally restricts a staged package to tested kernels.
  `DKMS_AUTOINSTALL` controls the staged package's AUTOINSTALL setting.

## Reproducible local build

Run from the repository root with the kernel tarball specified by PKGBUILD
available. No sudo is required for source preparation, compilation or staging.

```bash
make build-bluetooth BUILD_WIFI=no PREPARE_FIRMWARE=no \
  SRCDIR=_build-bt-local TARGET_KERNEL=6.8.0-138-generic \
  CC=x86_64-linux-gnu-gcc-12

make install BUILD_WIFI=no PREPARE_FIRMWARE=no SRCDIR=_build-bt-package \
  VERSION=2.16.68.1 PKGBUILD_VER=2.16.68.1 BT_MODULE_VERSION=2.16.68.1 \
  DKMS_KERNEL_PATTERN='^6[.]8[.]0-138-generic$' DKMS_AUTOINSTALL=yes \
  DESTDIR="$PWD/_build-install-local"
```

The staged local package is Bluetooth-only and deliberately restricted to the
verified ABI. Other ABIs are excluded, not automatically supported. Automatic
installation was checked at the configuration level; an actual autoinstall run
has not been tested. The explicit DKMS build/install path was tested.

## Sources and firmware

Driver source: Linux 7.2, as pinned by PKGBUILD. SHA-256:
`f9fef3d14c0df53819026f4be74459835c2a0b0dcbf5b5bbd9ea19f0829402b3`.
Target API comparison used Ubuntu linux-hwe-6.8
`6.8.0-138.138~22.04.1` headers, Module.symvers and Bluetooth sources.
Upstream copyright and licenses are retained in the drivers and patches.

The locally tested firmware was extracted from ASUS's
`DRV_WiFi_MTK_MT7925_MT7927_TP_W11_64_V5603998_20250709R.zip`:

| Artifact | SHA-256 |
| --- | --- |
| Driver ZIP | `b377fffa28208bb1671a0eb219c84c62fba4cd6f92161b74e4b0909476307cc8` |
| `BT_RAM_CODE_MT6639_2_1_hdr.bin` (688341 bytes) | `669c5c99a0c59c85c1285d3d1b8b31915c2d31341a2244f4eddcbfd60ffbbc76` |

The request path is `mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin`.
Use the existing download/extraction workflow with `--bluetooth-only` if needed.
No firmware binary is committed. A traceable vendor source does not establish
redistribution permission; that permission has not been confirmed.

## Observed validation (2026-09-26)

MSI B850MPOWER, Bluetooth USB `0489:e110`, Ubuntu 22.04.5,
`6.8.0-138-generic`, Secure Boot enabled, existing enrolled MOK. Local package
`2.16.68.1` was built with GCC 12.3 and installed by the user.

| Check | Result and scope |
| --- | --- |
| Fresh patch application and compilation | Passed; no rejects, target modpost/vermagic/dependencies checked; BTF skipped without vmlinux |
| Default module versions | Compiled; btusb 0.8 and btmtk 0.1 retained |
| DKMS configuration | Default, Bluetooth-only, WiFi-only, 7.1 gate, explicit Bluetooth opt-in and all-disabled rejection checked |
| Signing and installation | Both modules signed by existing MOK; explicit install without force copied modules to updates/dkms |
| Actual loaded identity | MODULE_VERSION 2.16.68.1; disk and loaded srcversion matched |
| Normal-mode initialization | Passed with diagnostics disabled; controller powered |
| Scan | Started, discovered eight devices, stopped successfully in formal normal mode |
| Initial pairing | QC45 pairing passed on the earlier diagnostic candidate; fresh pairing on formal normal mode was not repeated |
| Existing pairing and A2DP | QC45 pairing preserved; connection and actual playback confirmed by user |
| Ordinary reboot | Passed; initialization about 2.71 seconds, connection and playback normal |
| Power-disconnected cold boot | Passed; initialization about 19.37 seconds, connection and playback normal |
| One deep/S3 suspend/resume | Passed; initialization about 2.68 seconds; user confirmed automatic reconnection and actual playback |
| Other devices after resume | User confirmed wired network, display and hardware monitoring normal; their configuration was not changed |
| Firmware extractor | Valid/truncated/out-of-range payload checks passed |

Resume logs contain xHCI reinitialization, USB resets and APIC warnings. They
are recorded despite the successful functional test; no cause was established.
The Enhanced Setup Synchronous Connection warning also remains; HFP/microphone
was not tested. Do not infer long-term or repeated sleep stability from one test.
Exact playback duration was not measured. Disk hibernation, s2idle, other hardware,
other kernel ABIs (including a newer-kernel compile regression), actual
AUTOINSTALL execution and formal-package uninstall/reinstall remain unverified.

## Installation and recovery

System installation/reloading affects every device using btusb/btmtk. Save
existing package/firmware state and keep the distribution modules and a bootable
kernel. Use an independent local package version; retain any previous candidate
and its signed build as a fallback. The package above does not install firmware.

After copying the staged source into `/usr/src/mediatek-mt7927-2.16.68.1`, use:

```bash
sudo dkms add -m mediatek-mt7927 -v 2.16.68.1 -k 6.8.0-138-generic
sudo dkms build -m mediatek-mt7927 -v 2.16.68.1 -k 6.8.0-138-generic
```

Check both built modules' signer and vermagic before installation. DKMS's success
exit alone does not prove signing succeeded. Keep Secure Boot enabled and use
the existing enrolled key; never copy a private key into this repository.

After a controlled unload and any necessary previous-package uninstall, install
with `sudo dkms install -m mediatek-mt7927 -v 2.16.68.1 -k 6.8.0-138-generic`,
then depmod. Confirm updates/dkms paths, versions and signers before loading.
Compare disk and `/sys/module/{btusb,btmtk}/srcversion` after loading and confirm
the diagnostic parameter is N. Update initramfs before testing reboot.

To restore distribution modules, stop Bluetooth, unload btusb/btmtk, uninstall
only this project's active package for the target ABI, run depmod and update
initramfs. Confirm module paths resolve to kernel/drivers/bluetooth. Do not delete
distribution modules or touch unrelated DKMS projects. The distribution modules
are a recovery baseline, not a working MT6639 solution on this ABI.

On this host DKMS 2.8.7 uninstall completed but returned 1 through a trailing
conditional expression. Inspect the actual package state and module paths before
proceeding; do not blindly suppress errors or repeat the uninstall. A USB device
that disappears after failure may require power removal once a safe recovery
state is established; avoid repeated module reloads.
