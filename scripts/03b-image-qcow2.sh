#!/usr/bin/env bash
set -euo pipefail

# 03b-image-qcow2.sh: Build a bootable qcow2 disk image with GRUB (BIOS/UEFI)
# Outputs: artifacts/micro-linux-ubuntu-24.04.qcow2

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

mkdir -p artifacts

IMG_OUT="artifacts/micro-linux-ubuntu-24.04.qcow2"
SIZE_GB=${SIZE_GB:-8}

echo "Creating qcow2 $IMG_OUT (${SIZE_GB}G)"
qemu-img create -f qcow2 "$IMG_OUT" ${SIZE_GB}G

pick_nbd() {
  modprobe nbd max_part=16 || true
  for i in {0..15}; do
    local dev="/dev/nbd${i}"
    [[ -e "$dev" ]] || continue
    # If pid file exists and is non-empty, it's in use
    local pidf="/sys/class/block/nbd${i}/pid"
    if [[ ! -s "$pidf" ]]; then
      echo "$dev"
      return 0
    fi
  done
  return 1
}

TMPNBD=$(pick_nbd) || { echo "No free /dev/nbdX devices." >&2; exit 1; }
# Best-effort disconnect in case it's half-open
qemu-nbd --disconnect "$TMPNBD" >/dev/null 2>&1 || true
qemu-nbd --connect="$TMPNBD" "$IMG_OUT"
trap 'qemu-nbd --disconnect "$TMPNBD" || true' EXIT
# Wait a moment for the device to be ready
udevadm settle || sleep 0.5

echo "Partitioning (GPT: ESP/rootA/rootB/data) on $TMPNBD"
parted -s "$TMPNBD" mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB set 1 esp on \
  mkpart rootA ext4 513MiB 4097MiB \
  mkpart rootB ext4 4097MiB 7681MiB \
  mkpart data ext4 7681MiB 100%
partprobe "$TMPNBD" || true
udevadm settle || sleep 0.5

ESP_PART=${TMPNBD}p1
ROOTA_PART=${TMPNBD}p2
ROOTB_PART=${TMPNBD}p3
DATA_PART=${TMPNBD}p4

echo "Formatting filesystems"
mkfs.vfat -F32 -n ESP "$ESP_PART"
mkfs.ext4 -F -L rootA "$ROOTA_PART"
mkfs.ext4 -F -L rootB "$ROOTB_PART"
mkfs.ext4 -F -L data "$DATA_PART"

MNT="/mnt/ml"
mkdir -p "$MNT"
mount "$ROOTA_PART" "$MNT"
mkdir -p "$MNT/boot/efi"
mount "$ESP_PART" "$MNT/boot/efi"

echo "Installing rootfs into rootA"
rsync -aHAX artifacts/rootfs/ "$MNT/"

echo "Configuring fstab"
cat > "$MNT/etc/fstab" <<EOF
# /etc/fstab
LABEL=rootA  /          ext4  defaults  0 1
LABEL=data   /data      ext4  defaults  0 2
LABEL=ESP    /boot/efi  vfat  umask=0077  0 1
EOF

echo "Installing GRUB (UEFI only)"
mount --bind /dev "$MNT/dev"
mount --bind /proc "$MNT/proc"
mount --bind /sys "$MNT/sys"

# Ensure networking for apt inside chroot
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf" || true

# Install minimal GRUB for UEFI in the target
chroot "$MNT" bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update'
chroot "$MNT" bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends grub-efi-amd64 grub-efi-amd64-bin grub-common grub2-common shim-signed'

# Install GRUB to the ESP and add a removable-media fallback
chroot "$MNT" bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck"
chroot "$MNT" bash -c 'mkdir -p /boot/efi/EFI/BOOT; if [ -f /boot/efi/EFI/ubuntu/shimx64.efi ]; then cp -f /boot/efi/EFI/ubuntu/shimx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI; elif [ -f /boot/efi/EFI/ubuntu/grubx64.efi ]; then cp -f /boot/efi/EFI/ubuntu/grubx64.efi /boot/efi/EFI/BOOT/BOOTX64.EFI; fi'

echo "Finalizing GRUB configuration"
chroot "$MNT" grub-editenv /boot/grub/grubenv create || true
# Ensure initramfs and grub.cfg are present
chroot "$MNT" bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends initramfs-tools || true'
chroot "$MNT" bash -c 'update-initramfs -u -k all || true'
chroot "$MNT" update-grub || true

echo "Enable SSH and boot-success service if present"
chroot "$MNT" systemctl enable ssh || true
if [[ -f autoinstall/boot-success.service ]]; then
  install -D -m 0644 autoinstall/boot-success.service "$MNT/etc/systemd/system/boot-success.service"
  chroot "$MNT" systemctl enable boot-success.service || true
fi

echo "Cleanup mounts"
umount -R "$MNT/boot/efi" || true
umount -R "$MNT/dev" || true
umount -R "$MNT/proc" || true
umount -R "$MNT/sys" || true
umount -R "$MNT" || true

echo "qcow2 image ready at $IMG_OUT"
