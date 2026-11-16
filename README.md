# Charcoal — tuned SteamOS 3.10 / Linux 7.3 kernel

Charcoal is a tuned Linux kernel for the **Steam Deck**, based on Valve's SteamOS 3.10 kernel source. It aims to improve gaming performance and frametime stability through a focused set of scheduler, CPU-frequency, memory, storage, and compiler optimizations, while retaining Valve's Steam Deck platform support and boot identity.

This repository contains the source integration, configuration, patch inputs, build recipe, and validation tooling. It does not currently publish an installable kernel package.

**Changes from the stock Valve kernel**

- **CPU scheduling and idle:** BORE, POC Selector, NAP CPUIdle governor (TEO fallback).
- **CPU frequency and platform:** AMD P-State EPP active mode and boost changes; Zen Interactive changes (evdev RCU and schedutil dependency); higher Van Gogh CPU-frequency ceiling.
- **Memory and compression:** LRU CAST; ZRAM as a module with LZ4 primary compression and ZSTD ZRAM-IR recompression; ZSWAP disabled; ZSTD Crypto API default level set to 1.
- **Storage and graphics:** ADIOS I/O scheduler as the default; DRM scheduler Round Robin as the compiled default instead of FIFO.
- **Compiler and optimization:** Clang/LLVM, O3, full Clang LTO, Polly, and AMD Zen 2 targeting via `-march=znver2`.
- **Steam Deck support:** Valve's Steam Deck and Van Gogh platform support and boot/module identity are retained.

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
