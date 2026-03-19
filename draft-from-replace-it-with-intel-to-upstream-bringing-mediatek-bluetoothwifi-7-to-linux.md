# From "Replace It with Intel" to Upstream: Bringing MediaTek Bluetooth/WiFi 7 to Linux

## TL;DR

MediaTek's MT7927 WiFi 7 chip shipped on 15+ flagship products from ASUS, Gigabyte, Lenovo, MSI, and TP-Link with zero Linux support. Through community reverse-engineering and 20 upstream kernel patches, full WiFi 7 (2+ Gbps on 6 GHz) and Bluetooth 5.4 now work on every major Linux distribution. Once merged, every distribution gets support automatically \- eliminating the maintenance burden of out-of-tree drivers and reducing hardware support risk for silicon vendors and Original Equipment Manufacturers (OEMs) alike.

## Contents

- [The Discovery](#the-discovery)  
- [The Ecosystem Gap](#the-ecosystem-gap)  
- [Community Investigation](#community-investigation)  
- [Engineering the Solution](#engineering-the-solution)  
- [Community Validation](#community-validation)  
- [Upstream Submission](#upstream-submission)  
- [Why Upstreaming Matters](#why-upstreaming-matters)  
- [Bridging the Gap](#bridging-the-gap)  
- [Get Your Hardware Upstream](#get-your-hardware-upstream)

## The Discovery

Last year, I noticed that the WiFi on my development PC \- the ASUS ROG Crosshair X870E Hero, which boasts AMD's flagship X870E platform coupled with a MediaTek MT7927 WiFi 7 chip \- was only partially working through an existing driver that didn't fully recognize the hardware present. Bluetooth didn't work at all. The kernel's Bluetooth stack attempted the most basic initialization command and got back an error. The driver had no idea what it was talking to.

The MT7927 is MediaTek's Filogic 380 \- a WiFi 7 and Bluetooth 5.4 combo module marketed as their flagship wireless solution. It ships on motherboards and laptops from ASUS, Gigabyte, Lenovo, MSI, and TP-Link. Over 15 products, all sold to consumers who might reasonably expect their wireless hardware to work. On Linux, it didn't.

This post traces how a community-driven reverse-engineering effort produced 20 upstream kernel patches for the MT7927, and what the experience reveals about the cost of missing Linux support for hardware vendors.

## The Ecosystem Gap

I wasn't alone. An [OpenWRT tracking issue](https://github.com/openwrt/mt76/issues/927) had been open since October 2024, accumulating 89 comments and 46 upvotes from users reporting the same problem: "my WiFi 7 card doesn't work on Linux." The same question appeared on forums for Arch, Manjaro, Fedora, Linux Mint, and half a dozen other distributions. No MediaTek developer ever replied to any of them.

The CachyOS team \- maintainers of a performance-focused Arch Linux derivative \- gave the most direct answer anyone had offered: "MT7927 is not supported on Linux. Replace it with an Intel wireless card."

When a Linux distribution's official answer to a WiFi 7 chip is "replace the hardware," the ecosystem has a problem. A silicon vendor had shipped WiFi 7 hardware to OEMs who put it on flagship products, and the Linux community was left to figure it out alone.

## Community Investigation

Without vendor documentation, the open source community started from scratch. Contributors on the [OpenWRT issue](https://github.com/openwrt/mt76/issues/927) began mapping the hardware \- cataloging USB and PCI Express (PCIe) device identifiers, dumping register layouts, and documenting firmware formats across different OEM implementations.

One critical discovery came from reverse-engineering the Windows driver package: the MT7927's Bluetooth firmware was hidden inside a WiFi firmware container. Not distributed as a separate file, not documented anywhere. A community contributor wrote a tool to parse the binary format and extract the Bluetooth firmware blob.

The chip naming itself was a puzzle. The MT7927 is a combo module containing two distinct pieces of silicon: a Bluetooth controller internally called the MT6639 (a mobile SoC component) and WiFi hardware based on the MT7925 architecture. Meanwhile, the MT7902 \- despite its similar model number \- is a completely different product line using an older driver entirely. Understanding what hardware you're actually dealing with was the first engineering challenge.

Another contributor went further, reverse-engineering a standalone WiFi driver from the Windows driver behavior. It wasn't code you could propose for the Linux kernel \- it was a self-contained implementation outside the existing driver framework \- but it proved the hardware could work on Linux and documented the initialization sequence the chip actually needed.

## Engineering the Solution

That standalone driver was the turning point. It worked. It booted the chip, loaded firmware, created a network interface. The tempting path was to package it and ship it.

I chose not to. A standalone driver would need constant maintenance against kernel API changes, couldn't leverage the existing mt76 framework's power management, roaming, or multi-band support, and would be impossible to propose for upstream inclusion in the Linux kernel. Instead, I used it as a reference to understand what the MT7927 hardware actually needs, then implemented those changes as patches to the existing mt7925e kernel driver. The upstream-first approach is harder, but it's the only path that benefits everyone permanently.

For Bluetooth, the problem was three missing layers, each depending on the one before it:

| Layer | What was missing |
| :---- | :---- |
| USB device identification | The kernel's Bluetooth driver didn't have the MT7927's USB identifier in its lookup table, so it treated the chip as generic hardware |
| Hardware variant support | The MediaTek Bluetooth subsystem didn't recognize the chip's internal identifier, so it couldn't load the right firmware |
| Firmware | The firmware itself didn't exist in any public Linux repository |

Fix all three, Bluetooth works. Miss any one, silence. Getting Bluetooth alive was the first breakthrough \- but WiFi turned out to be a much deeper challenge.

Each fix revealed the next problem. The MT7927's WiFi silicon is architecturally based on the MT7925, but it has a different bus-level initialization. A bus fabric sits between PCIe and the WiFi subsystem. Until that fabric is configured, every register read returns zero \- the chip appears completely dead even though the PCIe link is live. The existing driver had no idea this layer existed.

Beyond initialization, the chip uses a different layout for the Direct Memory Access (DMA) rings that exchange data and commands between the host and the chip's processor. The driver was sending commands on the right channels but listening for responses on the wrong ones. Commands went out, responses came back, and the driver heard silence. Getting past this required understanding the chip's actual communication layout, interrupt routing, and power management behavior \- all undocumented, all derived from the reverse-engineered reference.

The result: 18 patches for WiFi, 2 for Bluetooth, plus a firmware submission. Every new code path is gated behind hardware detection \- existing MT7925 users see zero behavior change. Same kernel module, with branches for the new hardware.

## Community Validation

The patches weren't tested in isolation. I coordinated testing across more than 20 community members and over 15 hardware platforms \- ASUS, Gigabyte, Lenovo, MSI, and TP-Link products \- running Arch Linux, CachyOS, EndeavourOS, Fedora, NixOS, openSUSE, and Ubuntu. Each tester's results fed back into the next revision of the patch series.

WiFi 7 performance was confirmed: over 2 Gbps on 6 GHz with 320 MHz channels. All three bands \- 2.4, 5, and 6 GHz \- working. Suspend and resume tested clean across multiple sleep cycles.

Community contributors found and fixed real bugs along the way: a PCIe power saving conflict that throttled uploads to a fraction of the expected throughput, a bandwidth negotiation bug that collapsed 320 MHz connections down to 20 MHz, and an authentication failure specific to 5 GHz and 6 GHz networks. Each fix was integrated, retested, and included in the patch series.

While the upstream process moved at kernel pace, I packaged everything into [mediatek-mt7927-dkms](https://github.com/jetm/mediatek-mt7927-dkms) \- a Dynamic Kernel Module Support (DKMS)-based [Arch User Repository (AUR)](https://aur.archlinux.org/packages/mediatek-mt7927-dkms) package for Arch Linux that handles firmware extraction, kernel module building, and automatic rebuilds on kernel updates. It gave users a working solution today while the patches made their way through review.

The ecosystem started packaging itself around it. Community-maintained ports appeared for NixOS, Ubuntu, and Bazzite \- each handling distribution-specific differences like module signing, firmware paths, and initramfs rebuilding. All carrying the same patches, all with the same goal: making themselves unnecessary once the code lands in the mainline kernel.

## Upstream Submission

Three parallel submissions went out: the [WiFi patch series](https://lore.kernel.org/linux-wireless/20260306-mt7927-wifi-support-v1-0-c77e7445511d@jetm.me/) to the [linux-wireless mailing list](https://lore.kernel.org/linux-wireless/), the Bluetooth patches to [linux-bluetooth](https://lore.kernel.org/linux-bluetooth/), and the firmware to the [linux-firmware repository](https://gitlab.com/kernel-firmware/linux-firmware/-/merge_requests/946).

The Bluetooth subsystem maintainer reviewed within hours. His feedback was specific and constructive: provide kernel logs showing before-and-after behavior, confirm the USB device identifiers come from real hardware testing, and get a sign-off from a MediaTek engineer confirming the changes match the chip's actual behavior. Standard kernel process \- evidence-based, thorough, and moving forward.

The WiFi series carries Tested-by acknowledgments from 10 hardware testers across 7 distributions \- kernel convention for documenting that patches have been validated on real hardware by real users. Both submissions received constructive review and are on track for mainline inclusion.

Once merged, the patches flow through subsystem trees into stable kernel releases. Every Linux distribution \- Ubuntu, Fedora, Arch, openSUSE, Debian, and every derivative \- gets MT7927 WiFi 7 and Bluetooth 5.4 support automatically. The DKMS packages and community ports become unnecessary. That's the goal.

## Why Upstreaming Matters

The cost of developing and submitting 20 kernel patches is borne once. The cost of not upstreaming is borne by every user, every distribution, and every OEM support team, indefinitely. Out-of-tree drivers break on kernel updates, diverge across distributions, and create maintenance burdens that compound over time.

For silicon vendors: your hardware reaches more users when it works out of the box on Linux. The OEMs putting your chips on flagship products are fielding support tickets from Linux users you never planned for. Upstreaming your drivers is not charity \- it's product support at scale.

For OEMs: Linux market share on the desktop is growing. When your flagship motherboard ships with a WiFi chip that doesn't work on Linux, the community's answer is "replace it with Intel." That's not a driver problem. That's a competitive problem.

When hardware vendors don't upstream, the open source community and ecosystem still moves forward. The MT7927 story shows how: community reverse-engineering, upstream-quality driver patches, cross-distribution testing, and a clear path to mainline. The gap gets closed \- it just takes longer than it should. And Linaro engineers are often the ones making it happen.

## Bridging the Gap

None of this was accidental. I work at Linaro, and bridging the gap between silicon and the upstream Linux kernel is exactly what we do \- it's what we've been doing for over a decade. On Arm, on x86, wherever the hardware exists but the kernel support doesn't. Reverse-engineering undocumented hardware, shepherding 20 patches through mailing list review, coordinating cross-distribution testing \- this is familiar territory.

The MT7927 is one chip on one platform. But the pattern repeats across the industry: hardware ships, Linux support lags, the community fills the gap. If your hardware has a Linux gap \- whether it's a missing driver, stalled firmware submission, or upstream patches that need shepherding through review \- that's exactly the work we do.

## Get Your Hardware Upstream

If your hardware has a Linux gap, Linaro's engineering teams can help close it. We work with silicon vendors and OEMs to bring hardware support from prototype to mainline.

- **Silicon vendors**: [Contact Linaro](https://www.linaro.org/contact/) to discuss upstream driver development and firmware submission  
- **OEMs**: Reduce support costs and competitive risk by getting your hardware working on Linux before it ships \- [talk to us](https://www.linaro.org/contact/) about upstream enablement  
- **Engineers**: Follow the MT7927 upstream progress on the [linux-wireless mailing list](https://lore.kernel.org/linux-wireless/) or contribute to the [DKMS package on GitHub](https://github.com/jetm/mediatek-mt7927-dkms)

