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

The pinned NAP patch is applied with `git apply --check` first. The API adapter, `automation/fix-nap-kernel-api.py`, uses narrow, fail-closed compatibility checks for the Linux 7.2+ IRQ counter layout and binary sysfs attribute constness. It rejects unexpected or partially matching source instead of guessing.

The kernel configuration enables `CONFIG_CPU_IDLE=y` and `CONFIG_CPU_IDLE_GOV_NAP=y`, and selects NAP at boot with `cpuidle.governor=nap`. The bootloader command line remains appendable because `CONFIG_CMDLINE_OVERRIDE` stays disabled. `CONFIG_CPU_IDLE_GOV_TEO=y` is also retained as a fallback: if NAP fails its boot-time self-test or cannot register, the standard TEO governor remains available. The explicit boot argument still selects NAP when it registers successfully.

## Package integration

The PKGBUILD includes the deterministic `nap-tools.tar.gz` bootstrap, resolves the current upstream tools during `prepare()`, and fails the build if upstream resolution or the reviewed integration fails. During packaging, `install-tools.py --require-resolved` verifies the fetched payload and builds the viewer from the actual patched NAP kernel weights.

Only the kernel package carries `linux-charcoal-73.install`: installation and upgrades enable the persistence service and timer without restarting an already active service; removal stops the timer, saves the current state through the service stop action, and disables the units. The headers package does not run these hooks. The kernel package name and SteamOS boot identity remain unchanged, so the custom installer does not need a NAP-specific package path.

## Validation status

- PKGBUILD shell syntax and pinned NAP patch SHA-256: passed in GitHub Actions.
- NAP API compatibility unit tests: passed (6 tests).
- NAP persistence and refresh-tool suites: passed (13 and 10 tests); deterministic bootstrap archive SHA-256 passed.
- PKGBUILD and package install-script syntax, plus NAP packaging wiring checks: passed.
- Patch application and required API checks against upstream Linux v7.3: passed.
- Valve source archive `linux-neptune-73-7.3.1.valve2-1.src.tar.gz`: downloaded and matched the PKGBUILD SHA-256.
- Embedded Valve commit `0ed55b10a784a0a0b518ecd20551659fde1d59c9`: found and checked out successfully.
- NAP patch application against that exact Valve source commit: passed.
- API adapter against the exact Valve source: passed without source edits; `git diff --check` passed.
- Kernel compile, package build, boot test, installer test, and gaming benchmark: not run.

The exact Valve source compatibility gate is now passed. The branch is still experimental and is not a production or installation candidate until compile-time validation and subsequent user-authorized testing are completed.

## Expected behaviour

NAP selects CPU idle states and whether to stop the scheduler tick. It is not a CPU-frequency governor or scheduler, and this integration makes no FPS-improvement claim. Its impact on wake latency, power, thermals, and frame pacing needs measurement on Steam Deck hardware.

For the persistence tools and post-boot diagnostics, see [NAP-TOOLS.md](NAP-TOOLS.md).


## Additional kernel-only ports under evaluation

This experiment also carries two independent upstream kernel-source changes:

- **DRM scheduler Round Robin default**: pinned in `drm_sched_rr_default.patch`; changes the default DRM scheduler policy from FIFO to RR. It has no userspace dependency.
- **Re-swappiness v1.2**: pinned in `re-swappiness-v1.2_backported.patch`; changes MGLRU so anonymous and file-backed memory are aged independently. It has no userspace dependency, but touches core memory-management code and needs exact-source compatibility validation.

Neither port adds the original repository's controller drivers, SDL environment script, SMU tools, or other unrelated userspace components. NAP's persistence tools remain a separate component.

The patch-validation workflow prepares and checks the exact Valve 7.3.1 source without compiling the kernel. The kernel build workflow is manual-only; ordinary patch commits do not start a kernel build. No compile, package, boot, installer, or gaming benchmark result is implied by adding these candidates.
