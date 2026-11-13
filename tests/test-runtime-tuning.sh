#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/configure-zram-ir"
zram_generator_dropin="$root/90-charcoal-zram.conf"
zram_setup_dropin="$root/90-charcoal-zram-ir.conf"
sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

fail() {
  echo "runtime tuning validation failed: $*" >&2
  exit 1
}

require_line() {
  local file="$1"
  local line="$2"
  grep -Fxq -- "$line" "$file" || fail "missing '$line' in ${file#$root/}"
}

require_value() {
  local file="$1"
  local value="$2"
  [[ "$(<"$file")" == "$value" ]] || fail "expected '$value' in $file"
}

bash -n "$root/PKGBUILD"
sh -n "$helper"

require_line "$zram_generator_dropin" "[zram0]"
require_line "$zram_generator_dropin" "compression-algorithm = lz4 zstd"
require_line "$zram_setup_dropin" "[Service]"
require_line "$zram_setup_dropin" "ExecStartPre=/usr/lib/charcoal/configure-zram-ir %I"

# SteamOS configures zram0 with zstd in its main generator configuration.
# A zram-generator *.conf.d entry has higher precedence; verify the Charcoal
# drop-in changes only the compressor and preserves Valve's size/swap policy.
python3 - "$zram_generator_dropin" <<'PY'
import configparser
import sys

base = """\
[zram0]
zram-size = ram/2
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
"""

parser = configparser.ConfigParser(interpolation=None)
parser.read_string(base)
parser.read(sys.argv[1], encoding="utf-8")

zram0 = parser["zram0"]
assert zram0["compression-algorithm"] == "lz4 zstd"
assert zram0["zram-size"] == "ram/2"
assert zram0["swap-priority"] == "100"
assert zram0["fs-type"] == "swap"
PY

require_line "$root/config-charcoal" "CONFIG_ZRAM_DEF_COMP_LZ4=y"
require_line "$root/config-charcoal" "# CONFIG_ZRAM_DEF_COMP_ZSTD is not set"
require_line "$root/config-charcoal" 'CONFIG_ZRAM_DEF_COMP="lz4"'
require_line "$root/config-charcoal" "CONFIG_CMDLINE_BOOL=y"
require_line "$root/config-charcoal" 'CONFIG_CMDLINE="amd_pstate.epp_boost=1"'
require_line "$root/config-charcoal" "# CONFIG_CMDLINE_OVERRIDE is not set"
require_line "$root/config" "CONFIG_ZRAM_BACKEND_LZ4=y"
require_line "$root/config" "CONFIG_ZRAM_BACKEND_ZSTD=y"
require_line "$root/config" "CONFIG_ZRAM_BACKEND_LZO=y"
require_line "$root/config" "CONFIG_ZRAM_MULTI_COMP=y"
grep -Fq 'latest-amd-pstate-epp-boost-03-core.patch' "$root/PKGBUILD" || fail "AMD P-State EPP boost patch is missing from the dynamic patch stack"
grep -Fq 'zram_recomp_immediate' "$root/0001-linux7.2-zram-ir-1.2.patch" || fail "ZRAM-IR sysctl patch is missing"
grep -Fq 'sysctl_zram_recomp_immediate = 1' "$root/0001-linux7.2-zram-ir-1.2.patch" || fail "ZRAM-IR does not try the ZSTD recompressor"
grep -Fq 'params->level = -1' "$root/0001-linux7.2-zram-ir-1.2.patch" || fail "kernel ZSTD level is not fixed to --fast=1"
grep -Eq '^-.*if \(params->level == ZCOMP_PARAM_NOT_SET\)' "$root/0001-linux7.2-zram-ir-1.2.patch" \
  || fail "kernel ZSTD level still permits an algorithm_params override"
grep -Fq '/usr/lib/charcoal/configure-zram-ir' "$root/60-charcoal-zram-ir.rules" || fail "udev helper path is missing"
grep -Fq 'ACTION=="add"' "$root/60-charcoal-zram-ir.rules" || fail "udev add rule is missing"
grep -Fq 'ACTION=="change"' "$root/60-charcoal-zram-ir.rules" || fail "udev change rule is missing"
grep -Fq 'algo=zstd priority=1' "$helper" || fail "zstd priority-1 setup is missing"
if grep -Fq 'algorithm_params' "$helper"; then
  fail "userspace algorithm_params must not control the ZSTD level"
fi
grep -Fq 'lz4 > "$sys/comp_algorithm"' "$helper" || fail "lz4 primary setup is missing"

for package_path in \
  'usr/lib/udev/rules.d/60-charcoal-zram-ir.rules' \
  'usr/lib/charcoal/configure-zram-ir' \
  'usr/lib/systemd/zram-generator.conf.d/90-charcoal-zram.conf' \
  'usr/lib/systemd/system/systemd-zram-setup@.service.d/90-charcoal-zram-ir.conf'; do
  grep -Fq "\$pkgdir/$package_path" "$root/PKGBUILD" || fail "package install missing: $package_path"
done

# Local sources are pinned by the checked-out Git commit. Keep a real SHA-256
# entry for every local source (never SKIP), but defer byte-for-byte comparison
# until the build stage regenerates checksums from the final source set and
# executes makepkg --verifysource. This avoids stale local SHA failures after
# legitimate branch changes such as config-neptune updates.
source "$root/PKGBUILD"
for index in "${!source[@]}"; do
  candidate="${source[$index]%%::*}"
  [[ -f "$root/$candidate" ]] || continue
  checksum="${sha256sums[$index]}"
  [[ "$checksum" != "SKIP" ]] || fail "local source has SKIP checksum: $candidate"
  [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || fail "invalid SHA-256 entry: $candidate"
done

# Exercise the exact helper against regular files standing in for sysfs/procfs.
mkdir -p "$sandbox/sys/block/zram0" "$sandbox/proc/sys/vm" "$sandbox/bin"
printf '0\n' > "$sandbox/sys/block/zram0/initstate"
printf 'zstd lz4\n' > "$sandbox/sys/block/zram0/comp_algorithm"
printf 'zstd lz4\n' > "$sandbox/sys/block/zram0/recomp_algorithm"
printf '0\n' > "$sandbox/proc/sys/vm/zram_recomp_immediate"
printf '#!/bin/sh\nexit 0\n' > "$sandbox/bin/logger"
chmod +x "$sandbox/bin/logger"

PATH="$sandbox/bin:$PATH" \
  CHARCOAL_SYS_ROOT="$sandbox/sys" \
  CHARCOAL_PROC_SYS_ROOT="$sandbox/proc/sys" \
  sh "$helper" zram0
require_value "$sandbox/proc/sys/vm/zram_recomp_immediate" "1"
require_value "$sandbox/sys/block/zram0/comp_algorithm" "lz4"
require_value "$sandbox/sys/block/zram0/recomp_algorithm" "algo=zstd priority=1"

# Older kernels may lack algorithm_params. The helper must keep the established
# LZ4 -> ZSTD setup working instead of failing or resetting ZRAM.
mkdir -p "$sandbox/sys/block/zram1"
printf '0\n' > "$sandbox/sys/block/zram1/initstate"
printf 'zstd lz4\n' > "$sandbox/sys/block/zram1/comp_algorithm"
printf 'zstd lz4\n' > "$sandbox/sys/block/zram1/recomp_algorithm"
PATH="$sandbox/bin:$PATH" \
  CHARCOAL_SYS_ROOT="$sandbox/sys" \
  CHARCOAL_PROC_SYS_ROOT="$sandbox/proc/sys" \
  sh "$helper" zram1
require_value "$sandbox/sys/block/zram1/comp_algorithm" "lz4"
require_value "$sandbox/sys/block/zram1/recomp_algorithm" "algo=zstd priority=1"

# A later udev change event must reassert the sysctl but leave active swap alone.
printf '1\n' > "$sandbox/sys/block/zram0/initstate"
printf 'already-active-primary\n' > "$sandbox/sys/block/zram0/comp_algorithm"
printf 'already-active-secondary\n' > "$sandbox/sys/block/zram0/recomp_algorithm"
printf '0\n' > "$sandbox/proc/sys/vm/zram_recomp_immediate"
PATH="$sandbox/bin:$PATH" \
  CHARCOAL_SYS_ROOT="$sandbox/sys" \
  CHARCOAL_PROC_SYS_ROOT="$sandbox/proc/sys" \
  sh "$helper" zram0
require_value "$sandbox/proc/sys/vm/zram_recomp_immediate" "1"
require_value "$sandbox/sys/block/zram0/comp_algorithm" "already-active-primary"
require_value "$sandbox/sys/block/zram0/recomp_algorithm" "already-active-secondary"

# Rebuild the makepkg archive from current NAP tools sources before the
# strict byte-for-byte comparison; keep the integrity validation enabled.
python3 "$root/nap-tools/make-archive.py"
python3 "$root/tests/test_nap_tools.py"
python3 "$root/tests/test_nap_tools_refresh.py"
python3 "$root/tests/test_kernel_config_validation.py"

echo "runtime tuning validation passed"
