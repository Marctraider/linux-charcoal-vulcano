#!/usr/bin/env bash
# Install the latest successful NAP experiment build for SteamOS 3.10 / Linux 7.3.

set -Eeuo pipefail

readonly REPOSITORY="Marctraider/linux-charcoal-vulcano"
readonly WORKFLOW_RUNS_API="https://api.github.com/repos/${REPOSITORY}/actions/workflows/build-kernel-7.3.yml/runs?branch=experiment%2Fsteamos-3.10-linux-7.3-nap&status=success&per_page=30"
readonly WORKFLOW_ARTIFACTS_API_PREFIX="https://api.github.com/repos/${REPOSITORY}/actions/runs/"
readonly ARTIFACT_DOWNLOAD_PREFIX="https://api.github.com/repos/${REPOSITORY}/actions/artifacts/"
readonly NAP_BRANCH="experiment/steamos-3.10-linux-7.3-nap"
readonly ARTIFACT_NAME_PREFIX="charcoal-steamos-3.10-linux-7.3-nap-build-"
readonly USER_AGENT="charcoal-73-nap-installer"

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

select_latest_nap_run() {
  python3 - "$1" "$NAP_BRANCH" <<'PY'
import json, sys
data=json.load(open(sys.argv[1],encoding="utf-8"))
runs=data.get("workflow_runs",[]) if isinstance(data,dict) else []
valid=[r for r in runs if isinstance(r,dict) and r.get("head_branch")==sys.argv[2]
 and r.get("status")=="completed" and r.get("conclusion")=="success"
 and r.get("path")==".github/workflows/build-kernel-7.3.yml"
 and isinstance(r.get("id"),int) and isinstance(r.get("run_number"),int)
 and isinstance(r.get("head_sha"),str)]
if not valid: raise SystemExit("No successful NAP-branch build found")
r=max(valid,key=lambda x:(x["run_number"],x["id"]))
print(r["id"]); print(r["run_number"]); print(r["head_sha"])
PY
}
select_nap_artifact() {
  python3 - "$1" "$ARTIFACT_NAME_PREFIX" "$2" "$ARTIFACT_DOWNLOAD_PREFIX" <<'PY'
import json,sys
data=json.load(open(sys.argv[1],encoding="utf-8"))
items=data.get("artifacts",[]) if isinstance(data,dict) else []
found=[x for x in items if isinstance(x,dict) and x.get("name")==sys.argv[2]+sys.argv[3] and x.get("expired") is False and isinstance(x.get("id"),int)]
if len(found)!=1: raise SystemExit("NAP build artifact missing, expired, or ambiguous")
url=found[0].get("archive_download_url")
if not isinstance(url,str) or not url.startswith(sys.argv[4]): raise SystemExit("Untrusted artifact URL")
print(found[0]["id"]); print(url)
PY
}
extract_and_verify_nap_artifact() {
  python3 - "$1" "$2" <<'PY'
import hashlib,re,stat,sys,zipfile
from pathlib import Path,PurePosixPath
archive,dest=Path(sys.argv[1]),Path(sys.argv[2])
pkg=re.compile(r"linux-charcoal-73(?:-headers)?-[A-Za-z0-9._+-]+\.pkg\.tar\.zst")
sum_re=re.compile(r"([0-9a-fA-F]{64}) [ *](linux-charcoal-73(?:-headers)?-[A-Za-z0-9._+-]+\.pkg\.tar\.zst)")
with zipfile.ZipFile(archive) as z:
 infos=z.infolist(); names=[x.filename for x in infos]
 if len(names)!=len(set(names)): raise SystemExit("Duplicate artifact paths")
 ps=[x for x in infos if "/" not in x.filename and pkg.fullmatch(x.filename)]
 if len(ps)!=2 or sum("-headers-" in x.filename for x in ps)!=1: raise SystemExit("Artifact must contain kernel and headers packages")
 required={"logs/SHA256SUMS-73","logs/makepkg-73.log","logs/prepare-73.log","logs/nap-tools-upstream.json"}
 if not required.issubset(names): raise SystemExit("Artifact missing build provenance")
 sums={}
 for line in z.read("logs/SHA256SUMS-73").decode().splitlines():
  m=sum_re.fullmatch(line)
  if not m or m.group(2) in sums: raise SystemExit("Invalid artifact checksum manifest")
  sums[m.group(2)]=m.group(1).lower()
 if set(sums)!={x.filename for x in ps}: raise SystemExit("Artifact manifest/package mismatch")
 prepare_log=z.read("logs/prepare-73.log").decode("utf-8",errors="replace")
 if "int drm_sched_policy = DRM_SCHED_POLICY_RR;" not in prepare_log: raise SystemExit("Build log does not prove the DRM Round Robin source default was applied")
 if "nap-6.12-v0.6.5.patch" not in prepare_log: raise SystemExit("Build log does not prove the pinned NAP patch was applied")
 dest.mkdir(mode=0o700)
 for x in ps:
  if PurePosixPath(x.filename).name!=x.filename or stat.S_ISLNK(x.external_attr>>16): raise SystemExit("Unsafe package path")
  target=dest/x.filename; h=hashlib.sha256()
  with z.open(x) as src,target.open("xb") as out:
   for b in iter(lambda:src.read(1048576),b""): h.update(b); out.write(b)
  if h.hexdigest()!=sums[x.filename]: target.unlink(missing_ok=True); raise SystemExit("Package checksum failed")
PY
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
  mapfile -t config_entries < <(bsdtar -tf "$headers_pkg" | grep -E '^(./)?usr/lib/modules/[^/]+/build/.config' || true)

  [[ ${#config_entries[@]} -eq 1 ]] || { info "error: headers package must contain exactly one resolved kernel .config"; return 1; }
  local config_data expected
  config_data="$(bsdtar -xOf "$headers_pkg" "${config_entries[0]}")" || { info "error: cannot read packaged kernel configuration"; return 1; }
  for expected in \
    'CONFIG_CPU_IDLE_GOV_NAP=y' \
    'CONFIG_CPU_IDLE_GOV_TEO=y' \
    'CONFIG_CMDLINE="amd_pstate.epp_boost=1 mitigations=off cpuidle.governor=nap"' \
    'CONFIG_BTRFS_FS=y' \
    'CONFIG_ZRAM=m' \
    'CONFIG_ZSMALLOC=m' \
    'CONFIG_ZRAM_DEF_COMP_LZ4=y' \
    'CONFIG_ZRAM_MULTI_COMP=y' \
    'CONFIG_ZRAM_DEF_COMP="lz4"' \
    'CONFIG_SCHED_BORE=y' \
    'CONFIG_SCHED_POC_SELECTOR=y' \
    'CONFIG_LRU_CAST=y' \
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

main() {
  for cmd in curl python3 zstd sha256sum mktemp pacman bsdtar awk grep tr find sort stat ln mkinitcpio steamos-readonly steamos-devmode; do require_command "$cmd"; done
  (( EUID == 0 )) || require_command sudo
  verify_host_platform || die "Unsupported SteamOS version; no packages were changed"
  [[ -d /dev/shm && -w /dev/shm ]] || die "/dev/shm is unavailable; refusing to stage large packages on the root filesystem"
  [[ "$(stat -f -c %T /dev/shm)" == tmpfs ]] || die "/dev/shm is not a tmpfs; refusing to consume root-filesystem space"
  WORKDIR="$(mktemp -d /dev/shm/charcoal-73-installer.XXXXXX)"
  trap cleanup EXIT

  info "Finding latest successful NAP-branch Linux 7.3 build..."
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 15 \
    --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' --user-agent "$USER_AGENT" \
    --output "$WORKDIR/workflow-runs.json" "$WORKFLOW_RUNS_API"
  local run_metadata
  run_metadata="$(select_latest_nap_run "$WORKDIR/workflow-runs.json")" || die "No successful NAP build found"
  local -a run_fields
  mapfile -t run_fields <<< "$run_metadata"
  (( ${#run_fields[@]} == 3 )) || die "Incomplete NAP workflow metadata"
  local run_id=${run_fields[0]} run_number=${run_fields[1]} build_commit=${run_fields[2]}
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 15 \
    --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' --user-agent "$USER_AGENT" \
    --output "$WORKDIR/artifacts.json" "${WORKFLOW_ARTIFACTS_API_PREFIX}${run_id}/artifacts"
  local artifact_metadata
  artifact_metadata="$(select_nap_artifact "$WORKDIR/artifacts.json" "$run_number")" || die "NAP build artifact not found"
  local -a artifact_fields
  mapfile -t artifact_fields <<< "$artifact_metadata"
  (( ${#artifact_fields[@]} == 2 )) || die "Incomplete NAP artifact metadata"
  local artifact_url=${artifact_fields[1]}
  local archive_path="$WORKDIR/nap-build.zip" package_dir="$WORKDIR/packages"
  info "Downloading NAP build #${run_number} (${build_commit:0:12})..."
  download_file "$artifact_url" "$archive_path"
  info "Verifying NAP package checksums..."
  extract_and_verify_nap_artifact "$archive_path" "$package_dir"
  rm -f -- "$archive_path"

  local -a packages
  mapfile -d '' -t packages < <(find "$package_dir" -maxdepth 1 -type f -name 'linux-charcoal-*.pkg.tar.zst' -print0 | sort -z)
  (( ${#packages[@]} == 2 )) || die "Verified build artifact does not contain exactly kernel and headers"

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
    info "Existing Charcoal 7.3 detected; replacing it directly with the NAP packages."
  else
    if ! pacman -Qq linux-neptune-73 >/dev/null 2>&1; then
      die "Neither Valve linux-neptune-73 nor an existing Charcoal 7.3 kernel is installed; refusing an unknown boot setup"
    fi
    verify_existing_boot_state || die "Existing SteamOS boot state is not healthy; no package changes were made"
  fi

  local -a previous_packages=() stock_packages=()
  local old_package
  if (( charcoal_installed )); then
    for old_package in linux-charcoal-73 linux-charcoal-73-headers; do
      if pacman -Qq "$old_package" >/dev/null 2>&1; then previous_packages+=("$old_package"); fi
    done
    # Reuse cached old packages by symlink from /dev/shm; never duplicate
    # rollback archives onto the SteamOS root filesystem.
    if (( ${#previous_packages[@]} > 0 )); then capture_rollback_packages previous_packages; fi
  else
    stock_packages=(linux-neptune-73)
    if pacman -Qq linux-neptune-73-headers >/dev/null 2>&1; then stock_packages+=(linux-neptune-73-headers); fi
  fi

  confirm_transaction "NAP build #${run_number} (${build_commit:0:12})" "${previous_packages[@]}"

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
        die "NAP upgrade failed; the previous Charcoal 7.3 packages and boot files were restored"
      fi
      die "NAP upgrade failed; pacman did not complete the replacement. Do not reboot until the existing kernel is confirmed."
    fi
  else
    info "Installing Charcoal alongside the existing SteamOS 7.3 kernel..."
    if ! LC_ALL=C run_privileged pacman -U --noconfirm "${packages[@]}" >"$install_log" 2>&1; then
      cat "$install_log" >&2
      if ! is_pacman_disk_space_error "$install_log"; then
        die "SteamOS 7.3 package installation failed; the stock kernel was not removed"
      fi
      if (( ${#stock_packages[@]} == 0 )); then
        die "Not enough disk space and no stock SteamOS 7.3 kernel package is available to remove"
      fi
      capture_rollback_packages stock_packages
      confirm_stock_removal stock_packages
      info "Removing only the matching SteamOS 7.3 stock kernel packages..."
      run_privileged pacman -Rdd --noconfirm "${stock_packages[@]}"
      info "Retrying the verified Charcoal packages after freeing space..."
      if ! run_privileged pacman -U --noconfirm "${packages[@]}"; then
        if attempt_rollback; then
          die "SteamOS 7.3 installation failed; previous stock kernel packages were restored"
        fi
        die "SteamOS 3.10 / Linux 7.3 installation failed after stock-kernel removal; do not reboot"
      fi
    fi
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
  info "Charcoal SteamOS 3.10 / Linux 7.3 NAP build #${run_number} (${build_commit:0:12}) installed; kernel, initramfs and GRUB references verified."
  info "Reboot only after the installer reports all three boot checks passed."
}

diagnose_boot_state() {
  local failures=0 grub="" marker_found=0
  info "Read-only SteamOS 3.10 / Charcoal Linux 7.3 NAP diagnostic"
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
  local cfg="" cfgfile=""
  if [[ -r /proc/config.gz ]] && command -v zcat >/dev/null 2>&1; then cfg="$(zcat /proc/config.gz 2>/dev/null || true)"
  elif [[ -r "/boot/config-$(uname -r)" ]]; then cfgfile="/boot/config-$(uname -r)"
  elif [[ -r "/usr/lib/modules/$(uname -r)/build/.config" ]]; then cfgfile="/usr/lib/modules/$(uname -r)/build/.config"; fi
  [[ -n "$cfgfile" ]] && cfg="$(<"$cfgfile")"
  if [[ -n "$cfg" ]]; then
    local expected
    for expected in CONFIG_BTRFS_FS=y CONFIG_ZRAM=m; do
      if grep -qxF "$expected" <<< "$cfg"; then info "PASS: $expected"; else info "FAIL: missing $expected"; failures=$((failures+1)); fi
    done
    if grep -qxF CONFIG_CPU_IDLE_GOV_NAP=y <<< "$cfg"; then info "PASS: NAP governor is compiled in"; else info "INFO: the currently running kernel predates the NAP build"; fi
    grep -qxF '# CONFIG_ZSWAP is not set' <<< "$cfg" && info "PASS: ZSWAP disabled" || info "WARN: ZSWAP state not confirmed"
  else info "WARN: running kernel config unavailable; compile-time settings not checked"; fi
  local governor_file=/sys/devices/system/cpu/cpuidle/current_governor
  if [[ -r "$governor_file" ]]; then
    local governor; governor="$(<"$governor_file")"
    if [[ "$governor" == nap ]]; then info "PASS: NAP active"; else info "INFO: currently active CPUIdle governor is $governor (NAP takes effect after booting the NAP kernel)"; fi
  else info "WARN: CPUIdle governor sysfs state unavailable"; fi
  local drm_file=/sys/module/drm/parameters/sched_policy
  if [[ -r "$drm_file" ]]; then
    local policy; policy="$(<"$drm_file")"
    if [[ "$policy" == 1 || "$policy" == RR || "$policy" == rr ]]; then info "PASS: DRM Round Robin policy"; else info "FAIL: DRM policy is $policy"; failures=$((failures+1)); fi
  else info "WARN: DRM scheduler policy is not exposed; RR cannot be verified at runtime"; fi
  if [[ -x /usr/lib/nap/configure-services ]]; then
    info "PASS: NAP userspace helper installed"
    systemctl is-enabled nap-state.service >/dev/null 2>&1 && info "PASS: NAP state restore service enabled" || info "WARN: NAP state restore service not enabled"
    systemctl is-enabled nap-state-save.timer >/dev/null 2>&1 && info "PASS: NAP periodic save timer enabled" || info "WARN: NAP periodic save timer not enabled"
  else info "INFO: NAP userspace helper is not installed yet"; fi
  for candidate in /efi/EFI/SteamOS/grub.cfg /efi/EFI/steamos/grub.cfg /boot/efi/EFI/SteamOS/grub.cfg /boot/efi/EFI/steamos/grub.cfg /boot/grub/grub.cfg; do
    if run_privileged test -s "$candidate"; then grub=$candidate; break; fi
  done
  if [[ -z "$grub" ]]; then info "FAIL: no standard GRUB config"; failures=$((failures+1))
  elif run_privileged grep -Fq '/boot/vmlinuz-linux-neptune-73' "$grub" && run_privileged grep -Fq '/boot/initramfs-linux-neptune-73.img' "$grub"; then info "PASS: GRUB references 7.3 kernel and initramfs"
  else info "FAIL: GRUB references missing 7.3 boot files"; failures=$((failures+1)); fi
  df -h /boot / 2>/dev/null || true
  if (( failures )); then info "Diagnostic result: $failures failure(s); no changes made"; return 1; fi
  info "Diagnostic result: checks passed; review WARN lines. No changes made"
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
