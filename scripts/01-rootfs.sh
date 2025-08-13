#!/usr/bin/env bash
set -euo pipefail

# 01-rootfs.sh: Build minimal Ubuntu 24.04 rootfs with mmdebstrap (includes openssh-server)
# Output: artifacts/rootfs (directory or tarball depending on usage)

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

mkdir -p artifacts

# Minimal rootfs for installed system (qcow2 requires kernel + GRUB). Keep package set small.
# Size-focused tweaks:
#  - use linux-image-virtual (smaller driver set vs generic)
#  - disable recommends/suggests to avoid linux-firmware, extra locales, etc.
#  - restrict to main component
mmdebstrap --variant=minbase \
  --components=main \
  --aptopt='Apt::Install-Recommends "false";' \
  --aptopt='Apt::Install-Suggests "false";' \
  --dpkgopt='path-exclude=/usr/share/doc/*' \
  --dpkgopt='path-exclude=/usr/share/man/*' \
  --dpkgopt='path-exclude=/usr/share/info/*' \
  --dpkgopt='path-exclude=/usr/share/locale/*' \
  --dpkgopt='path-include=/usr/share/locale/en*' \
  --include=systemd-sysv,apt,openssh-server,linux-image-virtual,ca-certificates,netplan.io,initramfs-tools \
  noble artifacts/rootfs http://archive.ubuntu.com/ubuntu

# Optional trims (opt-in via env): remove docs/man/locales cache. Safe for most use-cases.
# Set PRUNE_DOCS=1 to enable.
if [[ "${PRUNE_DOCS:-0}" == "1" ]]; then
  ROOT=artifacts/rootfs
  rm -rf "$ROOT"/usr/share/doc/* || true
  rm -rf "$ROOT"/usr/share/man/* || true
  find "$ROOT"/usr/share/locale -mindepth 1 -maxdepth 1 ! -name 'en*' -exec rm -rf {} + 2>/dev/null || true
  rm -rf "$ROOT"/var/cache/apt/archives/* "$ROOT"/var/lib/apt/lists/* 2>/dev/null || true
fi

echo "Rootfs created at artifacts/rootfs"
