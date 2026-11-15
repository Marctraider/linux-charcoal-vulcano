#!/usr/bin/env bash
# Read-only SteamOS 3.10 boot diagnostic for Charcoal Linux 7.3.
# This script does not install/remove packages, write files, regenerate initramfs,
# change GRUB, toggle read-only mode, or reboot.

set -u

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

printf '%s\n' 'Charcoal / SteamOS 3.10 read-only boot diagnostic'
printf 'Date: '; date -Is 2>/dev/null || date
printf 'Kernel currently running: '; uname -r 2>/dev/null || printf 'unknown\n'

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  printf 'OS: %s %s (%s)\n' "${PRETTY_NAME:-unknown}" "${VERSION_ID:-unknown}" "${ID:-unknown}"
  if [[ ${ID:-} == steamos && ${VERSION_ID:-} == 3.10* ]]; then
    pass 'Host identifies as SteamOS 3.10'
  else
    fail 'Host is not identified as SteamOS 3.10'
  fi
else
  fail '/etc/os-release is missing or unreadable'
fi

if have pacman; then
  if pacman -Q linux-neptune-73 >/dev/null 2>&1; then
    pass 'Valve linux-neptune-73 package is installed'
    pacman -Q linux-neptune-73
  else
    fail 'Valve linux-neptune-73 package is not installed'
  fi
  if pacman -Q linux-charcoal-73 >/dev/null 2>&1; then
    pass 'Charcoal Linux 7.3 package is installed'
    pacman -Q linux-charcoal-73
  else
    warn 'Charcoal Linux 7.3 package is not installed'
  fi
else
  fail 'pacman command is unavailable'
fi

for path in \
  /etc/mkinitcpio.d/linux-neptune-73.preset \
  /boot/vmlinuz-linux-neptune-73 \
  /boot/initramfs-linux-neptune-73.img; do
  if [[ -s "$path" ]]; then
    pass "Present: $path"
    ls -l "$path"
  else
    fail "Missing or empty: $path"
  fi
done

pkgbase_found=0
if have pacman; then
  while IFS= read -r module_dir; do
    [[ -n "$module_dir" ]] || continue
    if [[ -r "$module_dir/pkgbase" ]]; then
      value=$(<"$module_dir/pkgbase")
      printf 'Module marker %s/pkgbase: %s\n' "$module_dir" "$value"
      if [[ $value == linux-neptune-73 ]]; then
        pass 'Installed module pkgbase matches SteamOS 3.10 boot identity'
        pkgbase_found=1
      else
        warn "Unexpected module pkgbase: $value"
      fi
    fi
  done < <(find /usr/lib/modules -mindepth 2 -maxdepth 2 -type f -name pkgbase -print 2>/dev/null)
fi
(( pkgbase_found )) || warn 'No installed module pkgbase marker matched linux-neptune-73'

grub_found=0
for grub in /efi/EFI/steamos/grub.cfg /boot/grub/grub.cfg; do
  [[ -s "$grub" ]] || continue
  grub_found=1
  printf 'GRUB config: %s\n' "$grub"
  if grep -Fq '/boot/vmlinuz-linux-neptune-73' "$grub"; then
    pass 'GRUB references /boot/vmlinuz-linux-neptune-73'
  else
    warn 'GRUB does not reference /boot/vmlinuz-linux-neptune-73'
  fi
  if grep -Fq '/boot/initramfs-linux-neptune-73.img' "$grub"; then
    pass 'GRUB references /boot/initramfs-linux-neptune-73.img'
  else
    warn 'GRUB does not reference /boot/initramfs-linux-neptune-73.img'
  fi
done
(( grub_found )) || warn 'No standard SteamOS/GRUB configuration file was found'

printf '\n%s\n' 'Filesystem space (read-only):'
df -h /boot / 2>/dev/null || true

printf '\n%s\n' 'Diagnostic complete. No system changes were made.'
