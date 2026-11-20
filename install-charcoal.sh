#!/usr/bin/env bash
# Install a published Charcoal Linux 7.3 release for SteamOS 3.10.

set -Eeuo pipefail

readonly RELEASE_TAG="steamos-3.10-linux-7.3-build-99"
readonly RELEASE_BASE_URL="https://github.com/Marctraider/linux-charcoal-vulcano/releases/download/${RELEASE_TAG}"
readonly KERNEL_ASSET="linux-charcoal-73-7.3.1.valve2.cc1-3-x86_64.pkg.tar.zst"
readonly HEADERS_ASSET="linux-charcoal-73-headers-7.3.1.valve2.cc1-3-x86_64.pkg.tar.zst"
readonly CHECKSUM_ASSET="SHA256SUMS"
# SHA-256 digest reported by GitHub for the uploaded SHA256SUMS release asset.
readonly CHECKSUM_ASSET_SHA256="c89062483306d771676c80df2c91602d37b28ecbfa86c01637a9b55aaa98d6dc"

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
  local url=$1 destination=$2 request_url response_code curl_status attempt
  local partial="${destination}.part"

  # Use only the public GitHub Releases asset URL, never the Actions artifact
  # API (which requires authentication and can return HTTP 401). Release assets
  # redirect to signed URLs; each attempt gets a fresh cache-busting query.
  for attempt in 1 2 3; do
    request_url=$url
    case "$url" in
      https://github.com/*/releases/download/*)
        request_url="${url}?download=1&cachebust=$(date +%s)-$$-$RANDOM-$attempt"
        ;;
      *)
        die "Refusing non-release download URL: $url"
        ;;
    esac

    response_code="000"
    curl_status=0
    response_code="$(curl --fail --silent --show-error --location \
      --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 900 \
      -H 'Cache-Control: no-cache, no-store' -H 'Pragma: no-cache' \
      --output "$partial" --write-out '%{http_code}' "$request_url")" || curl_status=$?

    if (( curl_status == 0 )) && [[ "$response_code" == "200" ]] && [[ -s "$partial" ]]; then
      mv -- "$partial" "$destination"
      return 0
    fi

    rm -f -- "$partial"
    if [[ "$response_code" == "401" || "$response_code" == "403" || "$response_code" == "429" || "$response_code" =~ ^5[0-9][0-9]$ || "$response_code" == "000" ]]; then
      info "GitHub release download attempt $attempt failed (HTTP $response_code); retrying with a fresh URL..."
      sleep "$attempt"
      continue
    fi
    die "GitHub release download failed with HTTP $response_code; no packages were changed"
  done

  die "GitHub release download failed after three fresh attempts; check the public release asset and network connection"
}

verify_release_checksums() {
  local package_dir=$1 sums_file=$2
  python3 - "$sums_file" "$KERNEL_ASSET" "$HEADERS_ASSET" <<'PY'
import re,sys
from pathlib import Path
path=Path(sys.argv[1])
expected=set(sys.argv[2:])
entries={}
for line in path.read_text(encoding="utf-8").splitlines():
    m=re.fullmatch(r"([0-9a-fA-F]{64}) [ *](.+)", line)
    if not m:
        raise SystemExit("Invalid SHA256SUMS line")
    digest,name=m.groups()
    if name in entries or name not in expected or "/" in name or "\\" in name:
        raise SystemExit("Unexpected or duplicate checksum entry: "+name)
    entries[name]=digest.lower()
if set(entries)!=expected:
    raise SystemExit("SHA256SUMS must contain exactly the kernel and headers package entries")
PY
  (
    cd "$package_dir"
    sha256sum --check --status "$sums_file"
  ) || die "One or more downloaded package checksums failed; no packages were changed"
}

verify_kernel_package_identity() {
  local -n package_files_ref=$1
  local pkg pkgname="" pkgver="" kernel_pkg="" headers_pkg="" kernel_pkgver="" headers_pkgver=""
  local entry module_dir package_base archive_listing
  local -a pkgbase_entries=()

  for pkg in "${package_files_ref[@]}"; do
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

  local -a config_entries=()
  mapfile -t config_entries < <(bsdtar -tf "$headers_pkg" | grep -E '^(\./)?usr/lib/modules/[^/]+/build/\.config$' || true)

  [[ ${#config_entries[@]} -eq 1 ]] || { info "error: headers package must contain exactly one resolved kernel .config"; return 1; }
  local config_data expected
  config_data="$(bsdtar -xOf "$headers_pkg" "${config_entries[0]}")" || { info "error: cannot read packaged kernel configuration"; return 1; }
  for expected in \
    'CONFIG_CPU_MITIGATIONS=y' \
    'CONFIG_X86_AMD_PSTATE=y' \
    'CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3' \
    'CONFIG_CMDLINE_BOOL=y' \
    'CONFIG_CMDLINE="amd_pstate.epp_boost=1 mitigations=off"' \
    '# CONFIG_CMDLINE_OVERRIDE is not set' \
    'CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE=y' \
    '# CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3 is not set' \
    'CONFIG_LTO_CLANG_FULL=y' \
    'CONFIG_POLLY_CLANG=y' \
    'CONFIG_SCHED_CLASS_EXT=y' \
    'CONFIG_BPF=y' \
    'CONFIG_BPF_SYSCALL=y' \
    'CONFIG_PERF_EVENTS=y' \
    'CONFIG_UPROBES=y' \
    'CONFIG_UPROBE_EVENTS=y' \
    'CONFIG_BPF_EVENTS=y' \
    'CONFIG_BPF_JIT=y' \
    'CONFIG_BPF_JIT_ALWAYS_ON=y' \
    'CONFIG_BPF_JIT_DEFAULT_ON=y' \
    'CONFIG_DEBUG_INFO_DWARF5=y' \
    'CONFIG_DEBUG_INFO_BTF=y' \
    'CONFIG_TRACEPOINTS=y' \
    'CONFIG_FTRACE=y' \
    'CONFIG_FTRACE_SYSCALLS=y' \
    'CONFIG_NTSYNC=y'; do
    if ! grep -qxF "$expected" <<< "$config_data"; then
      info "error: build package configuration is missing $expected"
      return 1
    fi
  done
  grep -qxF '# CONFIG_ZSWAP is not set' <<< "$config_data" || { info "error: build package has not disabled ZSWAP"; return 1; }
}

charcoal_upgrade_installed() {
  pacman -Qq linux-charcoal-73 >/dev/null 2>&1
}

confirm_transaction() {
  local release_tag=$1
  shift
  local -a previous=("$@")
  info "Verified 7.3 build: ${release_tag}"
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
      ln -s -- "$found" "$rollback_dir/${found##*/}"
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
  mapfile -d '' -t rollback_packages < <(find "$WORKDIR/rollback" -maxdepth 1 \( -type f -o -type l \) -name '*.pkg.tar.zst' -print0 | sort -z)
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

install_lavd_scheduler() {
  local unit=/etc/systemd/system/charcoal-lavd.service

  info "Installing the SteamOS sched_ext userspace scheduler package..."
  if ! run_privileged pacman -S --needed --noconfirm scx-scheds; then
    die "Could not install the SteamOS scx-scheds package; Charcoal is installed, but LAVD is not configured. Do not assume LAVD is active."
  fi
  run_privileged test -x /usr/bin/scx_lavd || die "scx-scheds installed without /usr/bin/scx_lavd"

  info "Configuring LAVD as the persistent default scheduler..."
  run_privileged install -d -m 0755 /etc/systemd/system
  run_privileged tee "$unit" >/dev/null <<'UNIT'
[Unit]
Description=Charcoal default sched_ext LAVD scheduler
After=systemd-modules-load.service
ConditionPathExists=/sys/kernel/btf/vmlinux

[Service]
Type=simple
ExecStart=/usr/bin/scx_lavd --performance
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
  run_privileged systemctl daemon-reload
  run_privileged systemctl enable charcoal-lavd.service
  info "LAVD is enabled for the next boot. Reboot into Charcoal Linux 7.3 to activate it."
}

main() {
  for cmd in curl python3 zstd sha256sum mktemp pacman bsdtar awk grep tr find sort ln mv sleep date mkinitcpio steamos-readonly steamos-devmode systemctl tee; do require_command "$cmd"; done
  (( EUID == 0 )) || require_command sudo
  verify_host_platform || die "Unsupported SteamOS version; no packages were changed"
  WORKDIR="$(mktemp -d /dev/shm/charcoal-73-installer.XXXXXX)"
  trap cleanup EXIT

  [[ "$CHECKSUM_ASSET_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "The published checksum-file digest is invalid; no packages were changed"
  local package_dir="$WORKDIR/packages"
  local sums_path="$WORKDIR/$CHECKSUM_ASSET"
  mkdir -m 0700 "$package_dir"

  info "Downloading the SHA256SUMS file for release ${RELEASE_TAG}..."
  download_file "$RELEASE_BASE_URL/$CHECKSUM_ASSET" "$sums_path"
  printf '%s  %s\n' "$CHECKSUM_ASSET_SHA256" "$sums_path" | sha256sum --check --status \
    || die "Published SHA256SUMS file failed its pinned checksum; no packages were changed"

  info "Downloading the Charcoal kernel and matching headers packages..."
  download_file "$RELEASE_BASE_URL/$KERNEL_ASSET" "$package_dir/$KERNEL_ASSET"
  download_file "$RELEASE_BASE_URL/$HEADERS_ASSET" "$package_dir/$HEADERS_ASSET"

  info "Verifying both packages against the published SHA256SUMS..."
  verify_release_checksums "$package_dir" "$sums_path"

  local -a packages
  mapfile -d '' -t packages < <(find "$package_dir" -maxdepth 1 -type f -name 'linux-charcoal-*.pkg.tar.zst' -print0 | sort -z)
  (( ${#packages[@]} == 2 )) || die "Downloaded release does not contain exactly kernel and headers"

  info "Checking downloaded build package metadata without starting a transaction..."
  local pkg pkgname pkgbase=""
  for pkg in "${packages[@]}"; do
    pkgname="$(pacman -Qp "$pkg" | awk '{print $1}')" || die "pacman could not read package metadata: $pkg"
    [[ "$pkgname" =~ ^linux-charcoal-73(-headers)?$ ]] \
      || die "Expected a Linux 7.3 Charcoal package, got: $pkgname"
    pkgbase=${pkgname%-headers}
  done

  verify_kernel_package_identity packages || die "Build artifact package contents do not match the required linux-neptune-73 boot identity"

  local charcoal_installed=0
  if charcoal_upgrade_installed; then
    charcoal_installed=1
    info "Existing Charcoal 7.3 detected; replacing it directly with the current Charcoal 7.3 packages."
  else
    if ! pacman -Qq linux-neptune-73 >/dev/null 2>&1; then
      die "Neither Valve linux-neptune-73 nor an existing Charcoal 7.3 kernel is installed; refusing an unknown boot setup"
    fi
    verify_existing_boot_state || die "Existing SteamOS boot state is not healthy; no package changes were made"
  fi

  local -a previous_packages=()
  local old_package
  if (( charcoal_installed )); then
    for old_package in linux-charcoal-73 linux-charcoal-73-headers; do
      if pacman -Qq "$old_package" >/dev/null 2>&1; then previous_packages+=("$old_package"); fi
    done
    # Reuse cached old packages by symlink from /dev/shm; never duplicate
    # rollback archives onto the SteamOS root filesystem.
    if (( ${#previous_packages[@]} > 0 )); then capture_rollback_packages previous_packages; fi
  fi

  confirm_transaction "Linux 7.3 release ${RELEASE_TAG} (${KERNEL_ASSET} + ${HEADERS_ASSET})" "${previous_packages[@]}"

  info "Making SteamOS writable for the package transaction..."
  run_privileged steamos-readonly disable
  MADE_ROOT_WRITABLE=1
  info "Enabling SteamOS developer mode..."
  run_privileged steamos-devmode enable --no-prompt

  local install_log="$WORKDIR/pacman-install.log"
  if (( charcoal_installed )); then
    info "Replacing the existing Charcoal 7.3 kernel and headers in one pacman transaction..."
    if ! LC_ALL=C run_privileged pacman -U --noconfirm "${packages[@]}" >"$install_log" 2>&1; then
      cat "$install_log" >&2
      if attempt_rollback; then
        die "Charcoal upgrade failed; the previous Charcoal 7.3 packages and boot files were restored"
      fi
      die "Charcoal upgrade failed; pacman did not complete the replacement. Do not reboot until the existing kernel is confirmed."
    fi
  else
    # Free the space occupied by the stock Valve kernel before installing
    # Charcoal. Preserve cached package archives for rollback when available.
    local -a stock_packages=()
    for old_package in linux-neptune-73 linux-neptune-73-headers; do
      if pacman -Qq "$old_package" >/dev/null 2>&1; then
        stock_packages+=("$old_package")
      fi
    done
    (( ${#stock_packages[@]} > 0 )) || die "The stock Valve kernel package is not installed; refusing an unknown boot setup"
    capture_rollback_packages stock_packages
    info "Removing the stock SteamOS 7.3 kernel package(s) before installing Charcoal..."
    if ! run_privileged pacman -Rdd --noconfirm "${stock_packages[@]}"; then
      die "Could not remove the stock Valve kernel package(s); Charcoal was not installed. Do not reboot until the existing boot state is checked."
    fi
    info "Installing Charcoal Linux 7.3..."
    if ! LC_ALL=C run_privileged pacman -U --noconfirm "${packages[@]}" >"$install_log" 2>&1; then
      cat "$install_log" >&2
      if attempt_rollback; then
        die "Charcoal installation failed; the cached stock SteamOS kernel was restored"
      fi
      die "Charcoal installation failed after removing the stock kernel and automatic rollback was unavailable or unsuccessful; do not reboot"
    fi
  fi

  install_lavd_scheduler

  rm -rf -- "$package_dir"
  info "Generating the SteamOS 7.3 boot image and initramfs..."
  if ! run_privileged mkinitcpio -p linux-neptune-73; then
    info "warning: mkinitcpio returned a non-zero status; continuing with installation"
  fi

  info "Updating the SteamOS bootloader configuration..."
  if ! _update_grub || ! verify_grub_entry; then
    if attempt_rollback; then
      die "Charcoal GRUB validation failed; the previous SteamOS kernel was restored"
    fi
    die "Charcoal GRUB validation failed and automatic rollback was unsuccessful; do not reboot"
  fi
  info "Charcoal SteamOS 3.10 / Linux 7.3 release ${RELEASE_TAG} installed."
  info "LAVD userspace is installed and enabled for boot. Reboot into Charcoal Linux 7.3, then run: sudo charcoal-status"
}

diagnose_boot_state() {
  local failures=0 grub="" marker_found=0
  info "Read-only SteamOS 3.10 / Charcoal Linux 7.3 diagnostic"
  if verify_host_platform; then info "PASS: SteamOS 3.10"; else info "FAIL: unsupported host"; failures=$((failures+1)); fi
  if pacman -Q linux-charcoal-73 2>/dev/null; then info "PASS: Charcoal 7.3 installed"
  elif pacman -Q linux-neptune-73 2>/dev/null; then info "INFO: Valve 7.3 installed; Charcoal not installed"
  else info "FAIL: neither Valve nor Charcoal 7.3 installed"; failures=$((failures+1)); fi
  if verify_boot_artifacts; then info "PASS: preset, kernel and initramfs present"; else info "FAIL: expected boot artifacts missing"; failures=$((failures+1)); fi
  local marker marker_value
  while IFS= read -r marker; do
    [[ -r "$marker" ]] || continue
    marker_value="$(<"$marker")"
    [[ "$marker_value" == linux-neptune-73 ]] && marker_found=1
  done < <(find /usr/lib/modules -mindepth 2 -maxdepth 2 -type f -name pkgbase -print 2>/dev/null)
  if (( marker_found )); then info "PASS: module pkgbase linux-neptune-73"; else info "FAIL: module pkgbase mismatch"; failures=$((failures+1)); fi
  # Runtime feature checks are intentionally delegated to charcoal-status
  # after reboot, when the newly installed kernel is actually running.
  for candidate in /efi/EFI/SteamOS/grub.cfg /efi/EFI/steamos/grub.cfg /boot/efi/EFI/SteamOS/grub.cfg /boot/efi/EFI/steamos/grub.cfg /boot/grub/grub.cfg; do
    if run_privileged test -s "$candidate"; then grub=$candidate; break; fi
  done
  if [[ -z "$grub" ]]; then info "FAIL: no standard GRUB config"; failures=$((failures+1))
  elif run_privileged grep -Fq '/boot/vmlinuz-linux-neptune-73' "$grub" && run_privileged grep -Fq '/boot/initramfs-linux-neptune-73.img' "$grub"; then info "PASS: GRUB references 7.3 kernel and initramfs"
  else info "FAIL: GRUB references missing 7.3 boot files"; failures=$((failures+1)); fi
  df -h /boot / 2>/dev/null || true
  if (( failures )); then info "Diagnostic result: $failures installation/boot check failure(s); no changes made"; return 1; fi
  info "Diagnostic result: installation and boot-file checks passed; no changes made"
  info "Runtime features have not been checked. After booting into Charcoal Linux 7.3, run: sudo charcoal-status"
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
