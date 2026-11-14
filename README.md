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
- Van Gogh 4.2 GHz frequency patch, subject to source and hardware validation. The separate Van Gogh power-limit patch is omitted because its source anchors changed in Valve 7.3 and a safe port was not established.

The selected upstream patch candidates are pinned to immutable revisions and checked against the Valve source. A patch applying cleanly is only an initial compatibility check; it is not proof that the kernel compiles or works correctly.

### Explicit exclusions

- **NAP is not included in Linux 7.3.** No native 7.3 patch has been demonstrated to apply cleanly. NAP remains part of the separate stable 7.2 line.
- **IOMMU/PerfOpt is excluded.** Its patch, config overrides and documentation are not part of this 7.3 port.
- **No bundled third-party controller drivers or workarounds.** xone, xpadneo, xpad-noone, their udev/modprobe rules and controller workarounds are not included.
- **No custom controller or Steam Deck HID config overrides.** Controller and Steam Deck device options are inherited from Valve's SteamOS configuration; Charcoal does not force these drivers on or off.
- **No Ryzen SMU DKMS bundle.** Van Gogh kernel frequency/power changes are separate kernel-source patches; no third-party SMU module is installed.
- Gaming sysctl profiles, forced gaming environment variables, swapfile migration and gaming swap services/hooks are not part of this kernel package.

Steam Input and Valve's in-tree Steam Deck/controller support remain inherited from the stock SteamOS configuration. The 7.3 installer is series-specific: it removes previous Charcoal kernel packages and, only after explicit confirmation, the matching linux-neptune-73 stock kernel and headers. It does not target linux-neptune-72.

### CPU vulnerability mitigations

Charcoal 7.3 makes the requested performance policy the kernel's built-in boot default: the build configures `CONFIG_CMDLINE` with `mitigations=off` alongside the AMD P-State EPP boost parameter. The installer/build recipe supplies this setting; users do not need to add a boot argument themselves.

Valve's 7.3 x86 Kconfig selects `ARCH_CONFIGURES_CPU_MITIGATIONS`, so `CONFIG_CPU_MITIGATIONS=n` is not a valid final x86 configuration: `olddefconfig` restores it to `y`. The mitigation framework remains compiled in, while the built-in `mitigations=off` parameter disables mitigations by default at boot. The kernel command line is not forced to override the SteamOS bootloader command line, preserving required SteamOS boot arguments.

Disabling mitigations can reduce overhead and may help CPU-constrained workloads, but reduces protection against CPU side-channel vulnerabilities. This is a deliberate security/performance trade-off.