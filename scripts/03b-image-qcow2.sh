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

TMPNBD="/dev/nbd0"
modprobe nbd max_part=16
qemu-nbd --connect="$TMPNBD" "$IMG_OUT"
trap 'qemu-nbd --disconnect "$TMPNBD" || true' EXIT

echo "Partitioning (GPT: ESP/rootA/rootB/data)"
parted -s "$TMPNBD" mklabel gpt \
  mkpart ESP fat32 1MiB 513MiB set 1 esp on \
  mkpart rootA ext4 513MiB 4097MiB \
  mkpart rootB ext4 4097MiB 7681MiB \
  mkpart data ext4 7681MiB 100%

ESP_PART=${TMPNBD}p1
ROOTA_PART=${TMPNBD}p2
ROOTB_PART=${TMPNBD}p3
DATA_PART=${TMPNBD}p4

echo "Formatting filesystems"
mkfs.vfat -F32 -n esp "$ESP_PART"
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
LABEL=esp    /boot/efi  vfat  umask=0077  0 1
EOF

echo "Installing GRUB (BIOS/UEFI)"
mount --bind /dev "$MNT/dev"
mount --bind /proc "$MNT/proc"
mount --bind /sys "$MNT/sys"
chroot "$MNT" bash -c "grub-install --target=i386-pc ${TMPNBD} || true"
chroot "$MNT" bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck || true"

echo "GRUB configuration and boot entries"
cat > "$MNT/etc/grub.d/40_custom" <<'GRUBEOF'
set default="0"
set timeout=5
if [ -s /boot/grub/grubenv ]; then
  load_env
fi
menuentry "Ubuntu (rootA)" {
  linux /boot/vmlinuz root=LABEL=rootA ro
  initrd /boot/initrd.img
}
menuentry "Ubuntu (rootB)" {
  linux /boot/vmlinuz root=LABEL=rootB ro
  initrd /boot/initrd.img
}
GRUBEOF

chroot "$MNT" grub-editenv /boot/grub/grubenv create || true
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
