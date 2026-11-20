#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/install-charcoal.sh"
fail(){ echo "test failure: $*" >&2; exit 1; }

bash -n "$INSTALLER" || fail "installer syntax"
source "$INSTALLER"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

printf 'ID=steamos\nVERSION_ID=3.10\n' > "$tmp/os-release"
verify_host_platform "$tmp/os-release" || fail "SteamOS 3.10 host"
sed 's/3.10/3.9.5/' "$tmp/os-release" > "$tmp/old"
if verify_host_platform "$tmp/old" >/dev/null 2>&1; then fail "unsupported SteamOS accepted"; fi

# The installer must validate package identity and boot naming, not kernel .config options.
identity_fn="$(declare -f verify_kernel_package_identity)"
if grep -Eq 'CONFIG_[A-Z0-9_]+|build/\.config' <<< "$identity_fn"; then
  fail "kernel configuration is still an installation gate"
fi

module_dir='usr/lib/modules/7.3.1-valve2-3-charcoal-73-g0ed55b10a784-dirty'
mkdir -p "$tmp/bin"
cat > "$tmp/bin/pacman" <<'PACMAN'
#!/usr/bin/env bash
case "$1" in
  -Qp)
    case "$2" in
      *headers*)
        if [[ "${MISMATCH_HEADERS:-0}" == 1 ]]; then
          echo "linux-charcoal-73-headers 7.3.1.valve2.cc1-4"
        else
          echo "linux-charcoal-73-headers 7.3.1.valve2.cc1-3"
        fi ;;
      *) echo "linux-charcoal-73 7.3.1.valve2.cc1-3" ;;
    esac ;;
  *) exit 2 ;;
esac
PACMAN
cat > "$tmp/bin/bsdtar" <<'BSDTAR'
#!/usr/bin/env bash
module_dir='usr/lib/modules/7.3.1-valve2-3-charcoal-73-g0ed55b10a784-dirty'
case "$1" in
  -tf)
    if [[ "$2" == *headers* ]]; then
      printf '%s\n' "$module_dir/build/Makefile" "$module_dir/build/version"
    else
      printf '%s\n' "$module_dir/pkgbase" "$module_dir/vmlinuz"
    fi ;;
  -xOf)
    if [[ "${BAD_BOOT_ID:-0}" == 1 ]]; then echo "wrong-pkgbase"; else echo "linux-neptune-73"; fi ;;
  *) exit 2 ;;
esac
BSDTAR
chmod +x "$tmp/bin/pacman" "$tmp/bin/bsdtar"
touch "$tmp/linux-charcoal-73.pkg.tar.zst" "$tmp/linux-charcoal-73-headers.pkg.tar.zst"
package_files=("$tmp/linux-charcoal-73.pkg.tar.zst" "$tmp/linux-charcoal-73-headers.pkg.tar.zst")

PATH="$tmp/bin:$PATH" verify_kernel_package_identity package_files || fail "matching package boot/header identity rejected"
if BAD_BOOT_ID=1 PATH="$tmp/bin:$PATH" verify_kernel_package_identity package_files >/dev/null 2>&1; then
  fail "wrong Valve boot identity accepted"
fi
if MISMATCH_HEADERS=1 PATH="$tmp/bin:$PATH" verify_kernel_package_identity package_files >/dev/null 2>&1; then
  fail "mismatched kernel and headers versions accepted"
fi

mkdir -p "$tmp/packages"
printf 'kernel package test\n' > "$tmp/packages/$KERNEL_ASSET"
printf 'headers package test\n' > "$tmp/packages/$HEADERS_ASSET"
(
  cd "$tmp/packages"
  sha256sum "$KERNEL_ASSET" "$HEADERS_ASSET" > "$tmp/SHA256SUMS"
)
verify_release_checksums "$tmp/packages" "$tmp/SHA256SUMS" || fail "valid package checksum manifest rejected"
printf '0%.0s' {1..64} > "$tmp/SHA256SUMS"
if ( verify_release_checksums "$tmp/packages" "$tmp/SHA256SUMS" ) >/dev/null 2>&1; then
  fail "invalid package checksums accepted"
fi

grep -Fxq 'readonly RELEASE_TAG="steamos-3.10-linux-7.3-build-100"' "$INSTALLER" || fail "Build 100 release tag"
grep -Fxq 'readonly KERNEL_ASSET="linux-charcoal-73-7.3.1.valve2.cc1-3-x86_64.pkg.tar.zst"' "$INSTALLER" || fail "Actions kernel asset"
grep -Fxq 'readonly HEADERS_ASSET="linux-charcoal-73-headers-7.3.1.valve2.cc1-3-x86_64.pkg.tar.zst"' "$INSTALLER" || fail "Actions headers asset"
grep -Fxq 'readonly CHECKSUM_ASSET_SHA256="d08ca13f1afa536db076c9a8db48b6af4acf4d26b8cb1c3b5bbe1b37e6fdb72c"' "$INSTALLER" || fail "Build 100 checksum manifest digest"
grep -Fq 'mkinitcpio -p linux-neptune-73' "$INSTALLER" || fail "SteamOS boot identity initramfs generation"
grep -Fq 'verify_grub_entry' "$INSTALLER" || fail "GRUB entry validation"
grep -Fq 'ExecStart=/usr/bin/scx_lavd --performance' "$INSTALLER" || fail "LAVD performance mode"
grep -Fq 'pacman -S --needed --noconfirm scx-scheds' "$INSTALLER" || fail "LAVD userspace package"
grep -Fq 'systemctl enable charcoal-lavd.service' "$INSTALLER" || fail "LAVD service enablement"
grep -Fq 'd08ca13f1afa536db076c9a8db48b6af4acf4d26b8cb1c3b5bbe1b37e6fdb72c' "$ROOT/README.md" || fail "README Build 100 checksum manifest"
printf 'Charcoal Linux 7.3 installer tests passed\n'
