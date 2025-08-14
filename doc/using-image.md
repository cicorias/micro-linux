# Using micro-linux on bare-metal via USB

This guide shows how to get your minimal Ubuntu 24.04 image onto bare metal using a USB stick.

- Option A — Installer USB (recommended): boots Subiquity and autoinstalls onto the internal disk.
- Option B — Direct flash: write the qcow2 image (as raw) straight onto the device’s disk.
- Option C — Boot-from-USB: make the USB itself the OS disk, then optionally clone to the internal disk.

Notes:
- Prefer UEFI boot. Disable Secure Boot if your custom GRUB/kernel aren’t signed.
- Commands below are for zsh on Linux. Replace /dev/sdX with your actual target device.

## Prerequisites

- Built artifacts:
  - ISO: created by [`scripts/03-image.sh`](../scripts/03-image.sh)
  - qcow2: created by [`scripts/03b-image-qcow2.sh`](../scripts/03b-image-qcow2.sh)
- Autoinstall seed under [`autoinstall/`](../autoinstall/) is embedded for ISO installs.
- The per-build plaintext password is written to [`artifacts/password.txt`](../artifacts/password.txt) (don’t commit).
- Identify the correct block device before writing:
  
```zsh
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
```

Double-check and unmount any partitions of the target device before dd.

---

## Option A — Installer USB (autoinstall ISO) [recommended]

Use this to run a clean, non-interactive installation to the internal disk using Subiquity.

### 1) Build the ISO

```zsh
sudo ./scripts/00-setup-build-host.sh
sudo ./scripts/01-rootfs.sh
sudo NET_MODE=dhcp ./scripts/02-seed.sh
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh
```

Relevant files:
- [`scripts/02-seed.sh`](../scripts/02-seed.sh)
- [`scripts/03-image.sh`](../scripts/03-image.sh)
- [`autoinstall/user-data`](../autoinstall/user-data)
- [`autoinstall/meta-data`](../autoinstall/meta-data)

### 2) Write the ISO to the USB

```zsh
# Find your USB device (e.g., /dev/sdX)
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT

# Unmount any mounted partitions on the USB, then write:
sudo dd if=out/micro-linux-ubuntu-24.04.iso of=/dev/sdX bs=8M status=progress oflag=direct conv=fsync
sync
```

### 3) Boot and autoinstall

- On the target device, enable UEFI USB boot; disable Secure Boot if needed.
- The installer should autostart with your seed. After completion it reboots into the installed system.
- Log in using the password printed during the build (see [`artifacts/password.txt`](../artifacts/password.txt)).

Tip: Ensure the ISO’s boot configs include the autoinstall kernel args (handled by `03-image.sh`).

---

## Option B — Directly flash the disk image to the device

Use this when you want the target disk to be an exact copy of your built image.

### 1) Convert qcow2 to raw

```zsh
qemu-img convert -p -O raw artifacts/micro-linux-ubuntu-24.04.qcow2 artifacts/micro-linux-ubuntu-24.04.raw
```

### 2) Write raw to the target disk

Attach the target disk to a Linux system (via USB/SATA dock or from a live OS) and write the image:

```zsh
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
# Replace /dev/sdX with the WHOLE target disk (not a partition like /dev/sdX1)
sudo dd if=artifacts/micro-linux-ubuntu-24.04.raw of=/dev/sdX bs=8M status=progress oflag=direct conv=fsync
sync
```

### 3) First boot and optional growth

- Boot the device with that disk; ensure UEFI is enabled.
- If the disk is larger and you want to grow a partition (example: extend partition 3, then grow its filesystem):

```zsh
sudo growpart /dev/sdX 3
sudo e2fsck -f /dev/sdX3
sudo resize2fs /dev/sdX3
```

Adjust partition numbers to match your scheme (e.g., p1=ESP, p2=rootA, p3=rootB, p4=data as documented).

---

## Option C — Boot-from-USB as the OS disk (then clone)

This is the quickest demo path; later clone to the internal disk.

### 1) Put the OS image on the USB

```zsh
qemu-img convert -p -O raw artifacts/micro-linux-ubuntu-24.04.qcow2 /tmp/micro-linux.raw
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
sudo dd if=/tmp/micro-linux.raw of=/dev/sdX bs=8M status=progress oflag=direct conv=fsync
sync
```

### 2) Boot target from the USB

Select the USB as the boot device (UEFI preferred). The system should come up running from the USB.

### 3) Clone USB → internal disk (optional)

From the running system:

```zsh
# Example: clone to internal NVMe disk (verify devices!)
sudo dd if=/dev/sdX of=/dev/nvme0n1 bs=16M status=progress oflag=direct conv=fsync
sync
```

Power off, remove the USB, set the internal disk first in boot order, and boot. Grow partitions if desired (see Option B).

---

## UEFI, BIOS, and Secure Boot

- UEFI: Supported and preferred; ensure an ESP exists and GRUB is installed.
- Secure Boot: Custom images typically aren’t signed; disable Secure Boot or enroll keys.
- Legacy BIOS: If needed, ensure BIOS GRUB bits are included in your image/ISO assembly. You can extend build scripts to support dual BIOS/UEFI.

---

## Credentials and login

- Plaintext password is written to [`artifacts/password.txt`](../artifacts/password.txt) during the seed step.
- Only the hashed password is embedded in [`autoinstall/user-data`](../autoinstall/user-data).

For production, consider SSH keys and disabling password auth.

---

## Optional helper script: write ISO/qcow2/raw safely

Drop this as [`scripts/05-write-usb.sh`](../scripts/05-write-usb.sh) to unify writing ISO/qcow2/raw to a target disk:

```bash
#!/usr/bin/env bash
# filepath: scripts/05-write-usb.sh
set -euo pipefail

usage() {
  echo "Usage: sudo $0 <iso|qcow2|raw> <image_path> <target_disk>"
  echo "Example:"
  echo "  sudo $0 iso out/micro-linux-ubuntu-24.04.iso /dev/sdX"
  echo "  sudo $0 qcow2 artifacts/micro-linux-ubuntu-24.04.qcow2 /dev/sdX"
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run as root (sudo)"; exit 1; }
[[ $# -eq 3 ]] || usage

kind="$1"
img="$2"
disk="$3"

[[ -b "$disk" ]] || { echo "Target $disk is not a block device"; exit 1; }
mountpoints=$(lsblk -no MOUNTPOINT "$disk" | grep -v "^$" || true)
if [[ -n "$mountpoints" ]]; then
  echo "Unmount partitions on $disk first:"
  lsblk -o NAME,MOUNTPOINT "$disk"
  exit 1
fi

case "$kind" in
  iso)
    [[ -f "$img" ]] || { echo "ISO not found: $img"; exit 1; }
    ;;
  qcow2)
    [[ -f "$img" ]] || { echo "qcow2 not found: $img"; exit 1; }
    echo "Converting qcow2 to raw..."
    raw="${img%.*}.raw"
    qemu-img convert -p -O raw "$img" "$raw"
    img="$raw"
    ;;
  raw)
    [[ -f "$img" ]] || { echo "RAW not found: $img"; exit 1; }
    ;;
  *)
    usage
    ;;
esac

echo "Writing $img to $disk ..."
dd if="$img" of="$disk" bs=8M status=progress oflag=direct conv=fsync
sync
echo "Done. You can now boot from $disk."
```

Make it executable:

```zsh
chmod +x scripts/05-write-usb.sh
```

---

## Troubleshooting

- USB doesn’t boot: Verify boot order, UEFI vs Legacy, and Secure Boot state.
- Autoinstall didn’t trigger: Ensure `03-image.sh` injected the autoinstall kernel args and the `autoinstall/` seed is present on the ISO.
- No network during install: Use DHCP seed (`NET_MODE=dhcp` in [`scripts/02-seed.sh`](../scripts/02-seed.sh)) or adjust [`autoinstall/netplan`](../autoinstall/netplan/).
- Need to validate `user-data`:  
  ```zsh
  cloud-init schema --config-file autoinstall/user-data
  ```

---

## See also

- Build steps and context in [`README.md`](../README.md)
- QEMU smoke tests in [`scripts/04-test-qemu.sh`](../scripts/04-test-qemu.sh)
