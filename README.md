# Charcoal SteamOS 3.10 / Linux 7.3

> **Disclaimer:** At own risk! Tested on clean SteamOS builds.


This branch contains the Linux 7.3 port and installer validation work for SteamOS 3.10 Preview. The published `r1` release has a known boot-packaging defect: its kernel package uses the wrong mkinitcpio/boot identity. The 7.3 branch installer now normalizes the downloaded r1 kernel package locally by changing only its `pkgbase` marker and matching `.MTREE` record, then verifies both before pacman can install it. The kernel image and modules are not rebuilt or modified. It is separate from the stable 7.2 line on `master`; the 7.2 branch is not part of this work and must remain unchanged. The 7.2 package uses the `linux-neptune-72` boot identity, whereas SteamOS 3.10's boot integration targets `linux-neptune-73`. The 7.2 installer also removes every installed `linux-charcoal-*` package before installing its selected series, so it can remove an existing 7.3 kernel without restoring the 3.10 boot target. **Do not install the 7.2 branch on SteamOS 3.10.**

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
- ZRAM-IR with LZ4 primary compression and ZSTD recompression; kernel ZSWAP is intentionally disabled to avoid its additional compressed-cache activity in the CPU-focused gaming profile.
- AMD P-State EPP defaults and the per-core EPP boost port, subject to clean application and compilation validation.
- Zen 2 targeting via Clang's `-march=znver2` kernel compile flag, Clang/LLVM, O3, full Clang LTO and Polly. Valve 7.3 no longer exposes the older x86-64 `MZEN2` Kconfig selector, so the target is set explicitly by the build recipe.
- Van Gogh 4.2 GHz frequency patch, subject to source and hardware validation. The separate Van Gogh power-limit patch is omitted because its source anchors changed in Valve 7.3 and a safe port was not established.

### Memory compression policy

The 7.3 installer automatically adds `zswap.enabled=0` to `/etc/default/grub` before regenerating GRUB, so an already-built kernel is configured to start with ZSWAP disabled without rebuilding. The installer backs up the original file as `/etc/default/grub.charcoal-backup`, removes conflicting `zswap.enabled` values, and verifies that the generated GRUB entry contains the setting. For a kernel already installed before this installer change, add `zswap.enabled=0` to the GRUB kernel command line manually or rerun the updated installer. Verify after reboot with `cat /sys/module/zswap/parameters/enabled` (expected: `N`).

ZRAM-IR remains enabled as the swap device for memory-pressure protection. Kernel ZSWAP is disabled in the 7.3 build configuration: it adds a second compressed-swap cache path, while the Steam Deck configuration prioritizes ZRAM and CPU time for games. ZSWAP's ZSTD compressor selection is therefore removed rather than retained as an inactive backend. ZRAM still performs compression when pages are actually swapped; this is not a guarantee of higher FPS, and the aim is to avoid ZSWAP's additional work rather than eliminate all compression overhead.

The selected upstream patch candidates are pinned to immutable revisions and checked against the Valve source. A patch applying cleanly is only an initial compatibility check; it is not proof that the kernel compiles or works correctly.

### Explicit exclusions

- **NAP is not included in Linux 7.3.** No native 7.3 patch has been demonstrated to apply cleanly. NAP remains part of the separate stable 7.2 line.
- **IOMMU/PerfOpt is excluded.** Its patch, config overrides and documentation are not part of this 7.3 port.
- **No bundled third-party controller drivers or workarounds.** xone, xpadneo, xpad-noone, their udev/modprobe rules and controller workarounds are not included.
- **No custom controller or Steam Deck HID config overrides.** Controller and Steam Deck device options are inherited from Valve's SteamOS configuration; Charcoal does not force these drivers on or off.
- **No Ryzen SMU DKMS bundle.** Van Gogh kernel frequency/power changes are separate kernel-source patches; no third-party SMU module is installed.
- Gaming sysctl profiles, forced gaming environment variables, swapfile migration and gaming swap services/hooks are not part of this kernel package.

Steam Input and Valve's in-tree Steam Deck/controller support remain inherited from the stock SteamOS configuration. The 7.3 installer is series-specific. Before making package changes, it now verifies that the existing SteamOS 3.10 kernel image, initramfs, mkinitcpio preset and GRUB references are present. If the existing boot chain is already incomplete, it aborts before changing packages. The installer still removes only the matching `linux-neptune-73` stock kernel and headers to free system space; this removes the stock-kernel fallback, so installation remains a controlled validation step rather than a proven safe upgrade. It does not target `linux-neptune-72` or any 7.2 Charcoal packages.


## Install the latest 7.3 release

**Important:** this command downloads and executes the 7.3 installer from this validation branch. It does not compile the kernel on the Steam Deck. The installer selects the newest published, non-draft, non-prerelease Linux 7.3 release. If it selects r1, it corrects and verifies the local package copy before installation; it does not rebuild the kernel. It does not use the repository-wide latest release, which could belong to another kernel series.

First run the read-only diagnostic on SteamOS 3.10:

```bash
curl -fsSL https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/validation/steamos-3.10-linux-7.3/install-charcoal.sh -o install-charcoal-73.sh
bash install-charcoal-73.sh --check-only
```

The `--check-only` mode checks the SteamOS version, installed kernel packages, mkinitcpio preset, kernel image, initramfs, module `pkgbase`, GRUB references and free space. It does not install/remove packages, write files, regenerate initramfs, change GRUB, or reboot. Share its complete output before attempting installation.

After `--check-only` passes, the normal installer can be run from a terminal. It requires an interactive confirmation, verifies the release ZIP and package checksums, normalizes the r1 boot identity if needed, verifies the package marker and `.MTREE`, then generates and checks the initramfs and GRUB references. It removes the stock SteamOS 7.3 kernel and headers to free space; the stock kernel is therefore not retained as a boot-menu fallback. The exact cached stock packages are required for an attempted rollback if installation fails before reboot. This remains a controlled test install, not a proven boot-tested release. Do not reboot unless the installer reports that the kernel image, initramfs and GRUB references all passed.

### CPU vulnerability mitigations

Charcoal 7.3 makes the requested performance policy the kernel's built-in boot default: the build configures `CONFIG_CMDLINE` with `mitigations=off` alongside the AMD P-State EPP boost parameter. The installer/build recipe supplies this setting; users do not need to add a boot argument themselves.

Valve's 7.3 x86 Kconfig selects `ARCH_CONFIGURES_CPU_MITIGATIONS`, so `CONFIG_CPU_MITIGATIONS=n` is not a valid final x86 configuration: `olddefconfig` restores it to `y`. The mitigation framework remains compiled in, while the built-in `mitigations=off` parameter disables mitigations by default at boot. The kernel command line is not forced to override the SteamOS bootloader command line, preserving required SteamOS boot arguments.

Disabling mitigations can reduce overhead and may help CPU-constrained workloads, but reduces protection against CPU side-channel vulnerabilities. This is a deliberate security/performance trade-off.