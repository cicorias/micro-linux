#!/usr/bin/env bash
set -euo pipefail

# 02-seed.sh: Prepare Subiquity autoinstall seed with per-build password
# Outputs:
#  - autoinstall/user-data (with hashed password)
#  - autoinstall/meta-data
#  - artifacts/password.txt (plaintext, for local testing only)

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

mkdir -p autoinstall artifacts autoinstall/netplan

# Generate per-build password
PW=$(openssl rand -base64 18)
HASH=$(mkpasswd -m sha-512 "$PW" 2>/dev/null || openssl passwd -6 "$PW")

# Emit plaintext for testers (never commit)
printf "%s\n" "$PW" > artifacts/password.txt
chmod 600 artifacts/password.txt

echo "Per-build password written to artifacts/password.txt"

# Write meta-data (minimal)
cat > autoinstall/meta-data <<'EOF'
instance-id: micro-linux
local-hostname: micro
EOF

# Networking toggle (DHCP by default). For static, set NET_MODE=static and export IFACE/ADDR/PREFIX/GATEWAY
NET_MODE=${NET_MODE:-dhcp}
IFACE=${IFACE:-eth0}
ADDR=${ADDR:-192.168.1.10}
PREFIX=${PREFIX:-24}
GATEWAY=${GATEWAY:-192.168.1.1}

# Prepare netplan file
if [[ "$NET_MODE" == "static" ]]; then
  sed -e "s#\${IFACE}#$IFACE#g" \
      -e "s#\${ADDR}#$ADDR#g" \
      -e "s#\${PREFIX}#$PREFIX#g" \
      -e "s#\${GATEWAY}#$GATEWAY#g" \
      autoinstall/netplan/01-static.template.yaml > autoinstall/netplan/01-netcfg.yaml
else
  cp autoinstall/netplan/01-dhcp.yaml autoinstall/netplan/01-netcfg.yaml
fi

# Write user-data with A/B partitioning, GRUB dual entries, boot-success unit, and netplan
# Note: curtin storage is illustrative; sizes should be tuned for your environment.
# TODO: netplan configuration (networking) — decide DHCP/static and add accordingly.
# TODO: whether to keep cloud-init in target image (see README guidance).

cat > autoinstall/user-data <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: micro
    username: ubuntu
    password: $HASH
  ssh:
    install-server: true
    allow-pw: true
  storage:
    version: 1
    config:
      - id: disk0
        type: disk
        ptable: gpt
        wipe: superblock-recursive
        grub_device: true
      - id: bios_grub
        type: partition
        device: disk0
        size: 1M
        flag: bios_grub
        name: bios_grub
      - id: esp
        type: partition
        device: disk0
        size: 512M
        flag: boot
        name: esp
      - id: rootA
        type: partition
        device: disk0
        size: 8G
        name: rootA
      - id: rootB
        type: partition
        device: disk0
        size: 8G
        name: rootB
      - id: data
        type: partition
        device: disk0
        size: -1
        name: data
      - id: fs_esp
        type: format
        fstype: fat32
        volume: esp
      - id: fs_rootA
        type: format
        fstype: ext4
        volume: rootA
      - id: fs_rootB
        type: format
        fstype: ext4
        volume: rootB
      - id: fs_data
        type: format
        fstype: ext4
        volume: data
      - id: mnt_esp
        type: mount
        path: /boot/efi
        device: fs_esp
      - id: mnt_root
        type: mount
        path: /
        device: fs_rootA
  late-commands:
  - |
    if [ -d /sys/firmware/efi ]; then
      curtin in-target --target=/target -- grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck || true
    else
      curtin in-target --target=/target -- grub-install --recheck || true
    fi
  - curtin in-target --target=/target -- grub-mkconfig -o /boot/grub/grub.cfg || true
  - curtin in-target --target=/target -- grub-editenv /boot/grub/grubenv create || true
  - mkdir -p /target/etc/systemd/system
  - cp /cdrom/autoinstall/boot-success.service /target/etc/systemd/system/boot-success.service
  - curtin in-target --target=/target -- systemctl enable boot-success.service || true
  - mkdir -p /target/etc/netplan
  - cp /cdrom/autoinstall/netplan/01-netcfg.yaml /target/etc/netplan/01-netcfg.yaml
  - curtin in-target --target=/target -- update-grub || true
  - curtin in-target --target=/target -- systemctl enable ssh || true
EOF

echo "Autoinstall seed written to autoinstall/user-data and autoinstall/meta-data"

# Optional: validate syntax with cloud-init schema
if command -v cloud-init >/dev/null 2>&1; then
  echo "Validating autoinstall user-data with cloud-init schema..."
  if cloud-init schema --config-file autoinstall/user-data >/dev/null; then
    echo "cloud-init schema validation: OK"
  else
    echo "cloud-init schema validation: FAILED" >&2
  fi
else
  echo "cloud-init not installed on host; skipping schema validation" >&2
fi
