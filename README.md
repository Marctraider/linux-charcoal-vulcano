# Charcoal — tuned SteamOS 3.10 / Linux 7.3 kernel

Charcoal is a tuned Linux kernel for the **Steam Deck**, based on Valve's SteamOS 3.10 kernel source. It aims to improve gaming performance and frametime stability through a focused set of scheduler, CPU-frequency, memory, storage, and compiler optimizations, while retaining Valve's Steam Deck platform support and boot identity.

This repository contains the source integration, configuration, patch inputs, build recipe, and validation tooling. It does not currently publish an installable kernel package.

**Kernel base**

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

**Tuning and kernel changes**

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
- Valve Steam Deck / Van Gogh platform drivers and device support retained, including Steam Deck HID, MFD, LED, and sensor modules.
- Additional configuration keeps relevant Steam Deck audio, storage, Bluetooth, input, and platform support built in where specified by the overlay.

### Compiler and optimization

- Clang/LLVM toolchain for target and host compilation.
- Kernel optimization level **O3** via `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3=y`.
- **Full Clang LTO** via `CONFIG_LTO_CLANG_FULL=y`.
- **Polly** enabled via `CONFIG_POLLY_CLANG=y`.
- AMD Zen 2 target via `KCFLAGS=-march=znver2`.
- Debug symbols and stripping follow the package recipe; PKGBUILD disables Arch's debug package and generic strip option (`!debug`, `!strip`).

**Patch set**

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

**Built-in kernel command line**

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
