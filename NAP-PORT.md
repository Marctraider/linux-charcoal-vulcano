# NAP governor port for SteamOS 3.10 / Linux 7.3

**Experimental branch only:** `experiment/steamos-3.10-linux-7.3-nap`.

This branch integrates the NAP (Neural Adaptive Predictor) CPUIdle governor into the Charcoal 7.3 kernel source preparation. It does not change the validation branch, `master`, the installer, or the published kernel package.

## Pinned upstream source

- Upstream project: https://github.com/firelzrd/nap
- Governor patch: NAP 0.6.5 for Linux 6.12
- Upstream commit: `5092cfdbc615f2e1626e68ab03d3d9730364bcbd`
- Local patch: `nap-6.12-v0.6.5.patch`
- SHA-256: `4d4ac50ba014de33638a2efe9c6adc507b888c6d090aa29ea17b2a4686de4e07`

The patch is pinned in the PKGBUILD. It is not fetched from a moving upstream branch during a build.

## Linux 7.3 compatibility

The upstream patch is applied with `git apply --check` first. Then `automation/fix-nap-kernel-api.py` performs narrowly scoped, fail-closed compatibility edits for the Linux 7.2+ IRQ counter layout and binary sysfs attribute constness. Unexpected or partially matching source is rejected rather than guessed.

The kernel configuration enables `CONFIG_CPU_IDLE_GOV_NAP=y` and selects it at boot with `cpuidle.governor=nap`. The bootloader command line remains appendable because `CONFIG_CMDLINE_OVERRIDE` stays disabled.

## Validation status

- PKGBUILD shell syntax: passed in GitHub Actions.
- Pinned patch SHA-256: passed in GitHub Actions.
- NAP API compatibility unit tests: passed (6 tests).
- Patch application and API adaptation against upstream Linux v7.3: passed in GitHub Actions.
- Application against Valve's exact embedded 7.3.1-valve2 source commit: not yet verified.
- Kernel build, package build, boot test, and gaming benchmark: not run.

A passing upstream-source patch check is not a substitute for checking Valve's exact source archive. This branch is not a production or installation candidate until that check and subsequent user-authorized testing are complete.

## Expected behaviour

NAP selects CPU idle states and whether to stop the scheduler tick. It is not a CPU-frequency governor or scheduler, and this integration makes no FPS-improvement claim. Its impact on wake latency, power, thermals, and frame pacing needs measurement on Steam Deck hardware.

For the persistence tools and post-boot diagnostics, see [NAP-TOOLS.md](NAP-TOOLS.md).
