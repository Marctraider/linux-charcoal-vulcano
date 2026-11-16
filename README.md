# Charcoal — SteamOS 3.10 / Linux 7.3

Custom Steam Deck kernel based on Valve's exact SteamOS 3.10 Linux 7.3 source, with the retained Charcoal patches and configuration.

The active development branch is `master`. The project is no longer organized as a separate NAP experiment or validation branch. NAP remains one of the included CPUIdle features; it is not the project name or release suffix.

> **Status:** Build 77 was successfully installed and booted on a Steam Deck, as reported by the project owner. This is a hardware result for that specific build, not a guarantee for other devices or future changes.

## Target and source identity

- Platform: SteamOS 3.10 / Steam Deck
- Valve package: `linux-neptune-73`
- Valve package version: `7.3.1.valve2-1`
- Valve source tag: `7.3.1-valve2`
- Pinned Valve source commit: `0ed55b10a784a0a0b518ecd20551659fde1d59c9`
- Official source archive SHA-256: `a6316acc22954d0685ac923248995246789a1f3b5ee6890d378ce2c3efa25af8`
- Charcoal package names: `linux-charcoal-73` and `linux-charcoal-73-headers`
- Boot/module identity: `linux-neptune-73`
- Architecture: x86_64, tuned for Steam Deck Zen 2 with `-march=znver2`

This is built from Valve's matching SteamOS source archive and configuration fragments, not from generic upstream Linux 7.3. Do not substitute another Valve tag, a generic upstream source tree, or a different SteamOS release.

## Included kernel features

The current baseline retains the following features and integrations:

- NAP CPUIdle governor, pinned to firelzrd NAP v0.6.5, with TEO compiled as fallback.
- DRM scheduler Round Robin compiled as the default policy.
- BORE CPU scheduler.
- POC Selector.
- ADIOS I/O scheduler and udev integration.
- LRU CAST reclaim.
- ZRAM as a module, with LZ4 as the primary compression algorithm and ZRAM-IR runtime configuration.
- ZSWAP disabled in the kernel configuration.
- NTSYNC.
- Btrfs built into the kernel.
- AMD P-State EPP changes.
- Steam Deck / Van Gogh platform support and retained device-specific patches.
- Clang/LLVM toolchain, O3 optimization, full Clang LTO and Polly.

The re-swappiness patch is intentionally omitted. ZRAM remains enabled; ZSWAP is compiled out. The built-in command line includes `amd_pstate.epp_boost=1 mitigations=off cpuidle.governor=nap`. Disabling CPU vulnerability mitigations is a security trade-off.

NAP controls CPU idle-state selection. It is not a CPU task scheduler or a GPU-frequency booster. The DRM Round Robin setting concerns GPU job scheduling, not CPU scheduling. The source patch sets the compiled default; runtime verification may be unavailable if the running kernel does not expose the DRM scheduler sysfs parameter.

## Build recipe and reproducibility

The authoritative build recipe is `PKGBUILD`, driven by the Linux 7.3 GitHub Actions workflow in `.github/workflows/build-kernel-7.3.yml`.

The successful build procedure is:

1. Download the official Valve `linux-neptune-73 7.3.1.valve2-1` source archive and verify its SHA-256.
2. Use the embedded Git repository and check out the exact pinned Valve commit.
3. Fetch the pinned patch inputs and verify their recorded checksums.
4. Apply patches in the order declared in `PKGBUILD`. The NAP and DRM Round Robin changes use explicit, fail-closed handling; NAP also uses the 7.3 API compatibility helper.
5. Apply the reviewed 7.3-specific source adaptations and normalize patch whitespace.
6. Merge Valve's `config.x86_64` and `config-neptune` fragments with `config-charcoal`.
7. Run `olddefconfig` using Clang/LLVM and validate the required kernel options.
8. Compile the kernel and bpftool, then package the kernel and matching headers.
9. Inspect the package metadata, boot identity, embedded configuration, build logs and SHA-256 manifest.

Important build details:

- `-march=znver2` is supplied through `KCFLAGS`; Valve 7.3 does not provide the old MZEN2 Kconfig selector.
- The DRM Round Robin patch expects exactly one FIFO policy declaration and fails if the source no longer matches.
- The NAP patch is pinned to upstream commit `5092cfdbc615f2e1626e68ab03d3d9730364bcbd`; the compatibility helper adapts the source for Valve 7.3.
- Keep the source archive checksum, patch checksums, patch order, config assertions and build logs together. A successful patch application alone does not prove compilation.
- A successful compile/package does not prove boot or runtime stability. Hardware testing is required after any future kernel build.

Patch provenance, source overrides, patch-lock validation, porting helpers and tests are retained in the repository. See `PATCH-SOURCES.md`, `PKGBUILD`, `automation/`, `tests/` and the workflow files.

## Installation

The installer is `install-charcoal.sh`. It targets SteamOS 3.10 and the `linux-neptune-73` boot identity. It supports a read-only diagnostic mode:

```bash
bash install-charcoal.sh --check-only
```

Run the installer interactively only when a compatible kernel package bundle is available and its checksums and package identity have been verified:

```bash
bash install-charcoal.sh
```

The installer does not reboot automatically. Retain a recovery route and do not remove the stock SteamOS kernel unless you understand the recovery implications. Post-install rollback is best-effort and depends on the previous packages still being present in the pacman cache.

**No currently published binary package is maintained as part of this source baseline.** A future installable release requires a separately authorized build, validation and publication.

## Diagnostics

- `charcoal-status` reports kernel build options and runtime state after boot.
- Installer `--check-only` performs read-only platform, package and boot-chain checks.
- The test suite under `tests/` covers patch handling, configuration validation, installer behavior and status reporting.

A missing runtime sysfs control must be reported as unavailable, not treated as proof that a compile-time default is inactive. In particular, the DRM scheduler policy can only be confirmed at runtime when the running kernel exposes its policy parameter.

## Project policy

- `master` is the sole intended development branch.
- SteamOS 3.10 / Linux 7.3 is the sole active kernel baseline.
- Preserve patch provenance, build scripts, configuration, tests and source-level diagnostics.
- Do not claim performance improvements without repeatable measurements.
- Do not claim boot success for a build that has not been tested on hardware.
- Do not publish packages or releases without explicit authorization.
