#!/usr/bin/env bash
set -euo pipefail

# 00-setup-build-host.sh: Prepare the build box on Ubuntu 24.04 with required tools
# - Verifies OS is Ubuntu 24.04 (Noble)
# - Installs packages for mmdebstrap, ISO remaster (xorriso), qcow2 build (qemu, parted, filesystems),
#   autoinstall tooling (cloud-init, curtin, subiquity), and UEFI support (OVMF, grub-efi)

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "/etc/os-release not found; cannot verify OS" >&2
  exit 2
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script supports Ubuntu only. Detected: ${ID:-unknown}" >&2
  exit 3
fi

if [[ "${VERSION_ID:-}" != "24.04" ]]; then
  echo "Ubuntu 24.04 required. Detected: ${VERSION_ID:-unknown}" >&2
  exit 4
fi

echo "Ensuring 'universe' repository is enabled..."
apt-get update -y
apt-get install -y software-properties-common || true
add-apt-repository -y universe || true

echo "Updating apt and installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  mmdebstrap \
  qemu-system-x86 qemu-utils \
  xorriso mtools \
  grub-pc-bin grub-efi-amd64-bin grub-common \
  squashfs-tools e2fsprogs dosfstools parted \
  cloud-init \
  openssh-server \
  ovmf \
  rsync \
  whois openssl \
  sed coreutils

echo "Verifying UEFI support (OVMF firmware)"
if [[ -f /usr/share/OVMF/OVMF_CODE.fd ]]; then
  echo "OVMF present: /usr/share/OVMF/OVMF_CODE.fd"
else
  echo "WARNING: OVMF firmware not found. UEFI tests in QEMU may fail. Ensure 'ovmf' is installed." >&2
fi

echo "Enabling nbd module for qcow2 operations (max_part=16)"
modprobe nbd max_part=16 || true

echo "Build host is ready."
