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
mmdebstrap --variant=minbase \
  --include=systemd-sysv,apt,openssh-server,linux-image-generic,ca-certificates,netplan.io \
  noble artifacts/rootfs http://archive.ubuntu.com/ubuntu

# Optional trims could be added here (locales/docs); left as TODO to keep script explicit.
# TODO: consider --components=main,universe and apt recommends policy adjustments if needed.

echo "Rootfs created at artifacts/rootfs"
