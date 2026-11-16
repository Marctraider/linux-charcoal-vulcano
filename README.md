# Charcoal — tuned SteamOS 3.10 / Linux 7.3 kernel

Charcoal is a tuned Linux kernel for the **Steam Deck**, based on Valve's SteamOS 3.10 kernel source. It aims to improve gaming performance and frametime stability through a focused set of scheduler, CPU-frequency, memory, storage, and compiler optimizations, while retaining Valve's Steam Deck platform support and boot identity.

This repository contains the source integration, configuration, patch inputs, build recipe, and validation tooling. It does not currently publish an installable kernel package.

## 1. Kernel base

Charcoal is based on Valve's SteamOS kernel package, not a generic upstream Linux tree.

| Item | Pinned base |
|---|---|
| Platform | SteamOS 3.10 / Steam Deck |
| Valve package | `linux-neptune-73` |
| Valve package version | `7.3.1.valve2-1` |
| Valve source tag | `7.3.1-valve2` |
| Valve source commit | `0ed55b10a784a0a0b518ecd20551659fde1d59c9` |
| Source archive SHA-256 | `a6316acc22954d0685ac923248995246789a1f3b5ee6890d378ce2c3efa25af8` |
| Architecture / target | `x86_64` / AMD Zen 2 (`-march=znver2`) |
| Output packages | `linux-charcoal-73`, `linux-charcoal-73-headers` |
| SteamOS boot/module identity | `linux-neptune-73` |

The source archive contains Valve's embedded Git repository and matching `config.x86_64` and `config-neptune` configuration fragments. The build checks out the pinned commit from that embedded repository. Do not substitute a different Valve tag, SteamOS release, or generic upstream source tree.

## 2. Tuning and kernel changes

The aim is a Steam Deck-oriented kernel configuration with tuned CPU scheduling, idle behavior, frequency management, memory reclaim, compression, and I/O scheduling. These are configuration and source changes; they are not a claim of measured performance gains.

### CPU scheduling, idle and frequency

- **BORE** CPU scheduler patch and configuration.
- **POC Selector** scheduler selection support.
- **NAP CPUIdle governor**, with **TEO** retained as the fallback governor. NAP selects CPU idle states; it is not the CPU task scheduler.
- **AMD P-State EPP** enabled in active mode (`CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3`).
- AMD P-State EPP boost changes, including the Valve 7.3 compatibility port.
- Zen-related evdev RCU and P-State schedutil-dependency changes, exposed through `CONFIG_ZEN_INTERACTIVE`. This profile does not change swap, reclaim, compaction, or THP defaults.
- Van Gogh higher CPU-frequency support patch.
- Steam Deck Zen 2 compiler target: `-march=znver2`.

### Memory and compression

- **LRU CAST** page-replacement/reclaim support enabled.
- **ZRAM** built as a module (`CONFIG_ZRAM=m`).
- **LZ4** is the primary ZRAM compressor; **ZSTD** is configured as the priority-1 recompressor for ZRAM-IR.
- ZRAM-IR immediate recompression is enabled by the integration helper (`vm.zram_recomp_immediate=1`).
- **ZSWAP is disabled** (`CONFIG_ZSWAP` is not set).
- No re-swappiness patch is applied; the kernel's normal `vm.swappiness` default is left alone.
- ZSTD Crypto API default compression level is set to 1.

ZRAM-IR configures an LZ4 write path and ZSTD recompression path. The packaged udev and systemd integration applies this to newly created ZRAM devices before their disksize is initialized, and avoids resetting an already active device.

### Storage, graphics and Steam Deck support

- **ADIOS** I/O scheduler patch and default-selection integration. The packaged udev rule selects ADIOS for non-loop, non-ZRAM block devices.
- **DRM scheduler Round Robin (RR)** is set as the compiled default instead of FIFO. This is GPU job scheduling, not CPU scheduling. The source change is applied by exact symbol match and fails if Valve's expected declaration is not unique.
- **NTSYNC** enabled.
- **Btrfs** built into the kernel.
- Valve Steam Deck / Van Gogh platform drivers and device support retained, including Steam Deck HID, MFD, LED, and sensor modules.
- Additional configuration keeps relevant Steam Deck audio, storage, Bluetooth, input, and platform support built in where specified by the overlay.

### Compiler and optimization

- Clang/LLVM toolchain for target and host compilation.
- Kernel optimization level **O3** via `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3=y`.
- **Full Clang LTO** via `CONFIG_LTO_CLANG_FULL=y`.
- **Polly** enabled via `CONFIG_POLLY_CLANG=y`.
- AMD Zen 2 target via `KCFLAGS=-march=znver2`.
- Debug symbols and stripping follow the package recipe; PKGBUILD disables Arch's debug package and generic strip option (`!debug`, `!strip`).

## 3. Patch set

The following patch inputs are listed by `PKGBUILD` and applied in that order. The pinned input checksums are in the same file.

| Patch input | Purpose |
|---|---|
| `vangogh_allow_higher_cpu_freq.patch` | Raises the allowed CPU-frequency ceiling for the Van Gogh / Steam Deck platform. |
| `latest-lru_cast.patch` | LRU CAST memory-reclaim integration. |
| `latest-zram-ir.patch` | ZRAM-IR kernel support. |
| `latest-amd-pstate-epp-02-cache-order.patch` | AMD P-State EPP boost series: cache/order component. |
| `latest-amd-pstate-epp-03-core.patch` | AMD P-State EPP boost core implementation. |
| `latest-o3.patch` | O3 kernel optimization support. |
| `latest-clang-polly.patch` | Clang Polly integration. |
| `latest-bore.patch` | BORE CPU scheduler. |
| `latest-poc-selector.patch` | POC scheduler selector. |
| `latest-adios.patch` | ADIOS I/O scheduler. |
| `latest-adios-default.patch` | ADIOS default-policy integration. |
| `latest-zen-01.patch` | Zen evdev RCU behavior change. |
| `latest-zen-02.patch` | Zen P-State schedutil dependency change. |
| `zstd-crypto-default-level-1.patch` | Sets the ZSTD Crypto API default level to 1. |
| `nap-6.12-v0.6.5.patch` | NAP CPUIdle governor, pinned to firelzrd commit `5092cfdbc615f2e1626e68ab03d3d9730364bcbd`. |
| `drm_sched_rr_default.patch` | Changes the DRM scheduler compiled default from FIFO to Round Robin. |

Additional source adaptations are applied by the build recipe rather than by standalone patch files:

- `automation/port-amd-pstate-epp-boost-73.py` ports the AMD P-State EPP boost core patch to Valve 7.3 and verifies required symbols.
- `automation/port-zen-cpufreq-7.3.py` adapts the Zen P-State Kconfig change to Valve 7.3.
- `automation/fix-nap-kernel-api.py` adapts the pinned NAP source to Valve 7.3 API differences.
- `automation/configure-zen-interactive.py` exposes the two Zen changes through `CONFIG_ZEN_INTERACTIVE`.
- `automation/fix-gud-tv-mode-fortify.py` applies a bounded-buffer compatibility fix in the GUD TV-mode path for the O3/Full-LTO build.
- The DRM RR change uses an exact-match replacement in `drivers/gpu/drm/scheduler/sched_main.c`; it does not rely on a fuzzy patch offset.

Patch application is fail-closed: the recipe checks expected source anchors and patch applicability and stops when the source no longer matches. It does not silently guess offsets or ignore failed patches.

## 4. Built-in kernel command line

The kernel configuration embeds this exact command line:

```text
amd_pstate.epp_boost=1 mitigations=off cpuidle.governor=nap
```

| Parameter | Effect |
|---|---|
| `amd_pstate.epp_boost=1` | Enables the AMD P-State EPP boost feature added by the patch set. |
| `mitigations=off` | Disables CPU vulnerability mitigations. |
| `cpuidle.governor=nap` | Selects NAP as the CPU idle governor at boot. TEO remains compiled in as a fallback. |

These are the kernel's **built-in command-line parameters** from `CONFIG_CMDLINE`; they are not compiler flags. The configuration sets `CONFIG_CMDLINE_BOOL=y` and leaves `CONFIG_CMDLINE_OVERRIDE` unset, so the boot loader can still supply its own command line according to the kernel's normal command-line combination rules.

The ZRAM-IR helper also writes `1` to `/proc/sys/vm/zram_recomp_immediate` when available. That is a runtime sysctl setting, not a boot command-line parameter.

## 5. Configuration highlights

The authoritative Charcoal configuration overlay is `config-charcoal`, merged with Valve's two configuration fragments before `olddefconfig`.

| Setting | Value |
|---|---|
| `CONFIG_X86_AMD_PSTATE` | `y` |
| `CONFIG_X86_AMD_PSTATE_DEFAULT_MODE` | `3` (active / EPP mode) |
| `CONFIG_CPU_IDLE_GOV_NAP` | `y` |
| `CONFIG_CPU_IDLE_GOV_TEO` | `y` |
| `CONFIG_SCHED_BORE` | `y` |
| `CONFIG_SCHED_POC_SELECTOR` | `y` |
| `CONFIG_LRU_CAST` | `y` |
| `CONFIG_ZRAM` | `m` |
| `CONFIG_ZRAM_DEF_COMP` | `"lz4"` |
| `CONFIG_ZRAM_MULTI_COMP` | `y` |
| `CONFIG_ZSWAP` | disabled |
| `CONFIG_NTSYNC` | `y` |
| `CONFIG_BTRFS_FS` | `y` |
| `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3` | `y` |
| `CONFIG_LTO_CLANG_FULL` | `y` |
| `CONFIG_POLLY_CLANG` | `y` |
| `CONFIG_IO_DELAY_NONE` | `y` |

The full configuration, including disabled drivers and debug options, is in `config-charcoal` and the Valve base fragments. The build validates required settings after `olddefconfig`.

## 6. Compilation

The canonical recipe is `PKGBUILD`; the manual GitHub Actions workflow is `.github/workflows/build-kernel-7.3.yml`. The workflow is **manual-only** (`workflow_dispatch`); pushes and README edits do not start a kernel build.

### Toolchain and make variables

The recipe invokes make with:

```bash
make LLVM=1 KCFLAGS="-march=znver2" \
  CC=clang \
  HOSTCC=clang \
  HOSTCXX=clang++ \
  <make-target>
```

The effective build choices are:

- LLVM tools selected through `LLVM=1`.
- `clang` for target C compilation and host C compilation; `clang++` for host C++.
- `-march=znver2` passed through `KCFLAGS` to target Steam Deck's Zen 2 CPU.
- O3, Full Clang LTO, and Polly selected through Kconfig.
- `make olddefconfig` resolves the merged Valve and Charcoal configuration before the required-option assertions.
- `make all` compiles the kernel; bpftool's `vmlinux.h` and CO-RE feature are also built.
- `makepkg` packages the kernel and matching headers. Module installation uses `ZSTD_CLEVEL=19` for package compression; this is not a kernel runtime parameter.

### Build sequence

1. Verify the Valve source archive SHA-256 and pinned embedded Git commit.
2. Resolve and verify the patch inputs and their SHA-256 checksums.
3. Apply the patch set in the order listed above, using the Valve 7.3 compatibility helpers where required.
4. Merge `config.x86_64`, `config-neptune`, and `config-charcoal`.
5. Run LLVM `olddefconfig` and assert required configuration values.
6. Build the kernel and bpftool, then package `linux-charcoal-73` and `linux-charcoal-73-headers`.
7. Retain source-preparation logs, build logs, package metadata, and SHA-256 checksums.

The CI workflow uses an Ubuntu 24.04 runner, configures 16 GB of build swap, builds an Arch Linux LLVM toolchain container, and runs the package build inside that container. It uploads packages and logs as a temporary Actions artifact. The workflow must be started manually from `master`.

### Reproducibility and validation

- Valve source archive checksum and exact source commit are pinned.
- Patch inputs are checksum-verified.
- Porting helpers validate expected source structure and fail on unexpected changes.
- `git diff --check` validates patched-source whitespace.
- `PKGBUILD` checks required Kconfig values after `olddefconfig`.
- Build logs and package SHA-256 manifests are retained with the build artifact.

A successful compile or package operation does not prove bootability, hardware compatibility, stability, or improved performance. Hardware testing is required for every future build.

## 7. Build and test status

Build 77 completed successfully, and the project owner reported that it installed and booted on a Steam Deck. This records one tested build only; it is not a guarantee for later source changes or other devices.

There is currently no published binary package in this repository. The installer is not configured with a downloadable release. A future kernel build, artifact retention, validation, or publication must be explicitly authorized.

## 8. Repository map

- `PKGBUILD` — authoritative source, patch, configuration, compile, and packaging recipe.
- `config-charcoal` — Charcoal Kconfig overlay.
- `PATCH-SOURCES.md`, `logs/patch-source-overrides-stable.json`, and `logs/patch-lock.json` — patch provenance and source locks.
- `automation/` — Valve 7.3 compatibility adapters and configuration helpers.
- `NAP-PORT.md`, `NAP-TOOLS.md` — NAP governor port and userspace learning/persistence integration details.
- `.github/workflows/build-kernel-7.3.yml` — manual-only kernel build workflow.
- `tests/` — patch, configuration, helper, and installer validation tests.
- `install-charcoal.sh` — installer and read-only `--check-only` diagnostics.

## 9. Safety and project policy

- Keep a recovery route and retain the stock SteamOS kernel.
- Do not assume a compile-time default is active at runtime unless the running kernel exposes a way to verify it. In particular, DRM scheduler policy visibility depends on the kernel's sysfs interface.
- Do not claim performance gains without repeatable benchmarks.
- Do not publish or install packages unless the exact build, checksums, and hardware validation are known.
