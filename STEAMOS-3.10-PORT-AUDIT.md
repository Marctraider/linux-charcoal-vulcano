# SteamOS 3.10 / Linux 7.3 source and port record

This file preserves source identity and compatibility notes from the original 7.3 port investigation. It is historical build documentation, not a statement that the port is still unbuilt.

## Exact Valve source

- Package: `linux-neptune-73`
- Version: `7.3.1.valve2-1`
- Source archive: https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-3.10/linux-neptune-73-7.3.1.valve2-1.src.tar.gz
- Signature: append `.sig` to the archive URL.
- Archive SHA-256: `a6316acc22954d0685ac923248995246789a1f3b5ee6890d378ce2c3efa25af8`
- Valve source tag: `7.3.1-valve2`
- Resolved commit: `0ed55b10a784a0a0b518ecd20551659fde1d59c9`

Do not substitute valve1, generic upstream v7.3.1, or another SteamOS source snapshot. The archive contains the embedded bare Git repository and matching `config.x86_64` / `config-neptune` fragments.

## Package and boot identity

- Recipe: `PKGBUILD`
- Packages: `linux-charcoal-73` and `linux-charcoal-73-headers`
- Boot/module identity: `linux-neptune-73`
- Architecture: x86_64, Steam Deck Zen 2 compiler target `-march=znver2`
- Installer: `install-charcoal.sh`; it does not reboot automatically.

## Retained Linux 7.3 feature scope

The consolidated baseline retains BORE, POC Selector, ADIOS and udev integration, LRU CAST, ZRAM-IR, AMD P-State EPP changes, NTSYNC, Steam Deck drivers/configuration, NAP CPUIdle with TEO fallback, DRM scheduler Round Robin default, Clang/LLVM, Zen 2 targeting, O3, full Clang LTO and Polly.

ZRAM is a module with LZ4 primary compression. ZSWAP is disabled. Btrfs is built in. Re-swappiness is omitted. The built-in command line includes `amd_pstate.epp_boost=1 mitigations=off cpuidle.governor=nap`; disabling CPU vulnerability mitigations is a security/performance trade-off.

NAP integration details and pinned source are documented in `NAP-PORT.md`; userspace persistence tooling is documented in `NAP-TOOLS.md`.

## Patch application and validation rules

The authoritative patch list, checksums, application order and 7.3-specific adapters are in `PKGBUILD`, `PATCH-SOURCES.md`, `automation/` and the validation workflows.

- Verify the exact Valve source archive and pinned commit first.
- Verify every patch input against its recorded SHA-256.
- Apply patches in the order declared in `PKGBUILD`.
- Use the fail-closed Python porting helpers for source APIs that differ from the upstream patch context. Do not replace these with fuzz or guessed offsets.
- NAP is pinned to firelzrd commit `5092cfdbc615f2e1626e68ab03d3d9730364bcbd`; its 7.3 API compatibility helper is `automation/fix-nap-kernel-api.py`.
- DRM Round Robin is applied by exact-match replacement of the single Valve FIFO policy declaration; preparation fails if the expected declaration is absent or duplicated.
- Merge Valve's base config fragments with `config-charcoal`, run `olddefconfig`, and enforce the required config assertions in `PKGBUILD`.
- Preserve build logs, source provenance and package SHA-256 manifests.

A clean patch application is not proof of a successful build. The successful build procedure is encoded in `PKGBUILD` and `.github/workflows/build-kernel-7.3.yml`. The build workflow is manual-only and must not run automatically on pushes.

## Historical validation result

The consolidated build 77 completed successfully. The project owner reported that it installed and booted on a Steam Deck. This is a user-reported result for that build, not a guarantee for future builds or other hardware.

The earlier port-audit statements that NAP was excluded, that no successful build existed, or that work belonged on a separate validation branch are superseded and should not be used as current project guidance.

## Hardware validation

After any future authorized build, test boot, Btrfs root mounting, Wi-Fi, audio, Bluetooth, controllers, suspend/resume, storage, thermals and games on an actual Steam Deck. CI cannot prove hardware compatibility or performance.
