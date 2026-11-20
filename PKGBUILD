# Maintainer: Charcoal SteamOS kernel project

pkgbase=linux-charcoal-73
_tag=7.3.1-valve2
_ver=1
pkgver=${_tag//-/.}.cc$_ver
pkgrel=6
pkgdesc='SteamOS 3.10 Linux 7.3 kernel for Steam Deck'
url="https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-3.10/"
arch=(x86_64)
license=(GPL-2.0-only)
makedepends=(
  bc
  bison
  cpio
  flex
  gettext
  libelf
  openssl
  pahole
  perl
  python
  rsync
  tar
  xz
  zstd
  git
  openssh
  llvm
  clang
  lld
  polly
)
options=(
  !debug
  !strip
)

# Every kernel C translation unit must pass the compile-time Zen 2 guard.
_zen2_cflags="-march=znver2 -mtune=znver2 -include $startdir/zen2-compile-check.h"
_make_llvm() {
  make LLVM=1 KCFLAGS="${KCFLAGS:+$KCFLAGS }$_zen2_cflags" \
    CC=clang HOSTCC=clang HOSTCXX=clang++ "$@"
}

_verify_zen2_compiler_target() {
  local output
  if ! output=$(clang -march=znver2 -mtune=znver2 -### -x c -c /dev/null -o /dev/null 2>&1); then
    echo "ERROR: Clang cannot compile for AMD Zen 2 (znver2)" >&2
    return 1
  fi
  if [[ "$output" != *'"-target-cpu" "znver2"'* ]]; then
    echo "ERROR: Clang did not resolve -march=znver2 to target-cpu znver2" >&2
    return 1
  fi
  if ! clang -march=znver2 -mtune=znver2 -include "$startdir/zen2-compile-check.h" -fsyntax-only -x c /dev/null; then
    echo "ERROR: Zen 2 compile-time guard rejected the selected Clang target" >&2
    return 1
  fi
  echo "Verified Clang target: -march=znver2 -mtune=znver2 (AMD Zen 2)"
}

_srcname=archlinux-linux-charcoal
source=(
  valve-source.tar.gz
  vangogh_allow_higher_cpu_freq.patch
  latest-amd-pstate-epp-02-cache-order.patch
  latest-amd-pstate-epp-03-core.patch
  latest-clang-polly.patch # Linux Kbuild/Kconfig glue; Polly itself comes from LLVM
)
sha256sums=(
  'a6316acc22954d0685ac923248995246789a1f3b5ee6890d378ce2c3efa25af8' # exact Valve 7.3.1.valve2-1 source archive
  '1a6f9d691612c4a729032273199d17756dd6666d85019655bd95ea24eff59cac' # Van Gogh higher CPU frequency
  '454f353669c81b5e214e5b71327ed5735733e6bd9f5671e710520a2c3e455cb6' # AMD P-State EPP cache ordering
  '072927860ad14a09bbc08ef4f99d52d9964ed4de5800b647e3d61bab7a046dda' # AMD P-State per-core EPP boost
  'd768b825af5654ec999088d67553952d9023fe0497c0f3914a46f7aa67652ac8' # LLVM Polly port
)

export KBUILD_BUILD_HOST=archlinux
export KBUILD_BUILD_USER=${pkgbase}-znver2
export KBUILD_BUILD_TIMESTAMP="$(date -Ru${SOURCE_DATE_EPOCH:+d @$SOURCE_DATE_EPOCH})"

_validate_kernel_config() {
  local expected
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
    'CONFIG_DEBUG_KERNEL=y' \
    'CONFIG_DEBUG_INFO=y' \
    'CONFIG_DEBUG_INFO_DWARF5=y' \
    'CONFIG_DEBUG_INFO_BTF=y' \
    'CONFIG_TRACEPOINTS=y' \
    'CONFIG_FTRACE=y' \
    'CONFIG_FTRACE_SYSCALLS=y' \
    'CONFIG_FUNCTION_TRACER=y' \
    'CONFIG_DYNAMIC_FTRACE=y' \
    '# CONFIG_DEBUG_INFO_BTF_MODULES is not set' \
    '# CONFIG_DEBUG_INFO_REDUCED is not set' \
    '# CONFIG_DEBUG_INFO_SPLIT is not set' \
    '# CONFIG_STACK_TRACER is not set' \
    '# CONFIG_FPROBE is not set' \
    '# CONFIG_FUNCTION_GRAPH_TRACER is not set' \
    '# CONFIG_KPROBES is not set' \
    '# CONFIG_PROFILING is not set' \
    '# CONFIG_KASAN is not set' \
    '# CONFIG_KCSAN is not set' \
    '# CONFIG_UBSAN is not set' \
    '# CONFIG_KFENCE is not set' \
    '# CONFIG_KMSAN is not set' \
    '# CONFIG_SLUB_DEBUG is not set' \
    '# CONFIG_LOCKDEP is not set' \
    '# CONFIG_PROVE_LOCKING is not set' \
    '# CONFIG_DEBUG_ATOMIC_SLEEP is not set' \
    '# CONFIG_DEBUG_MUTEXES is not set' \
    '# CONFIG_DEBUG_SPINLOCK is not set' \
    '# CONFIG_DEBUG_LIST is not set' \
    '# CONFIG_DEBUG_OBJECTS is not set' \
    '# CONFIG_DEBUG_PAGEALLOC is not set' \
    '# CONFIG_PAGE_POISONING is not set' \
    'CONFIG_HID_STEAM=m' \
    'CONFIG_MFD_STEAMDECK=m' \
    'CONFIG_LEDS_STEAMDECK=m' \
    'CONFIG_SENSORS_STEAMDECK=m' \
    'CONFIG_LEDS_VALVE=m' \
    'CONFIG_JOYSTICK_XBOX_GIP=m'; do
    if ! grep -qxF "$expected" .config; then
      echo "ERROR: Linux 7.3 configuration requires $expected after olddefconfig" >&2
      return 1
    fi
  done
}

prepare() {
  local repo_dir="$srcdir/linux-neptune-73/archlinux-linux-neptune"
  local valve_commit="0ed55b10a784a0a0b518ecd20551659fde1d59c9"

  _verify_zen2_compiler_target

  if [[ ! -d "$repo_dir/objects" ]]; then
    echo "ERROR: Valve source archive did not extract the embedded bare Git repository" >&2
    return 1
  fi
  git --git-dir="$repo_dir" worktree add --detach "$srcdir/$_srcname" "$valve_commit"
  cd "$srcdir/$_srcname"

  echo "Setting version..."
  echo "-$pkgrel" > localversion.10-pkgrel
  echo "${pkgbase#linux}" > localversion.20-pkgname

  local src
  for src in "${source[@]}"; do
    src="${src%%::*}"
    src="${src##*/}"
    src="${src%.zst}"
    [[ $src = *.patch ]] || continue
    echo "Applying pinned patch $src..."
    if [[ $src == latest-amd-pstate-epp-03-core.patch ]]; then
      python3 "$startdir/automation/port-amd-pstate-epp-boost-73.py" "../$src" "$PWD"
    else
      git apply --check --whitespace=nowarn "../$src"
      git apply --whitespace=nowarn "../$src"
    fi
  done

  git diff --check || {
    echo "ERROR: patched source contains whitespace errors" >&2
    return 1
  }

  # Merge Valve's exact SteamOS fragments with the minimal Charcoal overlay.
  cp "$srcdir/linux-neptune-73/config.x86_64" "$srcdir/config.x86_64"
  cp "$srcdir/linux-neptune-73/config-neptune" "$srcdir/config-neptune"
  cp "$startdir/config-charcoal" "$srcdir/config-charcoal"
  cp ../config.x86_64 .config
  scripts/kconfig/merge_config.sh -m ../config.x86_64 ../config-neptune ../config-charcoal

  _make_llvm olddefconfig

  # Preserve LAVD's required function tracing after Kconfig resolves selects
  # and defaults. Keep optional higher-level tracing/debug facilities disabled.
  scripts/config --enable FUNCTION_TRACER
  scripts/config --enable DYNAMIC_FTRACE
  scripts/config --disable FUNCTION_GRAPH_TRACER
  scripts/config --disable FPROBE
  scripts/config --disable STACK_TRACER
  scripts/config --disable PROVE_LOCKING
  scripts/config --disable LOCKDEP
  scripts/config --enable CC_OPTIMIZE_FOR_PERFORMANCE
  scripts/config --disable CC_OPTIMIZE_FOR_PERFORMANCE_O3
  _make_llvm olddefconfig
  _validate_kernel_config
  _make_llvm -s kernelrelease > version
  echo "Prepared $pkgbase version $(<version) for AMD Zen 2 (znver2), O2"
}

build() {
  cd "$_srcname"
  _make_llvm all
  # Polly is provided by the LLVM toolchain; latest-clang-polly.patch only wires its
  # compiler plugin and optimization flags into Linux Kbuild/Kconfig. Full LTO is separate.
  # Build bpftool and export this kernel's BTF as the CO-RE header used
  # when building sched_ext BPF schedulers such as scx_lavd.
  _make_llvm -C tools/bpf/bpftool
  tools/bpf/bpftool/bpftool btf dump file vmlinux format c > tools/bpf/bpftool/vmlinux.h
  test -s tools/bpf/bpftool/vmlinux.h
}

_package() {
  pkgdesc="The $pkgdesc kernel and modules"
  depends=(
    coreutils
    initramfs
    kmod
    python
    util-linux
    systemd
  )
  optdepends=(
    'wireless-regdb: to set the correct wireless channels of your country'
    'linux-firmware: firmware images needed for some devices'
  )
  provides=(
    KSMBD-MODULE
    VIRTUALBOX-GUEST-MODULES
    WIREGUARD-MODULE
  )
  replaces=(
    virtualbox-guest-modules-arch
    wireguard-arch
  )
  conflicts=(
    linux-charcoal-72
  )

  cd "$_srcname"
  local modulesdir="$pkgdir/usr/lib/modules/$(<version)"

  echo "Installing boot image..."
  install -Dm644 "$(_make_llvm -s image_name)" "$modulesdir/vmlinuz"
  echo "linux-neptune-73" | install -Dm644 /dev/stdin "$modulesdir/pkgbase"

  echo "Installing modules..."
  ZSTD_CLEVEL=19 _make_llvm INSTALL_MOD_PATH="$pkgdir/usr" INSTALL_MOD_STRIP=1 \
    DEPMOD=/doesnt/exist modules_install

  rm "$modulesdir"/build

  echo "Installing Charcoal status utility..."
  install -Dm755 "$startdir/charcoal-status" "$pkgdir/usr/bin/charcoal-status"
}

_package-headers() {
  pkgdesc="Headers and scripts for building modules for the $pkgdesc kernel"
  depends=(
    pahole
    llvm
    clang
    lld
    polly
  )

  cd "$_srcname"
  local builddir="$pkgdir/usr/lib/modules/$(<version)/build"

  echo "Installing build files..."
  install -Dt "$builddir" -m644 .config Makefile Module.symvers System.map \
    localversion.* version vmlinux tools/bpf/bpftool/vmlinux.h
  install -Dt "$builddir/kernel" -m644 kernel/Makefile
  install -Dt "$builddir/arch/x86" -m644 arch/x86/Makefile
  cp -t "$builddir" -a scripts
  ln -srt "$builddir" "$builddir/scripts/gdb/vmlinux-gdb.py"

  # Required when STACK_VALIDATION is enabled.
  install -Dt "$builddir/tools/objtool" tools/objtool/objtool
  # Required when DEBUG_INFO_BTF_MODULES is enabled in other configs.
  if [[ -x tools/bpf/resolve_btfids/resolve_btfids ]]; then
    install -Dt "$builddir/tools/bpf/resolve_btfids" tools/bpf/resolve_btfids/resolve_btfids
  fi

  echo "Installing headers..."
  cp -t "$builddir" -a include
  cp -t "$builddir/arch/x86" -a arch/x86/include
  install -Dt "$builddir/arch/x86/kernel" -m644 arch/x86/kernel/asm-offsets.s

  install -Dt "$builddir/drivers/md" -m644 drivers/md/*.h
  install -Dt "$builddir/net/mac80211" -m644 net/mac80211/*.h
  install -Dt "$builddir/drivers/media/i2c" -m644 drivers/media/i2c/msp3400-driver.h
  install -Dt "$builddir/drivers/media/usb/dvb-usb" -m644 drivers/media/usb/dvb-usb/*.h
  install -Dt "$builddir/drivers/media/dvb-frontends" -m644 drivers/media/dvb-frontends/*.h
  install -Dt "$builddir/drivers/media/tuners" -m644 drivers/media/tuners/*.h
  install -Dt "$builddir/drivers/iio/common/hid-sensors" -m644 drivers/iio/common/hid-sensors/*.h

  echo "Installing Kconfig files..."
  find . -name 'Kconfig*' -exec install -Dm644 {} "$builddir/{}" \;

  echo "Removing unneeded architectures..."
  local arch
  for arch in "$builddir"/arch/*/; do
    [[ $arch = */x86/ ]] && continue
    rm -r "$arch"
  done

  echo "Removing documentation..."
  rm -r "$builddir/Documentation"

  echo "Removing broken symlinks..."
  find -L "$builddir" -type l -delete

  echo "Removing loose objects..."
  find "$builddir" -type f -name '*.o' -delete

  echo "Stripping build tools..."
  local file
  while read -rd '' file; do
    case "$(file -Sib "$file")" in
      application/x-sharedlib\;*)      strip -v $STRIP_SHARED "$file" ;;
      application/x-archive\;*)        strip -v $STRIP_STATIC "$file" ;;
      application/x-executable\;*)     strip -v $STRIP_BINARIES "$file" ;;
      application/x-pie-executable\;*) strip -v $STRIP_SHARED "$file" ;;
    esac
  done < <(find "$builddir" -type f -perm -u+x ! -name vmlinux -print0)

  echo "Stripping vmlinux..."
  strip -v $STRIP_STATIC "$builddir/vmlinux"

  mkdir -p "$pkgdir/usr/src"
  ln -sr "$builddir" "$pkgdir/usr/src/$pkgbase"
}

pkgname=("$pkgbase" "$pkgbase-headers")
package_linux-charcoal-73() {
  install=linux-charcoal-73.install
  _package
}

package_linux-charcoal-73-headers() {
  install=
  _package-headers
}

# vim:set ts=8 sts=2 sw=2 et:
