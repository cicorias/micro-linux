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

echo "Configuring serial console and default user"
# Force console logs to serial for headless testing
cat > "$MNT/etc/default/grub" <<'EOF'
GRUB_DEFAULT=rootA
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=`lsb_release -i -s 2>/dev/null || echo Debian`
GRUB_CMDLINE_LINUX="console=ttyS0,115200 console=tty0 rootdelay=3"
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
EOF

# Create a default user 'ubuntu' with a password (use artifacts/password.txt if present)
PW_FILE="artifacts/password.txt"
if [[ -f "$PW_FILE" ]]; then
  PW=$(cat "$PW_FILE")
else
  PW=$(openssl rand -base64 18)
  echo "$PW" > "$PW_FILE"
  chmod 600 "$PW_FILE"
fi
HASH=$(mkpasswd -m sha-512 "$PW" 2>/dev/null || openssl passwd -6 "$PW")
chroot "$MNT" bash -lc 'id -u ubuntu >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo ubuntu'
echo "ubuntu:$HASH" | chroot "$MNT" chpasswd -e

echo "Writing a simple DHCP netplan"
mkdir -p "$MNT/etc/netplan"
cat > "$MNT/etc/netplan/01-netcfg.yaml" <<'YAML'
network:
  version: 2
  renderer: networkd
  ethernets:
    all:
      match:
        name: "*"
      dhcp4: true
      optional: true
YAML

# Ensure DNS works inside chroot for apt operations
cat > "$MNT/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF

# (initramfs driver injection happens after initramfs-tools is installed)

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
mount --bind /dev/pts "$MNT/dev/pts" || true

# Ensure networking for apt inside chroot (resolv.conf already written)

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
mkdir -p "$MNT/etc/initramfs-tools" && cat > "$MNT/etc/initramfs-tools/modules" <<'EOF'
nvme
virtio
virtio_pci
virtio_blk
virtio_scsi
EOF
# Provide A/B menu entries that use labels so device names (nvme/vda/sda) don’t matter
cat > "$MNT/etc/grub.d/06_abroot" <<'GRUBD'
#!/bin/sh
set -e
cat <<'EOF'
menuentry 'Ubuntu (rootA)' --id rootA {
  search --no-floppy --set=root --label rootA
  linux /boot/vmlinuz root=LABEL=rootA ro console=ttyS0,115200 console=tty0 rootdelay=3
  initrd /boot/initrd.img
}
menuentry 'Ubuntu (rootB)' --id rootB {
  search --no-floppy --set=root --label rootB
  linux /boot/vmlinuz root=LABEL=rootB ro console=ttyS0,115200 console=tty0 rootdelay=3
  initrd /boot/initrd.img
}
EOF
GRUBD
chmod +x "$MNT/etc/grub.d/06_abroot"
KVER=$(chroot "$MNT" bash -lc 'ls -1 /lib/modules | head -n1')
chroot "$MNT" bash -c "update-initramfs -c -k ${KVER} || true"
chroot "$MNT" update-grub || true

echo "Enable SSH and boot-success service if present"
chroot "$MNT" systemctl enable ssh || true
chroot "$MNT" systemctl enable systemd-networkd systemd-resolved serial-getty@ttyS0.service || true
if [[ -f autoinstall/boot-success.service ]]; then
  install -D -m 0644 autoinstall/boot-success.service "$MNT/etc/systemd/system/boot-success.service"
  chroot "$MNT" systemctl enable boot-success.service || true
fi

echo "Cleanup mounts"
umount -R "$MNT/boot/efi" || true
umount -R "$MNT/dev/pts" || true
umount -R "$MNT/dev" || true
umount -R "$MNT/proc" || true
umount -R "$MNT/sys" || true
umount -R "$MNT" || true

echo "qcow2 image ready at $IMG_OUT"
