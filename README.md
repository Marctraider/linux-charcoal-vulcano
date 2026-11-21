# Charcoal — tuned SteamOS 3.10 / Linux 7.3 kernel

> [!WARNING]
> ## ARCHIVED — NO LONGER ACTIVELY DEVELOPED
>
> **This repository is no longer maintained. Do not expect new updates or fixes here.**
>
> This project started as an experimental kernel-tuning effort. Development later moved to a cleaner, more deliberate build in the Conservative successor repository.
> Active development has moved to **[linux-charcoal-conservative](https://github.com/Marctraider/linux-charcoal-conservative)**, the successor project. **That repository is currently private** and may not be accessible until it is made public.

This repository is retained for historical source, documentation, and published releases. It is not the active development target.

Charcoal is a tuned Linux kernel for the **Steam Deck**, based on Valve's SteamOS 3.10 kernel source. It aims to improve gaming performance and frametime stability through a focused set of CPU-frequency, scheduler-extension, and compiler optimizations, while retaining Valve's Steam Deck platform support and boot identity.

This repository contains the source integration, configuration, patch inputs, build recipe, validation tooling, and the published SteamOS 3.10 / Linux 7.3 Charcoal package.

## Install the published SteamOS 3.10 build

The current published package is **Build 100**, built by GitHub Actions from source commit `f4fd0112f7268bcd6de1ab198caf0d67b97a6dff`: [view the Build 100 release and packages](https://github.com/Marctraider/linux-charcoal-vulcano/releases/tag/steamos-3.10-linux-7.3-build-100).

The release contains the kernel package, its matching headers package, and a `SHA256SUMS` manifest. The installer on `master` downloads these exact assets and verifies the manifest and both package hashes before changing packages. It also checks that the kernel package retains Valve's `linux-neptune-73` boot identity and that the headers match the kernel's module release directory. No kernel `.config` options are used as installation gates.

The installer supports a clean SteamOS 3.10 installation when the stock Valve `linux-neptune-73` kernel and its existing boot files are present, as well as an upgrade from an existing Charcoal 7.3 installation. On a clean install, it replaces the stock kernel rather than keeping it as a fallback. If the exact previous package archives are present in pacman's cache, it stages them for rollback; otherwise automatic package rollback may not be available.

Download and run the installer from Desktop Mode:

```bash
curl -fL --retry 3 --proto '=https' --proto-redir '=https' \
  -o install-charcoal.sh \
  https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/master/install-charcoal.sh
sudo bash install-charcoal.sh
```

The installer downloads the public GitHub Release asset directly. It does not use the GitHub Actions artifact API or require a GitHub token. Release redirects are fetched with cache-busting URLs and retried on transient authorization responses to avoid stale signed-URL HTTP 401 errors.

After installation, reboot into Charcoal Linux 7.3 and run the status utility.

Build 100 predates the utility being bundled in the kernel package. Until a package built from the updated PKGBUILD is published, fetch and run the script directly:

```bash
curl -fL --retry 3 \
  https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/master/charcoal-status \
  -o /tmp/charcoal-status
sudo bash /tmp/charcoal-status
```

The next kernel package build installs it as `/usr/bin/charcoal-status`, after which it can be run with:

```bash
sudo charcoal-status
```

Release SHA256SUMS file SHA-256:

```text
d08ca13f1afa536db076c9a8db48b6af4acf4d26b8cb1c3b5bbe1b37e6fdb72c
```

Package SHA-256 values are published in the [release SHA256SUMS asset](https://github.com/Marctraider/linux-charcoal-vulcano/releases/download/steamos-3.10-linux-7.3-build-100/SHA256SUMS).

**Changes from the stock Valve kernel**

- **CPU scheduling**
  - LAVD (`scx_lavd`) is configured in **performance mode** (`--performance`) as the default scheduler through a systemd service. Autopilot and Autopower are not enabled.
  - The installer installs the SteamOS `scx-scheds` userspace package and enables the service to start LAVD automatically on boot.
  - The kernel provides sched_ext/BPF support; the userspace service loads LAVD and keeps it active across reboots.

- **CPU frequency and platform**
  - AMD P-State EPP active mode and boost changes.
  - Higher Van Gogh CPU-frequency ceiling, up to 4.2 GHz; the higher limit must be enabled in UEFI.

- **Compiler and optimization**
  - Clang/LLVM is the kernel compiler toolchain.
  - Full Clang LTO is enabled as a separate link-time optimization mode.
  - Polly is an LLVM loop-optimization pass supplied by the LLVM `polly` package; it is not a linker or a standalone kernel patch.
  - The small `latest-clang-polly.patch` adds the Linux Kbuild/Kconfig integration needed to load `LLVMPolly.so` and pass Polly's optimization flags during kernel compilation. It does not contain the Polly optimizer itself.
  - AMD Zen 2 target enforced with `-march=znver2 -mtune=znver2`; a force-included compile-time guard rejects any kernel C translation unit that does not expose Clang's Zen 2 target macros. The build identity is embedded in `/proc/version` for runtime status reporting.
  - O2 is intentional. Kernel-wide O3 has shown only a small average gain in broad Linux benchmarks, with workload-dependent regressions; O2 avoids unnecessary code growth in branch-heavy hot paths while retaining full Clang LTO and the Zen 2 target.

The Zen 2 check is not inferred from the Deck's CPU model or `CONFIG_CPU_SUP_AMD`. A successful build must pass the Clang target probe and compile every kernel C translation unit with the guard. `charcoal-status` reports the running kernel as verified only when its embedded build identity is present.

- **Steam Deck support**
  - Valve Steam Deck and Van Gogh platform support retained.
  - Valve boot and module identity retained.

**Built-in kernel command line**

The kernel configuration embeds this exact command line:

```text
amd_pstate.epp_boost=1 mitigations=off
```

| Parameter | Effect |
|---|---|
| `amd_pstate.epp_boost=1` | Enables the AMD P-State EPP boost feature added by the patch set. |
| `mitigations=off` | Disables CPU vulnerability mitigations. |

These are the kernel's **built-in command-line parameters** from `CONFIG_CMDLINE`; they are not compiler flags. The configuration sets `CONFIG_CMDLINE_BOOL=y` and leaves `CONFIG_CMDLINE_OVERRIDE` unset, so the boot loader can still supply its own command line according to the kernel's normal command-line combination rules.

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
| Architecture / target | `x86_64` / AMD Zen 2 (`-march=znver2 -mtune=znver2`, compile-time guarded) |
| Output packages | `linux-charcoal-73`, `linux-charcoal-73-headers` |
| SteamOS boot/module identity | `linux-neptune-73` |

The source archive contains Valve's embedded Git repository and matching `config.x86_64` and `config-neptune` configuration fragments. The build checks out the pinned commit from that embedded repository. Do not substitute a different Valve tag, SteamOS release, or generic upstream source tree.
