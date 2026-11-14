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
if grep -Eq '^  install=charcoal\.install$|/usr/lib/nap' "$REPO_ROOT/PKGBUILD"; then
  fail "7.3 package still installs the NAP lifecycle hook"
fi

# Source functions without running main().
# shellcheck source=/dev/null
source "$INSTALLER"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/installed" <<'EOF'
linux-charcoal-72
linux-charcoal-72-headers
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

mapfile -t old_charcoal < <(select_installed_charcoal "$tmp/installed")
[[ ${#old_charcoal[@]} -eq 2 ]] || fail "previous Charcoal packages were not detected"

# Stock SteamOS 7.3 remains installed by default, including non-interactive runs.
CHARCOAL_73_REMOVE_STOCK=0 CHARCOAL_73_ASSUME_YES=1 confirm_stock_removal stock
[[ ${#stock[@]} -eq 0 ]] || fail "stock kernel was not preserved by default"

# Removal is possible only through explicit opt-in.
stock=(linux-neptune-73 linux-neptune-73-headers)
CHARCOAL_73_REMOVE_STOCK=1 confirm_stock_removal stock
[[ ${#stock[@]} -eq 2 ]] || fail "explicit stock-kernel opt-in was ignored"

empty_stock=()
confirm_stock_removal empty_stock

if grep -Fq -- '--print-format' "$INSTALLER"; then
  fail "installer uses unsupported pacman --print-format option"
fi
grep -Fq 'pacman -Qp "$pkg" | awk '\''{print $1}'\''' "$INSTALLER" \
  || fail "installer does not use SteamOS-compatible package metadata query"

grep -Fq 'Remove the stock SteamOS 7.3 kernel? This removes your fallback. [y/N]' "$INSTALLER" \
  || fail "explicit stock-kernel removal prompt is missing"
grep -Fq 'local stock="linux-neptune-${pkgbase#linux-charcoal-}"' "$INSTALLER" \
  || fail "installer is not limited to the matching stock kernel series"
grep -Fq 'remove_packages=("${previous_charcoal[@]}" "${stock_packages[@]}")' "$INSTALLER" \
  || fail "only previous Charcoal packages and explicitly approved stock packages may be removed"
grep -Fq 'run_privileged pacman -Rdd --noconfirm "${remove_packages[@]}"' "$INSTALLER" \
  || fail "installer does not remove only approved kernel packages"
grep -Fq 'run_privileged pacman -U --noconfirm "${packages[@]}"' "$INSTALLER" \
  || fail "installer does not install verified Charcoal packages"

remove_line="$(grep -n -F 'run_privileged pacman -Rdd --noconfirm "${remove_packages[@]}"' "$INSTALLER" | head -n1 | cut -d: -f1)"
install_line="$(grep -n -F 'run_privileged pacman -U --noconfirm "${packages[@]}"' "$INSTALLER" | head -n1 | cut -d: -f1)"
[[ -n "$remove_line" && -n "$install_line" && $remove_line -lt $install_line ]] \
  || fail "approved stock removal must occur before Charcoal installation"

grep -Fq 'RELEASE_TAG_PREFIX="charcoal-"' "$INSTALLER" \
  || fail "installer release tag prefix is incorrect"
grep -Fq 'release.get("prerelease") is not False' "$INSTALLER" \
  || fail "installer must reject GitHub prereleases"
grep -Fq '!= (7, 3)' "$INSTALLER" \
  || fail "installer must accept only Linux 7.3 release tags"
grep -Fq 'linux-charcoal-73(-headers)?' "$INSTALLER" \
  || fail "installer must reject packages from other kernel series"

if grep -Fq 'gaming-swap' "$INSTALLER"; then
  fail "installer still invokes removed gaming swap migration"
fi

printf 'install-charcoal SteamOS 7.3 stock-removal tests passed\n'
