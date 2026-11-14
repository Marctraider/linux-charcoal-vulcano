# SteamOS 3.10 / Linux 7.3 port audit

Status: **7.3 build preparation and validation in progress; no successful kernel build or Steam Deck boot has been established.** This branch is validation-only and must not publish a release.

## Target source

Use Valve's exact SteamOS 3.10 source package:

- Package: `linux-neptune-73`
- Version: `7.3.1.valve2-1`
- Source archive: https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-3.10/linux-neptune-73-7.3.1.valve2-1.src.tar.gz
- Signature: append `.sig` to the archive URL.
- Archive SHA-256: `a6316acc22954d0685ac923248995246789a1f3b5ee6890d378ce2c3efa25af8`
- Valve source tag: `7.3.1-valve2`
- Resolved commit: `0ed55b10a784a0a0b518ecd20551659fde1d59c9`

Do not substitute valve1, generic upstream v7.3.1, or a newer unrelated SteamOS source snapshot. The Valve source archive contains the embedded bare Git repository and the matching `config.x86_64` / `config-neptune` fragments.

## 7.3 package and installer

- Dedicated recipe: `PKGBUILD`
- Package identity: `linux-charcoal-73` and `linux-charcoal-73-headers`
- Kernel source identity is pinned to Valve's exact 7.3.1.valve2 tag and archive checksum.
- The 7.3 installer accepts only 7.3 release tags and package names.
- It removes previously installed Charcoal kernel packages. It also identifies only the matching `linux-neptune-73` kernel and headers and asks for explicit confirmation before removing them.
- It does not target `linux-neptune-72`. The installer never reboots automatically and attempts rollback from cached package files if installation fails.
- The 7.3 build workflow is isolated from the 7.2 workflow and uploads build artifacts only. It does not publish a release.

Because the installer can remove the stock 7.3 kernel after confirmation, do not approve that step unless a separate recovery route is available.

## Retained Linux 7.3 feature scope

The intended kernel-side feature set is:

- BORE scheduler and POC Selector.
- ADIOS I/O scheduler and default-scheduler integration.
- LRU CAST reclaim.
- ZRAM-IR and its runtime configuration.
- Kernel ZSWAP.
- AMD P-State EPP defaults and per-core EPP boost, pending clean source application and compilation.
- Zen 2 targeting, Clang/LLVM, O3, full Clang LTO and Polly.
- Van Gogh 4.2 GHz frequency and power-limit changes, pending source/build/hardware validation.

The pinned upstream patch candidates are checked against the exact Valve source. A successful `git apply --check` is only a preliminary compatibility signal, not proof of compilation or runtime correctness. Some 7.3-specific adaptations are handled by fail-closed Python helpers with exact source preconditions.

## Explicit exclusions and inherited stock configuration

- **NAP is omitted from Linux 7.3.** No native 7.3 patch has been proven to apply cleanly. NAP remains on the separate stable 7.2 line.
- **IOMMU/PerfOpt is excluded.** Its patch, config overrides and README claims are not part of this port.
- **No bundled third-party controller drivers or workarounds:** xone, xpadneo and xpad-noone are not included.
- **No custom controller or Steam Deck HID config overrides.** The Charcoal overlay does not force these options on or off; Valve's SteamOS base fragments determine the stock module/built-in settings.
- Gaming sysctl profiles, forced environment variables, gaming swapfile migration and gaming swap services/hooks are excluded.
- The 7.3 package does not install the inherited NAP package lifecycle hook.

Valve's base config has `CONFIG_BTRFS_FS=y` and the Steam Deck HID/MFD/LED/sensor options as modules. The Charcoal overlay does not override those controller/Steam Deck options. The earlier `btrfs.c` boot failure is not explained by Btrfs being disabled in Valve's 7.3 base config.

## Current validation path

1. Download and checksum-verify the exact Valve source archive.
2. Inspect the embedded bare Git repository and resolve the exact `7.3.1-valve2` commit.
3. Download pinned patch inputs, verify immutable Git blob IDs where available, and verify all source files against the PKGBUILD checksums.
4. Apply retained patches and reviewed 7.3-specific adapters in the declared order.
5. Merge Valve's base config fragments with `config-charcoal-73`, run `olddefconfig`, and assert required options.
6. Compile and package the kernel and headers using the isolated `.github/workflows/build-kernel-7.3.yml` workflow.
7. Inspect package metadata, module paths, boot image, headers and bootloader integration.
8. Test boot, Btrfs, Wi-Fi, audio, Bluetooth, controllers, suspend/resume, storage and games on an actual Steam Deck.

The source-inspection workflow is diagnostic. The build workflow must complete all preparation and compilation steps before a package can be treated as build-validated. CI still cannot prove that the kernel boots or behaves correctly on the user's Deck.

## Safety gates

- **Do not modify `master` or its stable 7.2 release workflow.** All 7.3 changes stay on `validation/steamos-3.10-linux-7.3`.
- Do not merge the validation branch or publish a 7.3 release without explicit approval.
- Do not describe patch application as a successful build.
- Do not claim a successful boot, hardware compatibility or performance improvement without evidence from the actual device.
- Keep a separate recovery route before removing the stock 7.3 kernel.

## Verified Valve source identity

The source inspection workflow successfully downloaded the official archive, extracted its package metadata and inspected the embedded repository. The exact annotated tag `7.3.1-valve2` resolves to commit `0ed55b10a784a0a0b518ecd20551659fde1d59c9`, subject `linux-integration 7.3.1-valve2`. The embedded bare Git repository contains 14,163,020 objects and its packed data is approximately 3.6 GiB.

This identity is the pinned base for `PKGBUILD` and the 7.3-only build workflow.
