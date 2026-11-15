#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly INSTALLER="$REPO_ROOT/install-charcoal.sh"

fail() {
  printf 'test failure: %s\n' "$*" >&2
  exit 1
}

bash -n "$INSTALLER" || fail "installer shell syntax is invalid"
grep -Fxq 'pkgbase=linux-charcoal-73' "$REPO_ROOT/PKGBUILD" \
  || fail "7.3 package identity is incorrect"
grep -Fq 'echo "linux-neptune-73" | install -Dm644 /dev/stdin "$modulesdir/pkgbase"' "$REPO_ROOT/PKGBUILD" \
  || fail "kernel package does not use Valve's SteamOS 7.3 boot identity"
if grep -Eq '^  install=charcoal\.install$|/usr/lib/nap' "$REPO_ROOT/PKGBUILD"; then
  fail "7.3 package still installs the NAP lifecycle hook"
fi

# Source functions without running main().
# shellcheck source=/dev/null
source "$INSTALLER"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The installer persists the ZSWAP-off policy in GRUB without a kernel rebuild.
run_privileged() { "$@"; }
export CHARCOAL_GRUB_DEFAULTS_FILE="$tmp/grub-defaults"
cat > "$CHARCOAL_GRUB_DEFAULTS_FILE" <<'EOF'
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash zswap.enabled=1"
GRUB_CMDLINE_LINUX="console=tty1 zswap.enabled=1"
EOF
ensure_zswap_disabled_boot_parameter || fail "could not set the persistent ZSWAP boot parameter"
[[ "$(grep -c 'zswap.enabled=0' "$CHARCOAL_GRUB_DEFAULTS_FILE")" -eq 1 ]] || fail "ZSWAP-off parameter was not written exactly once"
! grep -q 'zswap.enabled=1' "$CHARCOAL_GRUB_DEFAULTS_FILE" || fail "conflicting ZSWAP-on parameter remains"
grep -q 'zswap.enabled=1' "$CHARCOAL_GRUB_DEFAULTS_FILE.charcoal-backup" || fail "original GRUB defaults were not backed up"
ensure_zswap_disabled_boot_parameter || fail "second ZSWAP configuration pass failed"
[[ "$(grep -c 'zswap.enabled=0' "$CHARCOAL_GRUB_DEFAULTS_FILE")" -eq 1 ]] || fail "ZSWAP boot parameter is not idempotent"
unset CHARCOAL_GRUB_DEFAULTS_FILE

# The 7.3 installer must refuse other operating-system releases.
cat > "$tmp/os-release" <<'EOF'
ID=steamos
VERSION_ID=3.10
EOF
verify_host_platform "$tmp/os-release" || fail "SteamOS 3.10 host was rejected"
sed 's/VERSION_ID=3.10/VERSION_ID=3.9.5/' "$tmp/os-release" > "$tmp/os-release-old"
if verify_host_platform "$tmp/os-release-old" >/dev/null 2>&1; then
  fail "installer accepted a non-3.10 SteamOS host"
fi

# Inspect the actual package payload before allowing any package transaction.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/pacman" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "-Qp" ]] || exit 2
case "$2" in
  *headers*) printf '%s\n' 'linux-charcoal-73-headers 7.3.1.valve2.cc1-1' ;;
  *) printf '%s\n' 'linux-charcoal-73 7.3.1.valve2.cc1-1' ;;
esac
EOF
cat > "$tmp/bin/bsdtar" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  -tf)
    if [[ "$2" == *headers* ]]; then
      printf '%s\n' 'usr/lib/modules/7.3.1-neptune-73/build/Makefile'
    else
      printf '%s\n' \
        'usr/lib/modules/7.3.1-neptune-73/pkgbase' \
        'usr/lib/modules/7.3.1-neptune-73/vmlinuz'
    fi
    ;;
  -xOf) printf '%s\n' "${MOCK_PKGBASE:-linux-neptune-73}" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$tmp/bin/pacman" "$tmp/bin/bsdtar"
touch "$tmp/linux-charcoal-73.pkg.tar.zst" "$tmp/linux-charcoal-73-headers.pkg.tar.zst"
packages=("$tmp/linux-charcoal-73.pkg.tar.zst" "$tmp/linux-charcoal-73-headers.pkg.tar.zst")
PATH="$tmp/bin:$PATH" verify_kernel_package_identity packages \
  || fail "installer rejected a package with the correct SteamOS 7.3 boot identity"
if ( MOCK_PKGBASE=linux-charcoal-73 PATH="$tmp/bin:$PATH" verify_kernel_package_identity packages >/dev/null 2>&1 ); then
  fail "installer accepted a package with the incorrect Charcoal boot identity"
fi

cat > "$tmp/installed" <<'EOF'
linux-charcoal-72
linux-charcoal-72-headers
linux-charcoal-73
linux-charcoal-73-headers
linux-neptune-72
linux-neptune-72-headers
linux-neptune-73
linux-neptune-73-headers
unrelated-package
EOF

mapfile -t stock < <(select_stock_kernel "$tmp/installed")
[[ ${#stock[@]} -eq 2 ]] || fail "expected stock 7.3 kernel and headers"
[[ ${stock[0]} == linux-neptune-73 ]] || fail "stock kernel was not detected"
[[ ${stock[1]} == linux-neptune-73-headers ]] || fail "stock headers were not detected"

if declare -F select_installed_charcoal >/dev/null; then
  fail "installer must not select or remove any installed Charcoal package"
fi

# Stock kernel packages are identified as a possible space-recovery option,
# but are not removed unless pacman reports its explicit disk-space error.
[[ ${#stock[@]} -eq 2 ]] || fail "expected stock 7.3 kernel and headers as optional space-recovery packages"
empty_stock=()
confirm_stock_removal empty_stock

grep -Fq 'Remove the stock kernel packages and continue? [y/N]' "$INSTALLER" \
  || fail "stock-kernel removal does not require explicit y/n confirmation"
grep -Fq 'Installation cancelled; the stock kernel was not removed' "$INSTALLER" \
  || fail "declining stock-kernel removal does not cancel safely"
grep -Fq 'is_pacman_disk_space_error' "$INSTALLER" \
  || fail "installer does not restrict stock removal to a detected pacman disk-space failure"
grep -Fq 'Attempting to install Charcoal while preserving the stock kernel' "$INSTALLER" \
  || fail "installer does not first attempt installation with the stock kernel retained"
grep -Fq 'error: not enough free disk space' "$INSTALLER" \
  || fail "installer does not recognize pacman insufficient-space failures"

if grep -Fq -- '--print-format' "$INSTALLER"; then
  fail "installer uses unsupported pacman --print-format option"
fi
grep -Fq 'pacman -Qp "$pkg" | awk '\''{print $1}'\''' "$INSTALLER" \
  || fail "installer does not use SteamOS-compatible package metadata query"

grep -Fq 'local stock="linux-neptune-${pkgbase#linux-charcoal-}"' "$INSTALLER" \
  || fail "installer is not limited to the matching stock kernel series"
grep -Fq 'remove_packages=("${stock_packages[@]}")' "$INSTALLER" \
  || fail "only the matching SteamOS 7.3 stock packages may be considered for removal"
if grep -Fq 'previous_charcoal' "$INSTALLER"; then
  fail "installer must not remove existing Charcoal packages"
fi
grep -Fq 'run_privileged pacman -Rdd --noconfirm "${remove_packages[@]}"' "$INSTALLER" \
  || fail "installer does not remove only approved kernel packages"
grep -Fq 'run_privileged pacman -U --noconfirm "${packages[@]}"' "$INSTALLER" \
  || fail "installer does not install verified Charcoal packages"

first_install_line="$(grep -n -F 'Attempting to install Charcoal while preserving the stock kernel' "$INSTALLER" | head -n1 | cut -d: -f1)"
remove_line="$(grep -n -F 'run_privileged pacman -Rdd --noconfirm "${remove_packages[@]}"' "$INSTALLER" | head -n1 | cut -d: -f1)"
retry_line="$(grep -n -F 'Retrying the verified Charcoal package installation after freeing space' "$INSTALLER" | head -n1 | cut -d: -f1)"
[[ -n "$first_install_line" && -n "$remove_line" && -n "$retry_line" && $first_install_line -lt $remove_line && $remove_line -lt $retry_line ]] \
  || fail "stock removal must happen only after the first install attempt and confirmation, then retry installation"

grep -Fq 'RELEASE_TAG_PREFIX="charcoal-"' "$INSTALLER" \
  || fail "installer release tag prefix is incorrect"
grep -Fq 'release.get("prerelease") is not False' "$INSTALLER" \
  || fail "installer must reject GitHub prereleases"
grep -Fq 'releases?per_page=100' "$INSTALLER" \
  || fail "installer must inspect the release list, not the repository-wide latest release"
grep -Fq 'version[:2] != (7, 3)' "$INSTALLER" \
  || fail "installer must accept only Linux 7.3 release tags"
if grep -Fq '/releases/latest' "$INSTALLER"; then
  fail "installer must not depend on the repository-wide latest release"
fi

# A newer 7.2 release must not hide the newest stable 7.3 release.
python3 - "$tmp/releases.json" <<'PY'
import json, sys
base = "https://github.com/Marctraider/linux-charcoal-vulcano/releases/download/"
def release(tag, *, draft=False, prerelease=False, published="2026-01-01T00:00:00Z"):
    return {
        "tag_name": tag, "draft": draft, "prerelease": prerelease,
        "published_at": published,
        "assets": [
            {"name": f"linux-charcoal-73-{tag.removeprefix('charcoal-')}.zip",
             "browser_download_url": base + tag + f"/linux-charcoal-73-{tag.removeprefix('charcoal-')}.zip"},
            {"name": "RELEASE-ZIP-SHA256SUM",
             "browser_download_url": base + tag + "/RELEASE-ZIP-SHA256SUM"},
        ],
    }
releases = [
    release("charcoal-7.2.9.valve1.cc1-r99", published="2026-11-01T00:00:00Z"),
    release("charcoal-7.3.1.valve2.cc1-r1", published="2026-10-01T00:00:00Z"),
    release("charcoal-7.3.1.valve2.cc1-r2", published="2026-10-15T00:00:00Z"),
    release("charcoal-7.3.1.valve2.cc1-r9", draft=True),
    release("charcoal-7.3.1.valve2.cc1-r10", prerelease=True),
]
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(releases, f)
PY
release_metadata="$(parse_release_metadata "$tmp/releases.json")" \
  || fail "release metadata parser rejected the release-list fixture"
mapfile -t release_fields <<< "$release_metadata"
[[ ${release_fields[0]} == charcoal-7.3.1.valve2.cc1-r2 ]] \
  || fail "installer did not select the newest stable 7.3 release"
[[ ${#release_fields[@]} -eq 5 ]] \
  || fail "release metadata parser returned an incomplete asset set"

# The published r1 archive contains the broken kernel identity and must never be selected.
python3 - "$tmp/releases.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump([r for r in data if r["tag_name"].endswith("-r1")], f)
PY
r1_metadata="$(parse_release_metadata "$tmp/releases.json")" \
  || fail "installer did not accept r1 for verified local package normalization"
mapfile -t r1_fields <<< "$r1_metadata"
[[ ${r1_fields[0]} == charcoal-7.3.1.valve2.cc1-r1 ]] \
  || fail "installer did not select the available r1 package when no newer 7.3 release exists"

grep -Fq 'verify_host_platform || die' "$INSTALLER" \
  || fail "installer does not enforce the SteamOS 3.10 target"
grep -Fq 'verify_existing_boot_state || die' "$INSTALLER" \
  || fail "installer does not validate the pre-existing SteamOS boot chain before package changes"
grep -Fq 'diagnose_boot_state()' "$INSTALLER" \
  || fail "installer does not provide a read-only diagnostic mode"
grep -Fq 'pacman -Q linux-charcoal-73 2>/dev/null' "$INSTALLER" \
  || fail "diagnostic leaks pacman not-installed errors for the optional Charcoal package"
grep -Fq '/efi/EFI/SteamOS/grub.cfg' "$INSTALLER" \
  || fail "installer does not check SteamOS's canonical uppercase EFI GRUB path"
grep -Fq '/boot/efi/EFI/SteamOS/grub.cfg' "$INSTALLER" \
  || fail "installer does not check the mounted-EFI SteamOS GRUB path"
grep -Fq 'if run_privileged test -s "$candidate"; then' "$INSTALLER" \
  || fail "installer does not check root-owned EFI GRUB configs with privileges"
grep -Fq "run_privileged grep -Fq '/boot/vmlinuz-linux-neptune-73' \"\$grub\"" "$INSTALLER" \
  || fail "installer does not read root-owned GRUB config with privileges"
grep -Fq '"${1:-}" == "--check-only"' "$INSTALLER" \
  || fail "installer does not expose the read-only --check-only option"
grep -Fq 'diagnose_boot_state' "$INSTALLER" \
  || fail "installer does not call its diagnostic routine"
grep -Fq "verify_boot_artifacts || {" "$INSTALLER" \
  || fail "installer does not reject missing pre-install kernel/initramfs artifacts"
grep -Fq "current GRUB config does not reference the SteamOS 7.3 kernel" "$INSTALLER" \
  || fail "installer does not check the pre-install GRUB kernel reference"
grep -Fq "current GRUB config does not reference the SteamOS 7.3 initramfs" "$INSTALLER" \
  || fail "installer does not check the pre-install GRUB initramfs reference"
grep -Fq 'verify_kernel_package_identity packages' "$INSTALLER" \
  || fail "installer does not inspect the downloaded kernel package boot identity"
grep -Fq 'package_base" == linux-neptune-73' "$INSTALLER" \
  || fail "installer does not require Valve's SteamOS 7.3 pkgbase"
grep -Fq 'The Valve linux-neptune-73 stock kernel is not installed' "$INSTALLER" \
  || fail "installer does not require a known-good matching stock-kernel fallback"

grep -Fq 'mkinitcpio -p linux-neptune-73' "$INSTALLER" \
  || fail "installer does not explicitly generate the SteamOS 7.3 initramfs"
grep -Fq '/boot/vmlinuz-linux-neptune-73' "$INSTALLER" \
  || fail "installer does not verify the expected SteamOS kernel image"
grep -Fq '/boot/initramfs-linux-neptune-73.img' "$INSTALLER" \
  || fail "installer does not verify the expected SteamOS initramfs"
grep -Fq 'verify_grub_entry' "$INSTALLER" \
  || fail "installer does not validate the generated GRUB entry"
grep -Fq 'normalize-legacy-73-package.py' "$INSTALLER" \
  || fail "installer does not normalize r1 package boot identity"
if grep -Fq 'version[-1] < 2' "$INSTALLER"; then
  fail "installer still rejects r1 before package normalization"
fi
grep -Fq 'linux-charcoal-73(-headers)?' "$INSTALLER" \
  || fail "installer must reject packages from other kernel series"

if grep -Fq 'gaming-swap' "$INSTALLER"; then
  fail "installer still invokes removed gaming swap migration"
fi

printf 'install-charcoal SteamOS 7.3 stock-only removal tests passed\n'
