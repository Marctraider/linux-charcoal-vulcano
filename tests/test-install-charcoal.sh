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
grep -Fq 'verify_existing_boot_state || die' "$INSTALLER" || fail "pre-install boot-chain check"
grep -Fq 'mkinitcpio -p linux-neptune-73' "$INSTALLER" || fail "initramfs generation"
grep -Fq 'verify_grub_entry' "$INSTALLER" || fail "GRUB verification"
printf 'NAP Linux 7.3 installer tests passed\n'