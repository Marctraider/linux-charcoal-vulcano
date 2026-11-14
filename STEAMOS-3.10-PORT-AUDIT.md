# SteamOS 3.10 / Linux 7.3 port audit

Status: preparation only. This branch is intentionally not installable and must not publish a release.

## Target source

Use Valve's exact SteamOS 3.10 source package:

- Package: `linux-neptune-73`
- Version: `7.3.1.valve2-1`
- Source archive: https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-3.10/linux-neptune-73-7.3.1.valve2-1.src.tar.gz
- Signature: append `.sig` to the archive URL.
- Official source index: https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-3.10/

The source index lists both valve1 and valve2 builds. The selected target is valve2, matching the user's installed `linux-neptune-73 7.3.1.valve2-1`. Do not substitute valve1, generic upstream v7.3.1, or a newer unrelated SteamOS source snapshot.

## Current pipeline findings

The current stable pipeline is 7.2-specific in several coupled places:

- `PKGBUILD` currently names `linux-charcoal-72` / `linux-neptune-72` and bootstraps from `7.2.7-valve2`.
- `automation/prepare-pkgbuild-7.2.py` hard-codes the 7.2 package series and 7.2-specific patch dispatch.
- `automation/prepare-steamos-stable.py` resolves the stable SteamOS image, not the 3.10 preview image.
- `.github/workflows/push.yml` is named and validated as a 7.2 build, and uses the stable source resolver.
- The installer is explicitly 7.2-specific and removes the matching stock kernel before installing. It must not be reused unchanged for a test kernel intended to coexist with stock 7.3.

The 7.2 branch contains source-specific adapters for POC Selector, ADIOS, LRU CAST, NAP and Zen. These are not evidence that the same patches apply to 7.3. Each patch must be checked against the exact Valve 7.3.1.valve2 source, and each required incompatibility must receive a reviewed adapter with tests. Unknown source layouts must fail closed.

## Required port sequence

1. Extract and inspect Valve's exact source package, including its PKGBUILD, source repository/tag, `config`, and `config-neptune`.
2. Build a 7.3-only package identity (`linux-charcoal-73`) that can coexist with `linux-neptune-73` and the existing Charcoal 7.2 package during testing.
3. Rebase each retained patch family independently: BORE, POC Selector, ADIOS, LRU CAST, ZRAM-IR, NAP, AMD P-State EPP, Zen, Van Gogh, and the retained compiler/optimization changes.
4. Keep the fork's selected features and remove only the already-approved userspace gaming extras and bundled controller-driver package/workarounds.
5. Merge Valve's exact 7.3 config layers first, then Charcoal overrides; run `olddefconfig` and assert required options. In particular, verify Btrfs and Steam Deck hardware support remain available.
6. Add 7.3-specific adapter tests and a validation-only GitHub Actions workflow. Validation branches and pull requests must never publish stable releases.
7. Produce a test package and inspect package metadata, module paths, initramfs hooks, and boot entries. Keep the stock SteamOS 7.3 kernel installed as the fallback.
8. Only after CI succeeds should the user test boot, graphics, Wi-Fi, audio, Bluetooth, controllers, suspend/resume, and Btrfs on the Deck.

## Safety gates

- Do not modify `master` or its stable release workflow as part of this port.
- Do not publish a stable release from this branch.
- Do not make the installer remove `linux-neptune-73` during the initial coexistence test.
- Do not claim compatibility or a successful boot based only on patch application or CI.
- Preserve the user's known-good stock SteamOS kernel as the recovery path.

This document records the audit and plan only. It does not claim that any patch has been ported or that a 7.3 kernel has been built.

## Verified Valve source identity

The official source archive was downloaded and its embedded bare Git repository inspected in GitHub Actions run [43593241890](https://github.com/Marctraider/linux-charcoal-vulcano/actions/runs/43593241890).

- Embedded repository: `archlinux-linux-neptune`
- Exact tag: `7.3.1-valve2` (annotated tag)
- Resolved commit: `0ed55b10a784a0a0b518ecd20551659fde1d59c9`
- Commit subject: `linux-integration 7.3.1-valve2`
- Commit author/committer date: 2026-11-13 16:08:37 -0800
- Git pack: 14,163,020 objects; 3,633,624 KiB packed

The PKGBUILD independently confirms `_tag=7.3.1-valve2` and uses the Valve `linux-integration` repository. The next validation run checks out this resolved commit and audits source paths/config fragments. No retained Charcoal patch has yet been applied to this tree.
