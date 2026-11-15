#!/usr/bin/env bash
# Install the latest Charcoal kernel release for SteamOS with Linux 7.3.

set -Eeuo pipefail

readonly REPOSITORY="Marctraider/linux-charcoal-vulcano"
readonly RELEASES_API="https://api.github.com/repos/${REPOSITORY}/releases?per_page=100"
readonly RELEASE_DOWNLOAD_PREFIX="https://github.com/${REPOSITORY}/releases/download/"
readonly RELEASE_TAG_PREFIX="charcoal-"
readonly NORMALIZER_URL="https://raw.githubusercontent.com/Marctraider/linux-charcoal-vulcano/4fe6d52a9589ef6dd0534c6ea6ac80e14418d893/automation/normalize-legacy-73-package.py"
readonly RELEASE_ZIP_PREFIX="linux-charcoal-"
readonly USER_AGENT="charcoal-73-installer"

WORKDIR=""
MADE_ROOT_WRITABLE=0
ROLLBACK_READY=0

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '%s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

run_privileged() {
  if (( EUID == 0 )); then
    command "$@"
  else
    sudo "$@"
  fi
}

GRUB_CONFIG=""

verify_host_platform() {
  local release_file=${1:-/etc/os-release}
  [[ -r "$release_file" ]] || { info "error: SteamOS release metadata is unavailable"; return 1; }
  # shellcheck disable=SC1090
  . "$release_file"
  [[ ${ID:-} == steamos ]] || { info "error: this installer only supports SteamOS"; return 1; }
  case ${VERSION_ID:-} in
    3.10|3.10.*) ;;
    *) info "error: this installer requires SteamOS 3.10 (found ${VERSION_ID:-unknown})"; return 1 ;;
  esac
}

_update_grub() {
  local steamos_efi_dir=${1:-/efi/EFI/SteamOS}
  # Prefer Valve's SteamOS wrapper so its EFI/GRUB integration is respected.
  if command -v steamos-update-grub >/dev/null 2>&1; then
    run_privileged steamos-update-grub
  elif command -v grub-mkconfig >/dev/null 2>&1; then
    if [[ -d "$steamos_efi_dir" ]]; then
      run_privileged grub-mkconfig -o "$steamos_efi_dir/grub.cfg"
    else
      run_privileged grub-mkconfig -o /boot/grub/grub.cfg
    fi
  elif command -v update-grub >/dev/null 2>&1; then
    run_privileged update-grub
  else
    die "No supported SteamOS bootloader update command found"
  fi

  if [[ -s "$steamos_efi_dir/grub.cfg" ]]; then
    GRUB_CONFIG="$steamos_efi_dir/grub.cfg"
  elif [[ -s /boot/grub/grub.cfg ]]; then
    GRUB_CONFIG=/boot/grub/grub.cfg
  else
    die "Bootloader update completed but no GRUB configuration was found"
  fi
}

verify_boot_artifacts() {
  local preset=/etc/mkinitcpio.d/linux-neptune-73.preset
  local kernel=/boot/vmlinuz-linux-neptune-73
  local initramfs=/boot/initramfs-linux-neptune-73.img

  [[ -s "$preset" ]] || { info "error: SteamOS 7.3 mkinitcpio preset is missing"; return 1; }
  [[ -s "$kernel" ]] || { info "error: expected boot kernel is missing: $kernel"; return 1; }
  [[ -s "$initramfs" ]] || { info "error: expected initramfs is missing: $initramfs"; return 1; }
}

verify_existing_boot_state() {
  # Fail before any package or filesystem changes if the current SteamOS
  # 3.10 boot chain is already incomplete. Do not overwrite evidence or
  # attempt an installation on a system that is already missing boot files.
  verify_boot_artifacts || {
    info "error: existing SteamOS 3.10 boot files are incomplete; installation aborted without changes"
    return 1
  }
  local grub=""
  for candidate in /efi/EFI/SteamOS/grub.cfg /efi/EFI/steamos/grub.cfg /boot/efi/EFI/SteamOS/grub.cfg /boot/efi/EFI/steamos/grub.cfg /boot/grub/grub.cfg; do
    if run_privileged test -s "$candidate"; then
      grub=$candidate
      break
    fi
  done
  [[ -n "$grub" ]] || {
    info "error: no existing SteamOS GRUB configuration found; installation aborted without changes"
    return 1
  }
  run_privileged grep -Fq '/boot/vmlinuz-linux-neptune-73' "$grub" || {
    info "error: current GRUB config does not reference the SteamOS 7.3 kernel; installation aborted"
    return 1
  }
  run_privileged grep -Fq '/boot/initramfs-linux-neptune-73.img' "$grub" || {
    info "error: current GRUB config does not reference the SteamOS 7.3 initramfs; installation aborted"
    return 1
  }
}

verify_grub_entry() {
  [[ -n "$GRUB_CONFIG" && -s "$GRUB_CONFIG" ]] || {
    info "error: generated GRUB configuration is missing"
    return 1
  }
  grep -Fq '/boot/vmlinuz-linux-neptune-73' "$GRUB_CONFIG" || {
    info "error: GRUB configuration does not reference the SteamOS 7.3 kernel image"
    return 1
  }
  grep -Fq '/boot/initramfs-linux-neptune-73.img' "$GRUB_CONFIG" || {
    info "error: GRUB configuration does not reference the SteamOS 7.3 initramfs"
    return 1
  }
}

cleanup() {
  local exit_status=$?
  trap - EXIT
  if (( MADE_ROOT_WRITABLE )); then
    info "Restoring SteamOS read-only mode..."
    if ! run_privileged steamos-readonly enable; then
      printf 'warning: could not restore SteamOS read-only mode; run sudo steamos-readonly enable manually.\n' >&2
      exit_status=1
    fi
  fi
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf -- "$WORKDIR"
  fi
  exit "$exit_status"
}

download_file() {
  local url=$1 destination=$2
  curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 15 \
    --output "$destination" "$url"
}

parse_release_metadata() {
  local releases_json=$1
  python3 - "$releases_json" "$REPOSITORY" "$RELEASE_DOWNLOAD_PREFIX" "$RELEASE_TAG_PREFIX" "$RELEASE_ZIP_PREFIX" <<'PY'
import json
import re
import sys
from pathlib import PurePosixPath

releases_json, repository, download_prefix, tag_prefix, zip_prefix = sys.argv[1:]
with open(releases_json, encoding="utf-8") as handle:
    releases = json.load(handle)
if not isinstance(releases, list):
    raise SystemExit("GitHub did not return a release list")

def text(value, label):
    if not isinstance(value, str) or not value or any(c in value for c in "\x00\r\n"):
        raise SystemExit(f"Invalid {label} in GitHub release response")
    return value

def checked_asset(asset, expected, tag):
    name = text(asset.get("name"), "asset name")
    url = text(asset.get("browser_download_url"), "asset URL")
    if name != expected:
        raise SystemExit(f"Unexpected asset name: {name}")
    if not url.startswith(f"{download_prefix}{tag}/"):
        raise SystemExit(f"Refusing asset outside {repository} release {tag}: {url}")
    return url

candidates = []
tag_pattern = re.compile(
    re.escape(tag_prefix)
    + r"([0-9]+)\.([0-9]+)\.([0-9]+)\.valve([0-9]+)\.cc([0-9]+)-r([0-9]+)"
)
for release in releases:
    if not isinstance(release, dict):
        continue
    tag = release.get("tag_name")
    if release.get("draft") is not False or release.get("prerelease") is not False:
        continue
    match = tag_pattern.fullmatch(tag) if isinstance(tag, str) else None
    if match is None:
        continue
    version = tuple(map(int, match.groups()))
    if version[:2] != (7, 3):
        continue
    # r1 is accepted only after the downloaded kernel archive is normalized
    # and its pkgbase/.MTREE pair is verified before pacman sees the package.
    candidates.append((version, str(release.get("published_at") or ""), release))
if not candidates:
    raise SystemExit("No published Charcoal SteamOS 7.3 release was found")

# Pick the highest 7.3 package/release revision, regardless of newer 7.2 releases.
selected = max(candidates, key=lambda item: (item[0], item[1]))[2]
tag = text(selected.get("tag_name"), "release tag")
assets = selected.get("assets")
if not isinstance(assets, list):
    raise SystemExit("GitHub 7.3 release has no assets")
archives = [a for a in assets if isinstance(a, dict) and str(a.get("name", "")).startswith(zip_prefix) and str(a.get("name", "")).endswith(".zip")]
checksums = [a for a in assets if isinstance(a, dict) and a.get("name") == "RELEASE-ZIP-SHA256SUM"]
if len(archives) != 1 or len(checksums) != 1:
    raise SystemExit("7.3 release assets are incomplete or ambiguous")
archive_name = text(archives[0].get("name"), "archive name")
if PurePosixPath(archive_name).name != archive_name:
    raise SystemExit("Invalid release ZIP filename")
print(tag)
print(archive_name)
print(checked_asset(archives[0], archive_name, tag))
print("RELEASE-ZIP-SHA256SUM")
print(checked_asset(checksums[0], "RELEASE-ZIP-SHA256SUM", tag))
PY
}

verify_release_archive() {
  local archive=$1 checksum_file=$2 archive_name=$3
  python3 - "$archive" "$checksum_file" "$archive_name" <<'PY'
import hashlib, re, sys
archive, checksum_file, archive_name = sys.argv[1:]
lines = open(checksum_file, encoding="utf-8").read().splitlines()
entries = []
for line in lines:
    m = re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", line)
    if not m:
        raise SystemExit("Invalid RELEASE-ZIP-SHA256SUM format")
    entries.append((m.group(1).lower(), m.group(2)))
if len(entries) != 1 or entries[0][1] != archive_name:
    raise SystemExit("Release checksum does not match selected ZIP")
h = hashlib.sha256()
with open(archive, "rb") as f:
    for block in iter(lambda: f.read(1024 * 1024), b""):
        h.update(block)
if h.hexdigest() != entries[0][0]:
    raise SystemExit("Release ZIP SHA-256 verification failed")
PY
}

extract_and_verify_packages() {
  local archive=$1 destination=$2
  python3 - "$archive" "$destination" <<'PY'
import hashlib, re, stat, sys, zipfile
from pathlib import Path, PurePosixPath
archive, destination = map(Path, sys.argv[1:])
package_re = re.compile(r"^linux-charcoal-[0-9]+(?:-headers)?-[^/\\\x00\r\n]+\.pkg\.tar\.zst$")
sum_re = re.compile(r"([0-9a-fA-F]{64}) [ *](linux-charcoal-[0-9]+(?:-headers)?-[^/\\\x00\r\n]+\.pkg\.tar\.zst)")
with zipfile.ZipFile(archive) as zf:
    infos = zf.infolist()
    names = [i.filename for i in infos]
    if len(names) != len(set(names)) or "SHA256SUMS" not in names:
        raise SystemExit("Invalid release ZIP structure")
    package_infos = [i for i in infos if package_re.fullmatch(i.filename)]
    package_names = {i.filename for i in package_infos}
    if len(package_infos) != 2 or sum("-headers-" in n for n in package_names) != 1:
        raise SystemExit("Release ZIP must contain exactly kernel and headers packages")
    stems = {re.fullmatch(r"(linux-charcoal-[0-9]+)(?:-headers)?-[0-9].*", n).group(1) for n in package_names}
    if len(stems) != 1:
        raise SystemExit("Kernel and headers belong to different series")
    for info in package_infos:
        if PurePosixPath(info.filename).name != info.filename or stat.S_ISLNK(info.external_attr >> 16):
            raise SystemExit(f"Unsafe ZIP entry: {info.filename}")
    checksums = {}
    for line in zf.read("SHA256SUMS").decode("utf-8").splitlines():
        m = sum_re.fullmatch(line)
        if not m or m.group(2) in checksums:
            raise SystemExit("Invalid package SHA256SUMS")
        checksums[m.group(2)] = m.group(1).lower()
    if set(checksums) != package_names:
        raise SystemExit("Package list does not match SHA256SUMS")
    destination.mkdir(mode=0o700)
    for info in package_infos:
        target = destination / info.filename
        h = hashlib.sha256()
        with zf.open(info) as source, target.open("xb") as out:
            for block in iter(lambda: source.read(1024 * 1024), b""):
                h.update(block); out.write(block)
        if h.hexdigest() != checksums[info.filename]:
            target.unlink(missing_ok=True)
            raise SystemExit(f"Package SHA-256 verification failed: {info.filename}")
PY
}

verify_kernel_package_identity() {
  local -n package_files=$1
  local pkg pkgname="" pkgver="" kernel_pkg="" headers_pkg="" kernel_pkgver="" headers_pkgver=""
  local entry module_dir package_base archive_listing
  local -a pkgbase_entries=()

  for pkg in "${package_files[@]}"; do
    read -r pkgname pkgver < <(pacman -Qp "$pkg")
    [[ -n "$pkgname" && -n "$pkgver" ]] || { info "error: cannot read package metadata: $pkg"; return 1; }
    case "$pkgname" in
      linux-charcoal-73)
        [[ -z "$kernel_pkg" ]] || { info "error: duplicate 7.3 kernel package"; return 1; }
        kernel_pkg=$pkg
        kernel_pkgver=$pkgver
        ;;
      linux-charcoal-73-headers)
        [[ -z "$headers_pkg" ]] || { info "error: duplicate 7.3 headers package"; return 1; }
        headers_pkg=$pkg
        headers_pkgver=$pkgver
        ;;
      *) info "error: unexpected package identity: $pkgname"; return 1 ;;
    esac
  done

  [[ -n "$kernel_pkg" && -n "$headers_pkg" ]] || { info "error: kernel and matching headers packages are both required"; return 1; }
  [[ "$kernel_pkgver" == "$headers_pkgver" ]] || { info "error: kernel and headers package versions do not match"; return 1; }

  mapfile -t pkgbase_entries < <(bsdtar -tf "$kernel_pkg" | grep -E '^(\./)?usr/lib/modules/[^/]+/pkgbase$' || true)
  [[ ${#pkgbase_entries[@]} -eq 1 ]] || { info "error: kernel package must contain exactly one modules pkgbase marker"; return 1; }
  entry=${pkgbase_entries[0]}
  module_dir=${entry%/pkgbase}
  archive_listing="$(bsdtar -tf "$kernel_pkg")" || { info "error: cannot list kernel package contents"; return 1; }
  grep -Fxq "$module_dir/vmlinuz" <<< "$archive_listing" || { info "error: kernel package has no modules/vmlinuz image"; return 1; }
  package_base="$(bsdtar -xOf "$kernel_pkg" "$entry" | tr -d '\r\n')" || { info "error: cannot read kernel package boot identity"; return 1; }
  [[ "$package_base" == linux-neptune-73 ]] || {
    info "error: kernel package boot identity is '$package_base', expected linux-neptune-73"
    return 1
  }
}

list_installed_packages() {
  pacman -Qq || die "Could not query installed packages"
}

select_stock_kernel() {
  local installed_file=$1 pkgbase=${2:-linux-charcoal-73} name
  local stock="linux-neptune-${pkgbase#linux-charcoal-}"
  while IFS= read -r name; do
    case "$name" in
      "$stock"|"$stock-headers") printf '%s\n' "$name" ;;
    esac
  done < "$installed_file"
}

confirm_stock_removal() {
  local -n stock_ref=$1
  (( ${#stock_ref[@]} > 0 )) || return 0

  info "The matching SteamOS 7.3 stock kernel will be removed before Charcoal is installed to free system space."
  info "This removes the stock-kernel fallback; the installer will ask for confirmation before changing packages."
}

confirm_transaction() {
  local release_tag=$1
  shift
  local -a previous=("$@")
  info "Verified 7.3 release: ${release_tag}"
  if (( ${#previous[@]} )); then
    info "The following old kernel packages will be removed:"
    printf '  - %s\n' "${previous[@]}"
  fi
  info "The new kernel and headers are already downloaded and SHA-256 verified. The installer never reboots automatically."
  [[ "${CHARCOAL_73_ASSUME_YES:-0}" == "1" ]] && return 0
  [[ -t 0 ]] || die "Interactive confirmation is required; rerun in a terminal"
  local answer
  read -r -p "Continue with the Charcoal SteamOS 7.3 installation? [s/N] " answer
  case "$answer" in
    s|S|y|Y|yes|YES|sim|SIM) ;;
    *) die "Installation cancelled before any package was changed" ;;
  esac
}

capture_rollback_packages() {
  local -n package_names=$1
  (( ${#package_names[@]} > 0 )) || return 0
  local rollback_dir="$WORKDIR/rollback" name version candidate found missing=0
  mkdir -p "$rollback_dir"
  for name in "${package_names[@]}"; do
    version="$(pacman -Q "$name" 2>/dev/null | awk '{print $2}')" || true
    [[ -n "$version" ]] || { missing=1; continue; }
    found=""
    for candidate in /var/cache/pacman/pkg/"${name}-${version}"-*.pkg.tar.zst; do
      [[ -f "$candidate" ]] && { found=$candidate; break; }
    done
    if [[ -n "$found" ]]; then
      cp -- "$found" "$rollback_dir/"
    else
      missing=1
    fi
  done
  if (( missing == 0 )); then
    ROLLBACK_READY=1
  else
    info "warning: not every removed kernel package is present in pacman's cache; automatic rollback may be unavailable."
  fi
}

attempt_rollback() {
  (( ROLLBACK_READY )) || return 1
  local -a rollback_packages
  mapfile -d '' -t rollback_packages < <(find "$WORKDIR/rollback" -maxdepth 1 -type f -name '*.pkg.tar.zst' -print0 | sort -z)
  (( ${#rollback_packages[@]} > 0 )) || return 1
  info "Installation failed; attempting to restore the previous SteamOS kernel..."
  local -a installed_charcoal=()
  local package_name
  for package_name in linux-charcoal-73 linux-charcoal-73-headers; do
    if pacman -Qq "$package_name" >/dev/null 2>&1; then
      installed_charcoal+=("$package_name")
    fi
  done
  if (( ${#installed_charcoal[@]} > 0 )); then
    run_privileged pacman -Rdd --noconfirm "${installed_charcoal[@]}" || return 1
  fi
  if ! run_privileged pacman -U --noconfirm "${rollback_packages[@]}"; then
    return 1
  fi
  run_privileged mkinitcpio -p linux-neptune-73 || return 1
  verify_boot_artifacts || return 1
  _update_grub || return 1
  verify_grub_entry || return 1
}

main() {
  for cmd in curl python3 zstd sha256sum mktemp pacman bsdtar awk grep tr find sort mkinitcpio steamos-readonly steamos-devmode; do require_command "$cmd"; done
  (( EUID == 0 )) || require_command sudo
  verify_host_platform || die "Unsupported SteamOS version; no packages were changed"
  WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/charcoal-73-installer.XXXXXX")"
  trap cleanup EXIT

  info "Fetching published Charcoal SteamOS 7.3 releases..."
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --retry 3 --connect-timeout 15 --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' --user-agent "$USER_AGENT" \
    --output "$WORKDIR/releases.json" "$RELEASES_API"

  local metadata
  metadata="$(parse_release_metadata "$WORKDIR/releases.json")" || die "Could not identify a valid SteamOS 7.3 release"
  local -a fields
  mapfile -t fields <<< "$metadata"
  (( ${#fields[@]} == 5 )) || die "Incomplete GitHub 7.3 release metadata"

  local release_tag=${fields[0]} archive_name=${fields[1]} archive_url=${fields[2]}
  local checksum_name=${fields[3]} checksum_url=${fields[4]}
  local archive_path="$WORKDIR/$archive_name" checksum_path="$WORKDIR/$checksum_name" package_dir="$WORKDIR/packages"

  info "Downloading ${release_tag}..."
  download_file "$archive_url" "$archive_path"
  download_file "$checksum_url" "$checksum_path"
  info "Verifying release ZIP SHA-256..."
  verify_release_archive "$archive_path" "$checksum_path" "$archive_name"
  info "Extracting and verifying SteamOS 7.3 packages..."
  extract_and_verify_packages "$archive_path" "$package_dir"

  # r1 has the right 7.3 kernel payload but the wrong mkinitcpio pkgbase.
  # Normalize only the marker and its package .MTREE record; kernel bytes remain untouched.
  local normalizer="$WORKDIR/normalize-legacy-73-package.py"
  download_file "$NORMALIZER_URL" "$normalizer"
  local package
  for package in "$package_dir"/linux-charcoal-73-*.pkg.tar.zst; do
    [[ "$package" == *-headers-* ]] && continue
    info "Correcting and verifying the r1 SteamOS boot identity in the local package copy..."
    python3 "$normalizer" "$package" || die "Could not safely normalize the downloaded 7.3 kernel package"
  done

  local -a packages
  mapfile -d '' -t packages < <(find "$package_dir" -maxdepth 1 -type f -name 'linux-charcoal-*.pkg.tar.zst' -print0 | sort -z)
  (( ${#packages[@]} == 2 )) || die "Verified release does not contain exactly kernel and headers"

  info "Checking package metadata without starting a transaction..."
  local pkg pkgname pkgbase=""
  for pkg in "${packages[@]}"; do
    pkgname="$(pacman -Qp "$pkg" | awk '{print $1}')" || die "pacman could not read package metadata: $pkg"
    [[ "$pkgname" =~ ^linux-charcoal-73(-headers)?$ ]] \
      || die "Expected a Linux 7.3 Charcoal package, got: $pkgname"
    pkgbase=${pkgname%-headers}
  done

  verify_kernel_package_identity packages || die "Release package contents do not match the required linux-neptune-73 boot identity"

  local installed_file="$WORKDIR/installed-packages.txt"
  list_installed_packages > "$installed_file"
  local -a stock_packages remove_packages
  mapfile -t stock_packages < <(select_stock_kernel "$installed_file" "$pkgbase")

  if ! grep -Fxq 'linux-neptune-73' "$installed_file"; then
    die "The Valve linux-neptune-73 stock kernel is not installed; refusing to replace an unknown or already-broken boot setup"
  fi

  verify_existing_boot_state || die "Existing SteamOS boot state is not healthy; no package changes were made"

  confirm_stock_removal stock_packages
  # Only the matching SteamOS stock 7.3 kernel may be removed. Existing
  # Charcoal packages are left in place; pacman -U upgrades them in-place.
  remove_packages=("${stock_packages[@]}")
  capture_rollback_packages remove_packages
  if (( ${#remove_packages[@]} > 0 && ! ROLLBACK_READY )); then
    die "Refusing to remove the stock kernel: exact rollback packages are not available in pacman's cache"
  fi
  confirm_transaction "$release_tag" "${remove_packages[@]}"

  info "Making SteamOS writable for the package transaction..."
  run_privileged steamos-readonly disable
  MADE_ROOT_WRITABLE=1
  info "Enabling SteamOS developer mode..."
  run_privileged steamos-devmode enable --no-prompt

  if (( ${#remove_packages[@]} )); then
    info "Removing conflicting/previous kernel packages without cascading dependency removal..."
    run_privileged pacman -Rdd --noconfirm "${remove_packages[@]}"
  fi

  info "Installing verified Charcoal SteamOS 7.3 ${release_tag}..."
  if ! run_privileged pacman -U --noconfirm "${packages[@]}"; then
    if attempt_rollback; then
      die "SteamOS 7.3 installation failed; previous kernel packages were restored"
    fi
    die "SteamOS 7.3 installation failed after kernel removal; do not reboot until a working kernel is installed"
  fi


  info "Generating and checking the SteamOS 7.3 boot image and initramfs..."
  if ! run_privileged mkinitcpio -p linux-neptune-73 || ! verify_boot_artifacts; then
    if attempt_rollback; then
      die "Charcoal boot-image validation failed; the previous SteamOS kernel was restored"
    fi
    die "Charcoal boot-image validation failed and automatic rollback was unsuccessful; do not reboot"
  fi

  info "Updating the SteamOS bootloader configuration..."
  if ! _update_grub || ! verify_grub_entry; then
    if attempt_rollback; then
      die "Charcoal GRUB validation failed; the previous SteamOS kernel was restored"
    fi
    die "Charcoal GRUB validation failed and automatic rollback was unsuccessful; do not reboot"
  fi
  info "Charcoal SteamOS 7.3 ${release_tag} installed; kernel, initramfs and GRUB references verified."
  info "Reboot only after the installer reports all three boot checks passed."
}

diagnose_boot_state() {
  local failures=0 grub="" module_marker="" marker_found=0

  info "Read-only SteamOS 3.10 / Charcoal 7.3 diagnostic"
  if verify_host_platform; then
    info "PASS: host is SteamOS 3.10"
  else
    info "FAIL: host is not supported"
    failures=$((failures + 1))
  fi

  if pacman -Q linux-neptune-73; then
    info "PASS: Valve linux-neptune-73 package is installed"
  else
    info "FAIL: Valve linux-neptune-73 package is missing"
    failures=$((failures + 1))
  fi
  if pacman -Q linux-charcoal-73 2>/dev/null; then
    info "INFO: Charcoal Linux 7.3 package is installed"
  else
    info "INFO: Charcoal Linux 7.3 package is not installed"
  fi

  if verify_boot_artifacts; then
    info "PASS: mkinitcpio preset, kernel image and initramfs are present"
  else
    info "FAIL: one or more expected SteamOS 7.3 boot artifacts are missing"
    failures=$((failures + 1))
  fi

  while IFS= read -r module_marker; do
    [[ -r "$module_marker" ]] || continue
    local marker_value
    marker_value="$(<"$module_marker")"
    info "Module marker: $module_marker = $marker_value"
    if [[ "$marker_value" == linux-neptune-73 ]]; then
      marker_found=1
    fi
  done < <(find /usr/lib/modules -mindepth 2 -maxdepth 2 -type f -name pkgbase -print 2>/dev/null)
  if (( marker_found )); then
    info "PASS: installed module pkgbase matches linux-neptune-73"
  else
    info "FAIL: no installed module pkgbase matches linux-neptune-73"
    failures=$((failures + 1))
  fi

  for candidate in /efi/EFI/SteamOS/grub.cfg /efi/EFI/steamos/grub.cfg /boot/efi/EFI/SteamOS/grub.cfg /boot/efi/EFI/steamos/grub.cfg /boot/grub/grub.cfg; do
    if run_privileged test -s "$candidate"; then
      grub=$candidate
      break
    fi
  done
  if [[ -z "$grub" ]]; then
    info "FAIL: no standard SteamOS GRUB config was found"
    failures=$((failures + 1))
  else
    info "GRUB config: $grub"
    if run_privileged grep -Fq '/boot/vmlinuz-linux-neptune-73' "$grub" &&
       run_privileged grep -Fq '/boot/initramfs-linux-neptune-73.img' "$grub"; then
      info "PASS: GRUB references both expected SteamOS 7.3 boot artifacts"
    else
      info "FAIL: GRUB is missing one or both expected SteamOS 7.3 boot references"
      failures=$((failures + 1))
    fi
  fi

  info "Boot filesystem space:"
  df -h /boot / 2>/dev/null || true
  if (( failures > 0 )); then
    info "Diagnostic result: $failures check(s) failed. No changes were made."
    return 1
  fi
  info "Diagnostic result: all required checks passed. No changes were made."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  if [[ "${1:-}" == "--check-only" ]]; then
    diagnose_boot_state
  elif (( $# > 0 )); then
    die "Unknown option: $1 (supported: --check-only)"
  else
    main
  fi
fi
