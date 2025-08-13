#!/usr/bin/env bash
set -euo pipefail

# 03-image.sh: Remaster a fully bootable hybrid installer ISO with embedded autoinstall (NoCloud)
# Inputs: SOURCE_ISO (path to official Ubuntu 24.04 installer ISO)
# Outputs: artifacts/micro-linux-ubuntu-24.04.iso

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

SOURCE_ISO=${SOURCE_ISO:-}
if [[ -z "${SOURCE_ISO}" ]]; then
  echo "ERROR: Set SOURCE_ISO to the path of the Ubuntu 24.04 installer ISO (e.g., ubuntu-24.04-live-server-amd64.iso)." >&2
  exit 2
fi
if [[ ! -f "$SOURCE_ISO" ]]; then
  echo "ERROR: SOURCE_ISO not found: $SOURCE_ISO" >&2
  exit 3
fi
if echo "$SOURCE_ISO" | grep -qi "desktop-"; then
  echo "ERROR: Desktop ISO detected from filename. Use the Ubuntu Server Live ISO (ubuntu-24.04.x-live-server-amd64.iso)." >&2
  exit 3
fi

for f in autoinstall/user-data autoinstall/meta-data; do
  [[ -f "$f" ]] || { echo "Missing $f. Run ./scripts/02-seed.sh first." >&2; exit 4; }
done

mkdir -p artifacts
ISO_OUT="artifacts/micro-linux-ubuntu-24.04.iso"
VOLID=${VOLID:-MICRO_UBU_24_04}

STAGE=$(mktemp -d)
MNT=$(mktemp -d)
cleanup() { umount "$MNT" 2>/dev/null || true; rmdir "$MNT" "$STAGE" 2>/dev/null || true; }
trap cleanup EXIT

echo "Mounting source ISO: $SOURCE_ISO"
mount -o loop,ro "$SOURCE_ISO" "$MNT"

echo "Copying ISO contents to staging"
rsync -aHAX --delete "$MNT/" "$STAGE/"

# Validate it's a Server Live ISO (desktop ISOs are not supported for Subiquity autoinstall remaster)
if [[ ! -f "$STAGE/boot/grub/grub.cfg" ]] || [[ ! -f "$STAGE/casper/vmlinuz" ]]; then
  echo "ERROR: The provided ISO does not look like a Ubuntu Server Live ISO (missing boot/grub/grub.cfg or casper/vmlinuz)." >&2
  echo "Please use ubuntu-24.04.x-live-server-amd64.iso." >&2
  exit 5
fi
if [[ -f "$STAGE/.disk/info" ]] && ! grep -qi "server" "$STAGE/.disk/info"; then
  echo "ERROR: ISO .disk/info does not indicate 'Server'. This script supports the Ubuntu Server Live ISO only." >&2
  echo "Please use ubuntu-24.04.x-live-server-amd64.iso." >&2
  exit 6
fi

echo "Injecting autoinstall seed into /autoinstall (including extras)"
mkdir -p "$STAGE/autoinstall"
cp -a autoinstall/. "$STAGE/autoinstall/"

echo "Patching boot configs to autoinstall"
# Patch GRUB (UEFI)
if [[ -f "$STAGE/boot/grub/grub.cfg" ]]; then
  cp "$STAGE/boot/grub/grub.cfg" "$STAGE/boot/grub/grub.cfg.orig"
  sed -E -i 's#(linux(efi)?\s+/casper/[^ ]+)#\1 autoinstall ds=nocloud\\;s=/cdrom/autoinstall/#' "$STAGE/boot/grub/grub.cfg" || true
fi
# Patch ISOLINUX (BIOS) if present
if [[ -f "$STAGE/isolinux/txt.cfg" ]]; then
  cp "$STAGE/isolinux/txt.cfg" "$STAGE/isolinux/txt.cfg.orig"
  sed -E -i 's#(append .*)#\1 autoinstall ds=nocloud;s=/cdrom/autoinstall/#' "$STAGE/isolinux/txt.cfg" || true
fi

echo "Rebuilding ISO by replaying boot metadata from source"
xorriso -indev "$SOURCE_ISO" -outdev "$ISO_OUT" \
  -map "$STAGE" / \
  -boot_image any replay

echo "ISO created: $ISO_OUT"
