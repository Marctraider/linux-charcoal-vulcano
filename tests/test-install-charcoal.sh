#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/install-charcoal.sh"
fail(){ echo "test failure: $*" >&2; exit 1; }
bash -n "$INSTALLER" || fail "installer syntax"
grep -Fxq 'pkgbase=linux-charcoal-73' "$ROOT/PKGBUILD" || fail "package identity"
source_block="$(sed -n '/^source=(/,/^)/p' "$ROOT/PKGBUILD")"
for patch in vangogh_allow_higher_cpu_freq.patch latest-amd-pstate-epp-02-cache-order.patch latest-amd-pstate-epp-03-core.patch latest-clang-polly.patch; do
  grep -Fq "$patch" <<< "$source_block" || fail "current kernel patch input $patch"
done
for excluded in nap-6.12-v0.6.5.patch drm_sched_rr_default.patch latest-bore.patch; do
  if grep -Fq "$excluded" <<< "$source_block"; then fail "excluded patch input $excluded"; fi
done
if grep -Eiq 're-swappiness' "$ROOT/PKGBUILD"; then fail "re-swappiness must remain omitted"; fi
source "$INSTALLER"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'ID=steamos\nVERSION_ID=3.10\n' > "$tmp/os-release"
verify_host_platform "$tmp/os-release" || fail "SteamOS 3.10 host"
sed 's/3.10/3.9.5/' "$tmp/os-release" > "$tmp/old"
if verify_host_platform "$tmp/old" >/dev/null 2>&1; then fail "unsupported SteamOS accepted"; fi

cat > "$tmp/kernel.config" <<'EOF'
CONFIG_CPU_MITIGATIONS=y
CONFIG_X86_AMD_PSTATE=y
CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3
CONFIG_CMDLINE_BOOL=y
CONFIG_CMDLINE="amd_pstate.epp_boost=1 mitigations=off"
# CONFIG_CMDLINE_OVERRIDE is not set
CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y
# CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3 is not set
CONFIG_LTO_CLANG_FULL=y
CONFIG_POLLY_CLANG=y
CONFIG_SCHED_CLASS_EXT=y
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_PERF_EVENTS=y
CONFIG_UPROBES=y
CONFIG_UPROBE_EVENTS=y
CONFIG_BPF_EVENTS=y
CONFIG_BPF_JIT=y
CONFIG_BPF_JIT_ALWAYS_ON=y
CONFIG_BPF_JIT_DEFAULT_ON=y
CONFIG_DEBUG_INFO_DWARF5=y
CONFIG_DEBUG_INFO_BTF=y
CONFIG_TRACEPOINTS=y
CONFIG_FTRACE=y
CONFIG_FTRACE_SYSCALLS=y
CONFIG_NTSYNC=y
# CONFIG_ZSWAP is not set
EOF
mkdir -p "$tmp/bin"
cat > "$tmp/bin/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
 -Qp)
   case "$2" in
     *headers*) echo 'linux-charcoal-73-headers 7.3.1.valve2.cc1-1';;
     *) echo 'linux-charcoal-73 7.3.1.valve2.cc1-1';;
   esac;;
 -Qq)
   [[ "${CHARCOAL_TEST_INSTALLED:-0}" == "1" && "$2" == "linux-charcoal-73" ]];;
 *) exit 2;;
esac
EOF
cat > "$tmp/bin/bsdtar" <<'EOF'
#!/usr/bin/env bash
case "$1" in
 -tf)
   if [[ "$2" == *headers* ]]; then
     printf '%s\n' 'usr/lib/modules/7.3.1-neptune-73/build/.config' 'usr/lib/modules/7.3.1-neptune-73/build/Kconfig' 'usr/lib/modules/7.3.1-neptune-73/build/scripts/Kconfig'
   else printf '%s\n' 'usr/lib/modules/7.3.1-neptune-73/pkgbase' 'usr/lib/modules/7.3.1-neptune-73/vmlinuz'; fi;;
 -xOf)
   if [[ "$2" == *headers* ]]; then cat "$CONFIG_FIXTURE"; else echo 'linux-neptune-73'; fi;;
 *) exit 2;;
esac
EOF
chmod +x "$tmp/bin/pacman" "$tmp/bin/bsdtar"
touch "$tmp/linux-charcoal-73.pkg.tar.zst" "$tmp/linux-charcoal-73-headers.pkg.tar.zst"
package_files=("$tmp/linux-charcoal-73.pkg.tar.zst" "$tmp/linux-charcoal-73-headers.pkg.tar.zst")
if PATH="$tmp/bin:$PATH" charcoal_upgrade_installed; then fail "missing Charcoal package treated as an upgrade"; fi
CHARCOAL_TEST_INSTALLED=1 PATH="$tmp/bin:$PATH" charcoal_upgrade_installed || fail "installed Charcoal package not detected for in-place upgrade"
PATH="$tmp/bin:$PATH" CONFIG_FIXTURE="$tmp/kernel.config" verify_kernel_package_identity package_files || fail "valid current kernel package identity/config rejected"
if PATH="$tmp/bin:$PATH" charcoal_upgrade_installed; then fail "missing Charcoal package treated as an upgrade"; fi
CHARCOAL_TEST_INSTALLED=1 PATH="$tmp/bin:$PATH" charcoal_upgrade_installed || fail "installed Charcoal package not detected for in-place upgrade"
grep -v 'CONFIG_SCHED_CLASS_EXT=y' "$tmp/kernel.config" > "$tmp/kernel-bad.config"
if ( PATH="$tmp/bin:$PATH" CONFIG_FIXTURE="$tmp/kernel-bad.config" verify_kernel_package_identity package_files >/dev/null 2>&1 ); then fail "package without sched_ext support accepted"; fi
python3 - "$tmp/build-artifact.zip" <<'PY'
import hashlib, sys, zipfile
files = {
 "linux-charcoal-73-7.3.1.valve2.cc1-1-x86_64.pkg.tar.zst": b"kernel-package-fixture",
 "linux-charcoal-73-headers-7.3.1.valve2.cc1-1-x86_64.pkg.tar.zst": b"headers-package-fixture",
}
manifest = "".join(hashlib.sha256(value).hexdigest() + "  " + name + "\n" for name, value in files.items())
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for name, value in files.items(): z.writestr(name, value)
    z.writestr("logs/SHA256SUMS-73", manifest)
    z.writestr("logs/makepkg-73.log", "build log")
    z.writestr("logs/prepare-73.log", "Applying pinned patch vangogh_allow_higher_cpu_freq.patch\nApplying pinned patch latest-amd-pstate-epp-02-cache-order.patch\nApplying pinned patch latest-amd-pstate-epp-03-core.patch\nApplying pinned patch latest-clang-polly.patch\n")
PY
extract_and_verify_build_artifact "$tmp/build-artifact.zip" "$tmp/unpacked" || fail "verified artifact extraction"
[[ -f "$tmp/unpacked/linux-charcoal-73-7.3.1.valve2.cc1-1-x86_64.pkg.tar.zst" ]] || fail "kernel package not extracted"
[[ -f "$tmp/unpacked/linux-charcoal-73-headers-7.3.1.valve2.cc1-1-x86_64.pkg.tar.zst" ]] || fail "headers package not extracted"
grep -Fq 'github.com/Marctraider/linux-charcoal-vulcano/releases/download/' "$INSTALLER" || fail "public release download URL"
grep -Fq 'RELEASE_TAG="steamos-3.10-linux-7.3-build-82"' "$INSTALLER" || fail "published build-82 release tag"
grep -Fq 'RELEASE_ARCHIVE="charcoal-steamos-3.10-linux-7.3-build-82.zip"' "$INSTALLER" || fail "published build-82 release archive name"
grep -Fq 'RELEASE_SHA256="225e5126487b56d6923b58b7f361eb7f158639e35a90e996ee96bae4d524de69"' "$INSTALLER" || fail "published build-82 ZIP checksum"
grep -Fq 'cachebust=$(date +%s)-$$-$RANDOM-$attempt' "$INSTALLER" || fail "each release download attempt must use a fresh cache-busting URL"
grep -Fq 'HTTP 401' "$INSTALLER" || fail "installer must document and retry stale signed-URL 401 responses"
grep -Fq 'after three fresh attempts' "$INSTALLER" || fail "release download retry limit"
grep -Fq "Cache-Control: no-cache" "$INSTALLER" || fail "release download must disable redirect caching"
if grep -Eq '\\$\\{run_number\\}|\\$\\{build_commit' "$INSTALLER"; then fail "installer must not reference Actions-only build metadata"; fi
if grep -Fq 'actions/artifacts/' "$INSTALLER"; then fail "installer must not use authenticated Actions artifact endpoint"; fi
grep -Fq 'Neither Valve linux-neptune-73 nor an existing Charcoal 7.3 kernel is installed' "$INSTALLER" || fail "existing 7.3 upgrade guard"
grep -Fq 'if charcoal_upgrade_installed; then' "$INSTALLER" || fail "existing Charcoal upgrade path"
grep -Fq 'Replacing the existing Charcoal 7.3 kernel and headers in one pacman transaction' "$INSTALLER" || fail "direct in-place package replacement"
grep -Fq 'verify_existing_boot_state || die' "$INSTALLER" || fail "fresh-install boot-chain check"
grep -Fq 'mktemp -d /dev/shm/charcoal-73-installer' "$INSTALLER" || fail "package staging must stay off root filesystem"
grep -Fq 'rm -f -- "$archive_path"' "$INSTALLER" || fail "release archive should be removed after extraction"
grep -Fq 'ln -s -- "$found" "$rollback_dir/' "$INSTALLER" || fail "rollback cache should be referenced without copying to root filesystem"
if grep -Fq 'cp -- "$found" "$rollback_dir/"' "$INSTALLER"; then fail "rollback package must not be duplicated"; fi
grep -Fq 'mkinitcpio -p linux-neptune-73' "$INSTALLER" || fail "initramfs generation"
grep -Fq 'verify_grub_entry' "$INSTALLER" || fail "GRUB verification"
grep -Fq 'sudo charcoal-status' "$INSTALLER" || fail "post-reboot runtime status instruction"
grep -Fq 'pacman -S --needed --noconfirm scx-scheds' "$INSTALLER" || fail "SteamOS LAVD userspace package installation"
grep -Fq 'ExecStart=/usr/bin/scx_lavd --performance' "$INSTALLER" || fail "LAVD must use fixed performance mode"
if grep -Eq -- '--autopilot|--autopower' "$INSTALLER"; then fail "LAVD automatic mode flags must remain disabled"; fi
grep -Fq 'systemctl enable charcoal-lavd.service' "$INSTALLER" || fail "persistent LAVD boot activation"
grep -Fq 'charcoal-lavd.service' "$INSTALLER" || fail "LAVD service unit"
if grep -Eq 'current_governor|nap-state\.service|nap-state-save\.timer|/sys/module/drm(_sched)?/parameters/sched_policy' "$INSTALLER"; then fail "installer must not report current runtime feature state"; fi
STATUS="$ROOT/charcoal-status"
grep -Fq -- '-march=znver2' "$STATUS" || fail "status reports the Steam Deck Zen 2 build target"
for excluded in CONFIG_SCHED_BORE CONFIG_SCHED_POC_SELECTOR CONFIG_LRU_CAST CONFIG_CPU_IDLE_GOV_NAP ZRAM-IR ADIOS sched_policy; do
  if grep -Fq "$excluded" "$STATUS"; then fail "status must not check excluded feature $excluded"; fi
done
grep -Fq 'config_disabled CONFIG_ZSWAP' "$STATUS" || fail "status recognizes ZSWAP compiled out"
grep -Fq 'steamos-3.10-linux-7.3-build-82' "$ROOT/README.md" || fail "README documents published build-82 release"
grep -Fq 'this installer requires SteamOS 3.10' "$INSTALLER" || fail "installer documents SteamOS 3.10 platform requirement"
if grep -Eq 'is_pacman_disk_space_error|confirm_stock_removal|pacman -Rdd.*linux-neptune-73' "$INSTALLER"; then fail "installer must not auto-remove the stock kernel to recover disk space"; fi
printf 'Charcoal Linux 7.3 installer tests passed\n'