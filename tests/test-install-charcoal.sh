#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/install-charcoal.sh"
fail(){ echo "test failure: $*" >&2; exit 1; }
bash -n "$INSTALLER" || fail "installer syntax"
grep -Fxq 'pkgbase=linux-charcoal-73' "$ROOT/PKGBUILD" || fail "package identity"
grep -Fq 'nap-6.12-v0.6.5.patch' "$ROOT/PKGBUILD" || fail "NAP patch"
grep -Fq 'drm_sched_rr_default.patch' "$ROOT/PKGBUILD" || fail "DRM RR patch"
if grep -Eiq 're-swappiness' "$ROOT/PKGBUILD"; then fail "re-swappiness must remain omitted"; fi
grep -Fq 'nap-tools.tar.gz' "$ROOT/PKGBUILD" || fail "NAP tools package source"
grep -Fq 'CONFIG_BTRFS_FS=y' "$ROOT/config-charcoal" || fail "Btrfs config"
source "$INSTALLER"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'ID=steamos\nVERSION_ID=3.10\n' > "$tmp/os-release"
verify_host_platform "$tmp/os-release" || fail "SteamOS 3.10 host"
sed 's/3.10/3.9.5/' "$tmp/os-release" > "$tmp/old"
if verify_host_platform "$tmp/old" >/dev/null 2>&1; then fail "unsupported SteamOS accepted"; fi

cat > "$tmp/kernel.config" <<'EOF'
CONFIG_CPU_IDLE_GOV_NAP=y
CONFIG_CPU_IDLE_GOV_TEO=y
CONFIG_CMDLINE="amd_pstate.epp_boost=1 mitigations=off cpuidle.governor=nap"
CONFIG_BTRFS_FS=y
CONFIG_ZRAM=m
CONFIG_ZSMALLOC=m
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_ZRAM_MULTI_COMP=y
CONFIG_ZRAM_DEF_COMP="lz4"
CONFIG_SCHED_BORE=y
CONFIG_SCHED_POC_SELECTOR=y
CONFIG_LRU_CAST=y
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
   if [[ "$2" == *headers* ]]; then echo 'usr/lib/modules/7.3.1-neptune-73/build/.config'
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
PATH="$tmp/bin:$PATH" CONFIG_FIXTURE="$tmp/kernel.config" verify_kernel_package_identity package_files || fail "valid NAP package identity/config rejected"
if PATH="$tmp/bin:$PATH" charcoal_upgrade_installed; then fail "missing Charcoal package treated as an upgrade"; fi
CHARCOAL_TEST_INSTALLED=1 PATH="$tmp/bin:$PATH" charcoal_upgrade_installed || fail "installed Charcoal package not detected for in-place upgrade"
grep -v 'CONFIG_CPU_IDLE_GOV_NAP=y' "$tmp/kernel.config" > "$tmp/kernel-bad.config"
if ( PATH="$tmp/bin:$PATH" CONFIG_FIXTURE="$tmp/kernel-bad.config" verify_kernel_package_identity package_files >/dev/null 2>&1 ); then fail "package without NAP governor accepted"; fi
cat > "$tmp/runs.json" <<'EOF'
{"workflow_runs":[
{"id":1,"run_number":1,"head_branch":"validation/steamos-3.10-linux-7.3","status":"completed","conclusion":"success","path":".github/workflows/build-kernel-7.3.yml","head_sha":"bad"},
{"id":2,"run_number":2,"head_branch":"experiment/steamos-3.10-linux-7.3-nap","status":"completed","conclusion":"failure","path":".github/workflows/build-kernel-7.3.yml","head_sha":"bad"},
{"id":3,"run_number":3,"head_branch":"experiment/steamos-3.10-linux-7.3-nap","status":"completed","conclusion":"success","path":".github/workflows/build-kernel-7.3.yml","head_sha":"abc123"}]}
EOF
mapfile -t run < <(select_latest_nap_run "$tmp/runs.json")
[[ "${run[0]}" == 3 && "${run[1]}" == 3 && "${run[2]}" == abc123 ]] || fail "successful NAP workflow selection"
cat > "$tmp/artifacts.json" <<'EOF'
{"artifacts":[{"id":10,"name":"charcoal-steamos-3.10-linux-7.3-nap-build-3","expired":false,"archive_download_url":"https://api.github.com/repos/Marctraider/linux-charcoal-vulcano/actions/artifacts/10/zip"}]}
EOF
mapfile -t artifact < <(select_nap_artifact "$tmp/artifacts.json" 3)
[[ "${artifact[0]}" == 10 ]] || fail "matching build artifact selection"
python3 - "$tmp/nap-artifact.zip" <<'PY'
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
    z.writestr("logs/prepare-73.log", "Applying nap-6.12-v0.6.5.patch\nint drm_sched_policy = DRM_SCHED_POLICY_RR;\n")
    z.writestr("logs/nap-tools-upstream.json", "{}")
PY
extract_and_verify_nap_artifact "$tmp/nap-artifact.zip" "$tmp/unpacked" || fail "verified artifact extraction"
[[ -f "$tmp/unpacked/linux-charcoal-73-7.3.1.valve2.cc1-1-x86_64.pkg.tar.zst" ]] || fail "kernel package not extracted"
[[ -f "$tmp/unpacked/linux-charcoal-73-headers-7.3.1.valve2.cc1-1-x86_64.pkg.tar.zst" ]] || fail "headers package not extracted"
grep -Fq 'current_governor' "$INSTALLER" || fail "NAP runtime check"
grep -Fq 'nap-state.service' "$INSTALLER" || fail "NAP restore service check"
grep -Fq 'nap-state-save.timer' "$INSTALLER" || fail "NAP save timer check"
grep -Fq 'sched_policy' "$INSTALLER" || fail "DRM RR runtime check"
grep -Fq 'CONFIG_BTRFS_FS=y' "$INSTALLER" || fail "Btrfs config check"
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
STATUS="$ROOT/charcoal-status"
grep -Fq 'CONFIG_CPU_IDLE_GOV_NAP CONFIG_CPU_IDLE_GOV_TEO' "$STATUS" || fail "status checks NAP and TEO fallback"
grep -Fq '/sys/module/drm/parameters/sched_policy' "$STATUS" || fail "status checks DRM RR runtime policy"
grep -Fq 'NAP userspace service configuration helper' "$STATUS" || fail "status checks NAP userspace integration"
grep -Fq 'install-charcoal.sh --check-only' "$ROOT/README.md" || fail "README documents installer diagnostic command"
grep -Fq 'bash install-charcoal.sh' "$ROOT/README.md" || fail "README documents installer command"
if grep -Fq 'install-charcoal-73-nap.sh' "$ROOT/README.md"; then fail "README retains inconsistent installer filename"; fi
printf 'NAP Linux 7.3 installer tests passed\n'