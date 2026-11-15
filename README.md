# Charcoal SteamOS 3.10 / Linux 7.3 — NAP experiment

> Experimental Steam Deck kernel build. Use at your own risk. A successful package build does not prove boot or runtime stability.

This branch targets Valve's exact SteamOS 3.10 Linux 7.3 source. It is separate from the frozen validation/steamos-3.10-linux-7.3 branch and the 7.2 line on master. Do not use the 7.2 installer on SteamOS 3.10.

## Source and package identity

- Valve package: linux-neptune-73 7.3.1.valve2-1
- Valve source commit: 0ed55b10a784a0a0b518ecd20551659fde1d59c9
- Boot/module identity: linux-neptune-73
- Package names: linux-charcoal-73 and linux-charcoal-73-headers

This is built from Valve's SteamOS source and configuration, not generic upstream Linux.

## Feature set

The branch retains the previous 7.3 feature set: BORE, POC Selector, ADIOS and udev integration, LRU CAST, ZRAM-IR, AMD P-State EPP changes, NTSYNC, Steam Deck drivers/configuration, Clang/LLVM, Zen 2 targeting, O3, full Clang LTO and Polly.

This experiment adds:
- NAP CPUIdle governor, pinned to firelzrd NAP v0.6.5. NAP is selected with cpuidle.governor=nap; TEO remains compiled as a fallback.
- DRM scheduler Round Robin default, applied to Valve 7.3 source with an exact fail-closed symbol replacement.
- NAP userspace tools and persistence integration, packaged with the kernel from the resolved upstream source and the actual built governor weights.

It excludes the re-swappiness patch. ZSWAP is disabled; ZRAM remains enabled as a module with LZ4 primary compression and ZRAM-IR runtime configuration. Btrfs is built into the kernel (CONFIG_BTRFS_FS=y).

NAP changes CPU idle-state selection. It is not a scheduler or GPU-frequency booster, and no FPS gain should be assumed. Hardware testing is needed for power, wake latency, frame pacing and thermals.

## Build and artifact validation

GitHub Actions builds this branch only. The workflow downloads and verifies the exact Valve source archive, checks out the pinned Valve source commit, applies the NAP and DRM RR changes, resolves the kernel config, compiles with Clang/LLVM and packages kernel plus headers.

The successful build is published as the [SteamOS 3.10 – Linux 7.3 NAP GitHub Release](https://github.com/Marctraider/linux-charcoal-vulcano/releases/tag/steamos-3.10-linux-7.3-nap). The release contains the complete build ZIP and its `RELEASE-ZIP-SHA256SUM` checksum file. Verify the ZIP against that checksum before extracting it; the ZIP contains the kernel and headers packages, package SHA-256 manifest, build log and NAP upstream provenance. The published ZIP SHA-256 is `395cf9671e6149f26695e69eeed2fb4c1ae59a63ab35ee005f9519ca8d8e0680`. The installer continues to select the latest successful run of this branch's dedicated workflow and verify package checksums before pacman runs; it does not download from GitHub Releases.

A green build proves compilation and packaging only. It does not prove Steam Deck boot, Btrfs root mounting on a particular installation, or performance benefit.

## Install or upgrade on SteamOS 3.10

The NAP package uses the same package names and linux-neptune-73 boot identity as the earlier non-NAP 7.3 package. Before installing, ensure the currently installed kernel boots and retain a recovery route.

Run the read-only diagnostic:

```bash
curl -fsSL https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/experiment/steamos-3.10-linux-7.3-nap/install-charcoal.sh -o install-charcoal.sh
bash install-charcoal.sh --check-only
```

If the checks pass, run the installer interactively:

```bash
bash install-charcoal-73-nap.sh
```

The installer finds the latest successful NAP build artifact and verifies its package checksums, linux-neptune-73 boot identity, required kernel configuration (NAP, TEO fallback, Btrfs, ZRAM/LZ4, BORE, POC Selector, LRU CAST and NTSYNC), and build-log evidence for the DRM Round Robin default.

For an existing linux-charcoal-73 installation, it takes the short upgrade path: pacman replaces the kernel and headers together in one transaction. It does not run the fresh-install boot-chain preflight, calculate free space, or remove the stock kernel during this upgrade. It then regenerates initramfs and GRUB and checks the expected boot references.

For a fresh installation, it checks the existing SteamOS boot chain and keeps the Valve stock kernel unless pacman reports insufficient disk space. Only then does it ask before removing the matching stock 7.3 package(s) and retrying. If no stock package is available to free space, it stops rather than retrying the same transaction.

The downloaded ZIP and extracted packages are staged under /dev/shm (tmpfs), not /root or the root filesystem. The ZIP is deleted after extraction, and rollback packages already in pacman's cache are referenced by symlink rather than copied. This avoids creating a second large package archive on the root filesystem; it does use temporary RAM-backed storage, which must have enough free capacity. The installed kernel itself still occupies its normal filesystem space. The installer never reboots automatically.

Rollback after a failed post-install check is best-effort and depends on the previous exact packages being present in pacman's cache; it is not guaranteed. Do not reboot unless the installer reports that kernel image, initramfs and GRUB checks passed. A successful automated check is not a substitute for a real Steam Deck boot test.

## Feature diagnostics

The NAP-aware --check-only mode should check SteamOS version, installed package identity, module pkgbase, boot files and GRUB references. It should check the running kernel config for NAP, Btrfs and ZRAM where that config is exposed; check whether NAP is the active CPUIdle governor; report NAP userspace helper/service state; and check DRM Round Robin only if the running kernel exposes a scheduler-policy sysfs parameter. Otherwise it must explicitly report that runtime verification is unavailable.

The `--check-only` option is the installer's read-only boot diagnostic; it does not install/remove packages, regenerate initramfs, edit GRUB or reboot. The separate `charcoal-status` command reports installed kernel features and runtime state after boot. On this NAP branch it checks the NAP and TEO build options, whether NAP is the active CPUIdle governor, the DRM Round Robin policy when the kernel exposes its sysfs parameter, and the NAP userspace service integration. If the DRM parameter is absent, it reports that runtime verification is unavailable rather than treating the missing interface as a failure.

## Btrfs and boot status

The build configuration enables Btrfs in-kernel. The package boot identity is linux-neptune-73, and the installer checks the expected kernel/initramfs/GRUB paths. These checks do not replace a real Steam Deck boot test. Btrfs root mounting and successful hardware boot remain unverified until tested on a Deck.

## Memory and security policy

ZRAM remains enabled with LZ4 primary compression and ZRAM-IR runtime configuration. ZSWAP and re-swappiness are omitted. The built-in kernel command line includes mitigations=off and amd_pstate.epp_boost=1. Disabling CPU vulnerability mitigations is a security/performance trade-off.

## Branch safety

- This documentation and installer apply only to experiment/steamos-3.10-linux-7.3-nap.
- validation/steamos-3.10-linux-7.3 remains frozen and untouched.
- master remains untouched.
- No release is published automatically.
