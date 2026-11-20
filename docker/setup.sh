#!/usr/bin/bash

pushd /docker
  echo "MAKEFLAGS=\"-j$(nproc --all)\"" >> makepkg.conf
  mv makepkg.conf /etc/makepkg.conf.d/charcoal.conf
  mv pacman.conf /etc/pacman.conf

  pacman-key --init
  pacman -Syu --noconfirm bc bison cpio flex gettext libelf openssl pahole perl python rsync tar xz zstd llvm clang ccache lld polly git openssh
  echo -en "y\ny\n" | pacman -Scc
popd
rm -rf /docker /usr/share/man /usr/share/info /usr/share/locale

