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

for f in autoinstall/user-data autoinstall/meta-data; do
  [[ -f "$f" ]] || { echo "Missing $f. Run ./scripts/02-seed.sh first." >&2; exit 4; }
done

mkdir -p artifacts
ISO_OUT="artifacts/micro-linux-ubuntu-24.04.iso"
VOLID=${VOLID:-MICRO-UBU-24.04}

STAGE=$(mktemp -d)
MNT=$(mktemp -d)
cleanup() { umount "$MNT" 2>/dev/null || true; rmdir "$MNT" "$STAGE" 2>/dev/null || true; }
trap cleanup EXIT

echo "Mounting source ISO: $SOURCE_ISO"
mount -o loop,ro "$SOURCE_ISO" "$MNT"

echo "Copying ISO contents to staging"
rsync -aHAX --delete "$MNT/" "$STAGE/"

echo "Injecting autoinstall seed into /autoinstall"
mkdir -p "$STAGE/autoinstall"
cp autoinstall/user-data "$STAGE/autoinstall/user-data"
cp autoinstall/meta-data "$STAGE/autoinstall/meta-data"

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

echo "Building bootable hybrid ISO at $ISO_OUT (replaying boot metadata from source)"
xorriso -indev "$SOURCE_ISO" -outdev "$ISO_OUT" \
  -map "$STAGE" / \
  -boot_image any replay \
  -volid "$VOLID" \
  -rockridge on -joliet on

echo "ISO created: $ISO_OUT"
