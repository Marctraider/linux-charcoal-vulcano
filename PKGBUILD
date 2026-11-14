# Maintainer: Thomas Rohloff <v10lator@myway.de>
# Maintainer: John Schoenick <johns@valvesoftware.com>
# Maintainer: Jan Alexander Steffens (heftig) <heftig@archlinux.org>

pkgbase=linux-charcoal-73
_tag=7.3.1-valve2
_ver=1
pkgver=${_tag//-/.}.cc$_ver
pkgrel=1
pkgdesc='Linux'
url="https://steamdeck-packages.steamos.cloud/archlinux-mirror/sources/jupiter-3.10/"
arch=(x86_64)
license=(GPL-2.0-only)
makedepends=(
  bc
  cpio
  gettext
  libelf
  pahole
  perl
  python
  tar
  xz

  # htmldocs
  # Jupiter: documentation dependencies, disabled for now
  #graphviz
  #imagemagick
  #python-sphinx
  #python-yaml
  #texlive-latexextra

  # Jupiter: we're using git+ssh for the source
  git
  openssh

  # Charcoal: We build on LLVM
  llvm
  clang
  ccache
  lld
)
options=(
  !debug
  !strip
)

# Charcoal: use ccache when available without making it mandatory for local builds.
_ccache_prefix=
if command -v ccache >/dev/null 2>&1; then
  _ccache_prefix='ccache '
fi

_make_llvm() {
  make LLVM=1 \
    CC="${_ccache_prefix}clang" \
    HOSTCC="${_ccache_prefix}clang" \
    HOSTCXX="${_ccache_prefix}clang++" \
    "$@"
}
_srcname=archlinux-linux-charcoal
source=(
  valve-source.tar.gz
  65-adios.rules
  60-charcoal-zram-ir.rules
  configure-zram-ir
  90-charcoal-zram.conf
  90-charcoal-zram-ir.conf
  vangogh_allow_higher_cpu_freq.patch
  latest-lru_cast.patch
  latest-zram-ir.patch
  latest-amd-pstate-epp-02-cache-order.patch
  latest-amd-pstate-epp-03-core.patch
  latest-o3.patch
  latest-clang-polly.patch
  latest-bore.patch
  latest-poc-selector.patch
  latest-adios.patch
  latest-adios-default.patch
  latest-zen-01.patch
  latest-zen-02.patch
  zstd-crypto-default-level-1.patch
)
sha256sums=(
  'a6316acc22954d0685ac923248995246789a1f3b5ee6890d378ce2c3efa25af8' # Valve linux-neptune-73 7.3.1.valve2-1 source archive
  '52cbbf41450806d766260bc4f1ea055f6f9fdd55d37ad831840b16d505beb0cc'
  '35fc7647671b1ab412804143a0585dde8d9880097c06feb520f90680780ac5e5'
  '3e200a7ad9661f59be2dfd442fd993fd130da8a6f5df7d8b4ec40d86351b1dcd'
  'b59543c9aac43412e8b90b050380f482214ab33c4703d621ff0ea91ea39c6761'
  '07068c432fd7e80689f44a28346f1909de9ee77aa3e72dfaa6a4ea89d9921afd'
  '1a6f9d691612c4a729032273199d17756dd6666d85019655bd95ea24eff59cac'
  'f13ac591211d3af128f55f91658a98173472e5866d0cfcf7c730bd887cbf8271'
  '1620f45f0fbab1173c8693a2afc0ada37920c78fdde2d0cbff6afe28545128f4'
  'a8c4883edad965455c4d8affe6137ce34ff11563d42387ce0e83b1e7c3bed118'
  'd7e00188cb09ad3e6cf980b5e77d1418455c62c6070aa838f532bbad731f265d'
  '492aafbd940b18b817e4b7957805b9874f488cc1463fee588dd8dacd18c86677'
  'ecb48f8b4a122180e815beff3f64fd3077fb8bfb57ff2c554c1e8e31388eb8e9'
  '59349771e5cde001b5456b29b9d302f5dca9cdbe60beb43d1161a85b21c1a82d'
  '091a51229f796efbf2b22215d89f4502af1992ee912198f46d138aacb82f234e'
  '5cfab7f86fe855a6b0ed5b10cb64437ab8541e80eb430945d48f94531f82cb6a'
  '5ef2f14326a5fab8980d1ebb6734ece576f930c173b4980eb026513aa3b1b9d0'
  'bc647f73ec860a0fe7d074c2377588816a616dc2a651b30d7b9cd168863a17c6'
  '5059762e54c8dbe4262d48eafb8d486a54244eec71da5d7b61fc0f5f1c5c2ea7'
  '8c35a18407440f543518e383a96f8098438c3cbe4ea034241fb9a7fe8f7be129'
)
export KBUILD_BUILD_HOST=archlinux
export KBUILD_BUILD_USER=$pkgbase
export KBUILD_BUILD_TIMESTAMP="$(date -Ru${SOURCE_DATE_EPOCH:+d @$SOURCE_DATE_EPOCH})"

_validate_kernel_config() {
  local expected
  for expected in \
    'CONFIG_CPU_MITIGATIONS=n' \
    'CONFIG_GENERIC_CPU=n' \
    'CONFIG_MZEN2=y' \
    'CONFIG_X86_AMD_PSTATE=y' \
    'CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3' \
    'CONFIG_CMDLINE_BOOL=y' \
    'CONFIG_CMDLINE="amd_pstate.epp_boost=1"' \
    'CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3=y' \
    'CONFIG_LTO_CLANG_FULL=y' \
    'CONFIG_POLLY_CLANG=y' \
    'CONFIG_ZEN_INTERACTIVE=y' \
    'CONFIG_LRU_CAST=y' \
    'CONFIG_SCHED_BORE=y' \
    'CONFIG_SCHED_POC_SELECTOR=y' \
    'CONFIG_ZSWAP=y' \
    'CONFIG_ZSWAP_DEFAULT_ON=y' \
    'CONFIG_ZSWAP_SHRINKER_DEFAULT_ON=y' \
    'CONFIG_ZSWAP_COMPRESSOR_DEFAULT_ZSTD=y' \
    'CONFIG_ZSWAP_COMPRESSOR_DEFAULT="zstd"' \
    'CONFIG_ZSMALLOC=y' \
    'CONFIG_ZRAM=m' \
    'CONFIG_ZRAM_DEF_COMP_LZ4=y' \
    'CONFIG_ZRAM_MULTI_COMP=y' \
    'CONFIG_ZRAM_DEF_COMP="lz4"' \
    'CONFIG_CRYPTO_LZ4=y' \
    'CONFIG_BTRFS_FS=y' \
    'CONFIG_HID_STEAM=m' \
    'CONFIG_MFD_STEAMDECK=m' \
    'CONFIG_LEDS_STEAMDECK=m' \
    'CONFIG_SENSORS_STEAMDECK=m' \
    'CONFIG_LEDS_VALVE=m' \
    'CONFIG_JOYSTICK_XBOX_GIP=m' \
    'CONFIG_NTSYNC=y' \
    'CONFIG_IO_DELAY_NONE=y'; do
    if ! grep -qxF "$expected" .config; then
      echo "ERROR: Linux 7.3 configuration requires $expected after olddefconfig" >&2
      return 1
    fi
  done
}
prepare() {
  local repo_dir="$srcdir/linux-neptune-73/archlinux-linux-neptune"
  local valve_commit="0ed55b10a784a0a0b518ecd20551659fde1d59c9"

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
    echo "Applying or porting patch $src..."
    case "$src" in
      latest-amd-pstate-epp-03-core.patch)
        python3 "$startdir/automation/port-amd-pstate-epp-boost-73.py" "../$src" "$PWD"
        ;;
      latest-zen-02.patch)
        python3 "$startdir/automation/port-zen-cpufreq-7.3.py" "../$src" drivers/cpufreq/Kconfig.x86
        ;;
      *)
        git apply --check --whitespace=nowarn "../$src"
        git apply --whitespace=nowarn "../$src"
        ;;
    esac
  done

  python3 "$startdir/automation/port-vangogh-power-7.3.py" \
    drivers/gpu/drm/amd/pm/swsmu/smu11/vangogh_ppt.c
  python3 "$startdir/automation/configure-zen-interactive.py" "$PWD"
  python3 "$startdir/automation/fix-gud-tv-mode-fortify.py" \
    drivers/gpu/drm/gud/gud_connector.c
  git diff --check -- drivers/cpufreq/Kconfig.x86 \

  # Verify the ZSTD Crypto API default remains at level 1.
  grep -Eq '^#define[[:space:]]+ZSTD_DEF_LEVEL[[:space:]]+1([[:space:]]|$)' crypto/zstd.c
  sha256sum crypto/zstd.c | tee "$startdir/logs/zstd-crypto-source.sha256"

  # Merge the exact Valve 7.3 base fragments with the Charcoal overlay.
  cp "$srcdir/linux-neptune-73/config.x86_64" "$srcdir/config.x86_64"
  cp "$srcdir/linux-neptune-73/config-neptune" "$srcdir/config-neptune"
  cp "$startdir/config-charcoal" "$srcdir/config-charcoal"
  cp ../config.x86_64 .config
  scripts/kconfig/merge_config.sh -m ../config.x86_64 ../config-neptune ../config-charcoal
  _make_llvm olddefconfig
  _validate_kernel_config
  diff -u ../config.x86_64 .config || :
  _make_llvm -s kernelrelease > version
  echo "Prepared $pkgbase version $(<version)"
}
build() {
  cd $_srcname
  _make_llvm all
  _make_llvm -C tools/bpf/bpftool vmlinux.h feature-clang-bpf-co-re=1
#  make htmldocs # Jupiter: Don't build the docs

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

  cd $_srcname
  local modulesdir="$pkgdir/usr/lib/modules/$(<version)"

  echo "Installing boot image..."
  # systemd expects to find the kernel here to allow hibernation
  # https://github.com/systemd/systemd/commit/edda44605f06a41fb86b7ab8128dcf99161d2344
  install -Dm644 "$(_make_llvm -s image_name)" "$modulesdir/vmlinuz"

  # Used by mkinitcpio to name the kernel
  echo "$pkgbase" | install -Dm644 /dev/stdin "$modulesdir/pkgbase"

  echo "Installing modules..."
  ZSTD_CLEVEL=19 _make_llvm INSTALL_MOD_PATH="$pkgdir/usr" INSTALL_MOD_STRIP=1 \
    DEPMOD=/doesnt/exist modules_install  # Suppress depmod

  # Install device-specific udev rules for ADIOS and ZRAM-IR
  install -D -m 0644 -t "$pkgdir/etc/udev/rules.d" ../65-adios.rules
  install -D -m 0644 ../60-charcoal-zram-ir.rules \
    "$pkgdir/usr/lib/udev/rules.d/60-charcoal-zram-ir.rules"
  install -D -m 0755 ../configure-zram-ir \
    "$pkgdir/usr/lib/charcoal/configure-zram-ir"
  install -D -m 0644 ../90-charcoal-zram.conf \
    "$pkgdir/usr/lib/systemd/zram-generator.conf.d/90-charcoal-zram.conf"
  install -D -m 0644 ../90-charcoal-zram-ir.conf \
    "$pkgdir/usr/lib/systemd/system/systemd-zram-setup@.service.d/90-charcoal-zram-ir.conf"

  # remove build link
  rm "$modulesdir"/build
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

  cd $_srcname
  local builddir="$pkgdir/usr/lib/modules/$(<version)/build"

  echo "Installing build files..."
  install -Dt "$builddir" -m644 .config Makefile Module.symvers System.map \
    localversion.* version vmlinux tools/bpf/bpftool/vmlinux.h
  install -Dt "$builddir/kernel" -m644 kernel/Makefile
  install -Dt "$builddir/arch/x86" -m644 arch/x86/Makefile
  cp -t "$builddir" -a scripts
  ln -srt "$builddir" "$builddir/scripts/gdb/vmlinux-gdb.py"

  # required when STACK_VALIDATION is enabled
  install -Dt "$builddir/tools/objtool" tools/objtool/objtool

  # required when DEBUG_INFO_BTF_MODULES is enabled
  install -Dt "$builddir/tools/bpf/resolve_btfids" tools/bpf/resolve_btfids/resolve_btfids

  echo "Installing headers..."
  cp -t "$builddir" -a include
  cp -t "$builddir/arch/x86" -a arch/x86/include
  install -Dt "$builddir/arch/x86/kernel" -m644 arch/x86/kernel/asm-offsets.s

  install -Dt "$builddir/drivers/md" -m644 drivers/md/*.h
  install -Dt "$builddir/net/mac80211" -m644 net/mac80211/*.h

  # https://bugs.archlinux.org/task/13146
  install -Dt "$builddir/drivers/media/i2c" -m644 drivers/media/i2c/msp3400-driver.h

  # https://bugs.archlinux.org/task/20402
  install -Dt "$builddir/drivers/media/usb/dvb-usb" -m644 drivers/media/usb/dvb-usb/*.h
  install -Dt "$builddir/drivers/media/dvb-frontends" -m644 drivers/media/dvb-frontends/*.h
  install -Dt "$builddir/drivers/media/tuners" -m644 drivers/media/tuners/*.h

  # https://bugs.archlinux.org/task/71392
  install -Dt "$builddir/drivers/iio/common/hid-sensors" -m644 drivers/iio/common/hid-sensors/*.h

  echo "Installing KConfig files..."
  find . -name 'Kconfig*' -exec install -Dm644 {} "$builddir/{}" \;

  echo "Removing unneeded architectures..."
  local arch
  for arch in "$builddir"/arch/*/; do
    [[ $arch = */x86/ ]] && continue
    echo "Removing $(basename "$arch")"
    rm -r "$arch"
  done

  echo "Removing documentation..."
  rm -r "$builddir/Documentation"

  echo "Removing broken symlinks..."
  find -L "$builddir" -type l -printf 'Removing %P\n' -delete

  echo "Removing loose objects..."
  find "$builddir" -type f -name '*.o' -printf 'Removing %P\n' -delete

  echo "Stripping build tools..."
  local file
  while read -rd '' file; do
    case "$(file -Sib "$file")" in
      application/x-sharedlib\;*)      # Libraries (.so)
        strip -v $STRIP_SHARED "$file" ;;
      application/x-archive\;*)        # Libraries (.a)
        strip -v $STRIP_STATIC "$file" ;;
      application/x-executable\;*)     # Binaries
        strip -v $STRIP_BINARIES "$file" ;;
      application/x-pie-executable\;*) # Relocatable binaries
        strip -v $STRIP_SHARED "$file" ;;
    esac
  done < <(find "$builddir" -type f -perm -u+x ! -name vmlinux -print0)

  echo "Stripping vmlinux..."
  strip -v $STRIP_STATIC "$builddir/vmlinux"

  echo "Adding symlink..."
  mkdir -p "$pkgdir/usr/src"
  ln -sr "$builddir" "$pkgdir/usr/src/$pkgbase"
}

_package-docs() {
  pkgdesc="Documentation for the $pkgdesc kernel"

  cd $_srcname
  local builddir="$pkgdir/usr/lib/modules/$(<version)/build"

  echo "Installing documentation..."
  local src dst
  while read -rd '' src; do
    dst="${src#Documentation/}"
    dst="$builddir/Documentation/${dst#output/}"
    install -Dm644 "$src" "$dst"
  done < <(find Documentation -name '.*' -prune -o ! -type d -print0)

  echo "Adding symlink..."
  mkdir -p "$pkgdir/usr/share/doc"
  ln -sr "$builddir/Documentation" "$pkgdir/usr/share/doc/$pkgbase"
}

# Jupiter: Don't package the docs
#pkgname=(
#  "$pkgbase"
#  "$pkgbase-headers"
#  "$pkgbase-docs"
#)
pkgname=("$pkgbase" "$pkgbase-headers")
for _p in "${pkgname[@]}"; do
  eval "package_$_p() {
    $(declare -f "_package${_p#$pkgbase}")
    _package${_p#$pkgbase}
  }"
done

# vim:set ts=8 sts=2 sw=2 et:



