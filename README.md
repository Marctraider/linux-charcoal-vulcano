# Charcoal SteamOS 3.10 / Linux 7.3

This branch is the **unreleased Linux 7.3 port** for SteamOS 3.10 Preview. It is separate from the stable 7.2 line on `master`; the 7.2 branch is not part of this work and must remain unchanged.

The build target is Valve's exact SteamOS 3.10 source package:

- Package: `linux-neptune-73 7.3.1.valve2-1`
- Valve source tag: `7.3.1-valve2`
- Valve source commit: `0ed55b10a784a0a0b518ecd20551659fde1d59c9`
- Source archive: [Valve linux-neptune-73 7.3.1.valve2-1](https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-3.10/linux-neptune-73-7.3.1.valve2-1.src.tar.gz)

This is not a generic upstream Linux build. The Valve SteamOS integration tree and its matching `config.x86_64` / `config-neptune` fragments are the base.

## Linux 7.3 feature scope

The intended kernel-side features retained in this port are:

- BORE scheduler.
- POC Selector.
- ADIOS I/O scheduler and its default-scheduler integration.
- LRU CAST reclaim.
- ZRAM-IR and its udev/runtime configuration.
- Kernel ZSWAP.
- AMD P-State EPP defaults and the per-core EPP boost port, subject to clean application and compilation validation.
- Zen 2 targeting, Clang/LLVM, O3, full Clang LTO and Polly.
- Van Gogh 4.2 GHz frequency and power-limit changes, subject to source and hardware validation.

The selected upstream patch candidates are pinned to immutable revisions and checked against the Valve source. A patch applying cleanly is only an initial compatibility check; it is not proof that the kernel compiles or works correctly.

### Explicit exclusions

- **NAP is not included in Linux 7.3.** No native 7.3 patch has been demonstrated to apply cleanly. NAP remains part of the separate stable 7.2 line.
- **IOMMU/PerfOpt is excluded.** Its patch, config overrides and documentation are not part of this 7.3 port.
- **No bundled third-party controller drivers or workarounds.** xone, xpadneo and xpad-noone are not included.
- **No custom controller or Steam Deck HID config overrides.** Controller and Steam Deck device options are inherited from Valve's SteamOS configuration; Charcoal does not force these drivers on or off.
- Gaming sysctl profiles, forced gaming environment variables, swapfile migration and gaming swap services/hooks are not part of this kernel package.

Steam Input and Valve's in-tree Steam Deck/controller support are not removed by excluding the third-party driver bundle.

## Installation

A 7.3 release has not been published yet. The installer refuses to install a 7.2 release; it accepts only a Charcoal 7.3 release from this fork.

Once a 7.3 release has been built and published, the installer on this branch can be downloaded with:

```bash
curl -fsSL https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/validation%2Fsteamos-3.10-linux-7.3/install-charcoal.sh -o install-charcoal.sh && bash install-charcoal.sh
```

The installer verifies the release ZIP and package checksums before changing packages. It removes previously installed Charcoal kernel packages and, after explicit confirmation, the matching SteamOS stock `linux-neptune-73` kernel and headers. This is a deliberate replacement step: do not approve it unless you have a separate recovery route. The installer does not reboot automatically.

Optional installer variables:

- `CHARCOAL_73_REMOVE_STOCK=1` pre-authorizes removal of the matching stock 7.3 kernel.
- `CHARCOAL_73_ASSUME_YES=1` accepts the installer confirmations.

The package identity is `linux-charcoal-73` with matching `linux-charcoal-73-headers`. It is versioned separately from the 7.2 package.

## Build and validation

The dedicated 7.3 build recipe is `PKGBUILD-73`; it uses the exact Valve source archive and matching base config fragments. The archive SHA-256 is pinned in the recipe.

The source-inspection workflow downloads Valve's source, verifies the embedded tag/commit and audits the selected patch candidates. Its successful result is **not** a successful kernel build. The 7.3 build still has separate gates:

1. Verify every required patch/helper source and checksum.
2. Apply the selected patches and 7.3-specific source adapters in a clean tree.
3. Merge Valve's base config fragments with `config-charcoal-73` and validate the resulting `.config`.
4. Compile and package the kernel and headers.
5. Validate package metadata, module paths and bootloader integration.
6. Boot and test on an actual Steam Deck, including Wi-Fi, audio, controls, suspend/resume, storage and games.

The GitHub Actions workflow for 7.2 is not the 7.3 build workflow. This branch must use its own 7.3-only build path and must not publish or replace the 7.2 release.

## Historical benchmark

The following two sample runs were recorded against the older 3.9.5 baseline. They are historical measurements, not a benchmark of this Linux 7.3 port.

| Kernel | Run | Average FPS | Minimum FPS | Maximum FPS |
|---|---:|---:|---:|---:|
| Default 3.9.5 kernel | 1 | 59.03 | 43.53 | 85.91 |
| Default 3.9.5 kernel | 2 | 58.67 | 43.17 | 85.72 |
| Older tuned kernel | 1 | 62.94 | 44.73 | 89.92 |
| Older tuned kernel | 2 | 62.96 | 44.85 | 89.09 |

The test used graphics settings intended to stress the CPU and a modded OLED BIOS with a 4.2 GHz CPU limit. The results are only two sample runs and do not establish causation or predict Linux 7.3 performance.

## Project scope

This is an enthusiast kernel port for SteamOS, not an official Valve kernel. Kernel patches and compiler settings have workload- and hardware-dependent trade-offs. CI can validate source preparation, configuration, compilation and package structure; it cannot prove correct boot or runtime behavior on the Steam Deck.
