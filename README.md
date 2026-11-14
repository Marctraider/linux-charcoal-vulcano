# Charcoal SteamOS Kernel

## Sample Cyberpunk 2077 benchmark

Two sample benchmark runs comparing the default 3.9.5 kernel with this tuned kernel. FPS values are average, minimum and maximum FPS.

| Kernel | Run | Average FPS | Minimum FPS | Maximum FPS |
|---|---:|---:|---:|---:|
| Default 3.9.5 kernel | 1 | 59.03 | 43.53 | 85.91 |
| Default 3.9.5 kernel | 2 | 58.67 | 43.17 | 85.72 |
| This tuned kernel | 1 | 62.94 | 44.73 | 89.92 |
| This tuned kernel | 2 | 62.96 | 44.85 | 89.09 |

**Test notes:**
- The game was tested with graphics settings chosen to place maximum strain on the CPU, as this was expected to have the greatest effect on the comparison.
- The test device uses a modded OLED BIOS with the maximum CPU clock set to 4.2 GHz.
- It is not established whether the 4.2 GHz patch was the main contributor to the observed difference. These are two sample runs, not a controlled or statistically conclusive benchmark.

## Maintainer notes

- **Optional diagnostics:** the separate `charcoal-status` script checks whether the kernel features and related runtime functions appear to be working. It is a diagnostic aid, not a requirement for installing or using the kernel.

Charcoal is a custom SteamOS kernel maintained in this repository. The purpose of this fork is to keep the kernel-side performance, scheduling, memory-management and Steam Deck hardware work while removing the gaming-oriented userspace configuration and bundled third-party controller-driver stack that are not required for those kernel features.

**This repository is the installer and release source.** The installer must download packages from `Marctraider/linux-charcoal-vulcano`, not from the original `zarpon/linux-charcoal-vulcano` repository.

## Project intent: this fork vs. Zarpon's original

This repository began as a fork of [Zarpon's linux-charcoal-vulcano](https://github.com/zarpon/linux-charcoal-vulcano). It retains the Charcoal kernel project's general goal of providing a performance-focused SteamOS kernel, but this fork has a narrower separation between kernel features and operating-system/user-session tweaks.

| Area | This fork's intent |
|---|---|
| Kernel scheduler and reclaim features | Keep the selected kernel patches and configuration, including BORE, POC Selector, ADIOS, LRU CAST and NAP. |
| Memory and compression | Keep kernel ZSWAP and ZRAM-IR support/configuration. Keep the ADIOS and ZRAM-IR udev/runtime integration required by those features. |
| AMD power management | Keep AMD P-State EPP active-mode defaults and EPP boost changes. |
| Compiler and CPU tuning | Keep the Zen 2 target, Clang/LLVM build, O3, full Clang LTO and Polly configuration. |
| Gaming-oriented userspace tuning | Remove custom gaming sysctl profiles, forced environment variables and swapfile migration/setup. Let SteamOS and the user manage these policies. |
| Controller driver bundle | Remove the bundled xone, xpadneo and xpad-noone driver/workaround package. This does not remove Steam Input. |
| Unrelated kernel functionality | Preserve the Valve/SteamOS kernel base and features not specifically targeted by this cleanup. |

The distinction is deliberate: **kernel capabilities stay in the kernel; optional gaming-session policy and bundled controller workarounds do not get imposed by this package.** This is not a promise that every workload will be faster. Kernel options can have hardware- and workload-dependent trade-offs.

The fork has also moved beyond the original repository's earlier kernel-source baseline. Its maintained build pipeline resolves the current SteamOS stable image and the matching Valve kernel source/configuration rather than simply building the old source snapshot. See [stable source tracking](#how-the-build-tracks-steamos-stable).

## Install the latest fork release

**Important:** the installer below downloads a prebuilt release. It does not compile the kernel on the Steam Deck. A published release must exist in this fork before the command can install anything. If [this repository's Releases page](https://github.com/Marctraider/linux-charcoal-vulcano/releases) has no stable release yet, wait for the first successful publishing workflow.

Once a stable release is published, run:

```bash
curl -fsSL https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/master/install-charcoal.sh -o install-charcoal.sh && bash install-charcoal.sh
```

The script in this repository is configured to query [this fork's latest release](https://github.com/Marctraider/linux-charcoal-vulcano/releases/latest). It does not use Zarpon's release endpoint.

### What the installer does

1. Reads the latest non-draft, non-prerelease stable release from this repository.
2. Downloads the release ZIP and its release-level SHA-256 file over HTTPS.
3. Verifies the ZIP checksum, safely extracts the kernel and matching headers packages, and verifies each package against the ZIP's `SHA256SUMS`.
4. Checks package metadata before starting the package transaction.
5. Identifies an installed Charcoal kernel and the conflicting stock SteamOS kernel for the same series. It asks before removing the stock kernel.
6. Asks for confirmation before changing packages, enables SteamOS write mode/developer mode, installs the verified kernel and headers, and updates the bootloader.
7. Attempts rollback from exact package copies in pacman's cache if installation fails and all removed packages were cached.

The installer never reboots automatically. Do not reboot if it reports that installation failed and rollback was unavailable. The installer uses narrowly scoped package removal for the conflicting kernel packages; read its prompts before accepting them.

After a successful install, reboot manually. Optionally, run the separate `charcoal-status` diagnostic script to check compiled configuration and runtime activation:

```bash
uname -r
pacman -Q | grep '^linux-charcoal'
sudo charcoal-status
```

The running kernel version should identify the installed Charcoal kernel. `charcoal-status` reports compiled configuration and runtime activation separately. Green `[PASS]` means a check passed, yellow `[WARN]` means a check needs context (often reboot or hardware), and red `[FAIL]` means a required check failed. The status utility is a diagnostic aid, not a substitute for testing on the actual Deck.

The installer supports these optional environment variables:

- `CHARCOAL_72_REMOVE_STOCK=1`: pre-authorizes removal of the conflicting stock kernel.
- `CHARCOAL_72_ASSUME_YES=1`: accepts both installer confirmations.

Do not use these options unless you understand the package changes they authorize.

## Kernel features retained

The current configuration and patch stack retain the selected versions of:

- BORE scheduler changes and sched_ext coexistence support.
- POC Selector.
- ADIOS and its default I/O scheduler integration.
- LRU CAST reclaim changes.
- NAP CPU idle governor and its userspace learning/tools integration.
- ZRAM-IR and its runtime configuration.
- Kernel ZSWAP, including the configured ZSTD backend.
- AMD P-State EPP active-mode defaults and EPP boost changes.
- Zen 2 CPU targeting, Clang/LLVM, O3, full Clang LTO and Polly build configuration.

The package retains the ADIOS and ZRAM-IR udev rules and the NAP package lifecycle hooks required by these features. Kernel ZSWAP is distinct from the removed gaming swap userspace setup.

### What was intentionally removed

This fork's cleanup removed the custom gaming sysctl profiles, gaming environment variables, swapfile migration/setup scripts and related systemd units/hooks. It also removed the bundled xone, xpadneo and xpad-noone controller driver/workaround sources and packaging.

Steam Input is a Steam userspace feature and is not removed by this cleanup. The removed third-party driver bundle should not be confused with Steam Input. Controller behavior still depends on the kernel configuration, device and SteamOS userspace.

### Performance and safety notes

- O3, LTO and Polly are build choices, not guarantees of higher frame rates or lower latency. Results vary by workload and device.
- The Van Gogh patches raise configured CPU frequency/power limits; they do not guarantee that the hardware will sustain those values.
- Static CI and package validation do not replace boot, suspend/resume, Wi-Fi, audio, controller and game testing on a Steam Deck.

## How the build tracks SteamOS stable

The source of truth is Valve's [SteamOS stable update metadata](https://steamdeck-atomupd.steamos.cloud/meta/holo/steamos/amd64/steamdeck/stable.json), not the highest kernel version found in a source index. The stable resolver:

1. Selects an image explicitly marked stable and records its SteamOS version/build ID.
2. Downloads that image's package manifest and identifies the exact `linux-neptune-<series>` package.
3. Resolves the corresponding Valve kernel source repository/tag and matching Arch/Valve configuration.
4. Updates the package series and patch compatibility target to match that stable source.

Preview/main images and RC/beta kernel packages are rejected. Missing or ambiguous metadata fails the build rather than silently falling back to another channel or older source. The resolved image, manifest, source URL, tag and kernel series are recorded in `steamos-stable-source.json`.

Patch compatibility is checked against the resolved source. Required patch families are not silently dropped or downgraded when upstream APIs change; incompatible changes should fail validation/build until corrected. The validated `patch-lock.json` records patch versions, origins, hashes and functionality already provided by Valve's source.

## Build and release process

The `master` branch is the intended stable release branch.

- Pushes to `master` run the stable build and release workflow.
- Pull-request and `validation/**` builds validate changes but do not publish releases.
- The daily workflow checks the current SteamOS stable source and builds from `master`.
- A release is published only after source/patch validation, kernel configuration checks, compilation, packaging and checksum generation succeed.
- Published releases include the kernel package, matching headers, a ZIP bundle, checksums, patch-lock data and stable-source metadata.

The `kernel-7.2` workflow is retained for manual development builds and artifacts; it is not the stable release path. Some helper filenames still contain `7.2` for compatibility, while the stable resolver detects the active SteamOS kernel series.

For local development, the preparation flow uses Python 3, Bash and Git:

```bash
python3 automation/prepare-pkgbuild-7.2.py --write PKGBUILD
python3 automation/prepare-steamos-stable.py --fetch-config
python3 automation/resolve-latest-patches-7.2-policy.py --overrides logs/patch-source-overrides-stable.json --write
python3 automation/validate-patch-lock.py --manifest logs/patch-sources-7.2.json --overrides logs/patch-source-overrides-stable.json
```

The Dockerfile provides the Arch Linux/LLVM build environment. CI validation is useful, but it cannot prove correct operation on every hardware revision.

## Configuration details

The generic software Crypto API ZSTD default is configured at level 1 for the kernel's generic ZSTD codec, including generic ZSTD zswap. This is separate from ZRAM-IR's own fast-compression behavior and hardware-specific Intel QAT backends.

The retained `CONFIG_ZEN_INTERACTIVE` changes are limited to the existing evdev asynchronous RCU and P-State schedutil-selection behavior; this fork does not import a broad set of unrelated Zen memory/scheduler defaults.

NAP learning persists across boots, with periodic saves. The package includes `napctl` and the offline `/usr/share/nap/napviz.html` viewer generated from the built kernel's model. See [NAP-TOOLS.md](NAP-TOOLS.md).

## Scope

This is an enthusiast kernel project for SteamOS, not an official Valve kernel or a general-purpose Linux distribution. Keep a recovery route available, read installer prompts, and retain a known-good boot option whenever possible.
