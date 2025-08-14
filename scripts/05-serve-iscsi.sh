#!/usr/bin/env bash
set -euo pipefail

# 05-serve-iscsi.sh: Export the built qcow2 as an iSCSI LUN and emit an iPXE snippet.
# Boot the qcow2 directly (no ISO) via iPXE SAN boot.
#
# Requirements (Ubuntu 24.04 host):
#   sudo apt-get install -y qemu-utils targetcli-fb
#
# Usage:
#   sudo scripts/05-serve-iscsi.sh [qcow2_path] [server_ip]
#
# Security note: this uses demo mode (no auth, open ACLs). Restrict to lab nets
# or add CHAP + explicit ACLs for production.

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Please run as root (sudo)" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
ARTIFACTS_DIR="$REPO_ROOT/artifacts"

IMG_QCOW2="${1:-$ARTIFACTS_DIR/micro-linux-ubuntu-24.04.qcow2}"
SERVER_IP_DEFAULT=$(ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}')
SERVER_IP="${2:-${SERVER_IP_DEFAULT:-127.0.0.1}}"
IQN_BASE="${IQN_BASE:-iqn.2025-08.local.micro:target}"
TARGET_IQN="${TARGET_IQN:-$IQN_BASE:ml}"
TPG="1"
PORT="3260"

command -v qemu-nbd >/dev/null || { echo "Missing qemu-utils (qemu-nbd)" >&2; exit 2; }
command -v targetcli >/dev/null || { echo "Missing targetcli-fb (targetcli)" >&2; exit 2; }

if [[ ! -f "$IMG_QCOW2" ]]; then
  echo "qcow2 image not found: $IMG_QCOW2" >&2
  exit 3
fi

mkdir -p "$ARTIFACTS_DIR"

pick_nbd() {
  modprobe nbd max_part=16 || true
  for i in {0..15}; do
    local dev="/dev/nbd${i}"
    [[ -e "$dev" ]] || continue
    local pidf="/sys/class/block/nbd${i}/pid"
    if [[ ! -s "$pidf" ]]; then
      echo "$dev"; return 0
    fi
  done
  return 1
}

NBD_DEV=$(pick_nbd) || { echo "No free /dev/nbdX devices" >&2; exit 4; }
qemu-nbd --disconnect "$NBD_DEV" >/dev/null 2>&1 || true
qemu-nbd --fork --persistent --connect="$NBD_DEV" "$IMG_QCOW2"
trap 'qemu-nbd --disconnect "$NBD_DEV" || true' EXIT
udevadm settle || sleep 0.5

# Idempotent target setup
set +e
sudo targetcli /iscsi delete "$TARGET_IQN" >/dev/null 2>&1
sudo targetcli /backstores/block delete ml-disk >/dev/null 2>&1
set -e

# Create backstore, target, portal, and LUN
sudo targetcli /backstores/block create name=ml-disk dev="$NBD_DEV" >/dev/null
sudo targetcli /iscsi create "$TARGET_IQN" >/dev/null
sudo targetcli /iscsi "$TARGET_IQN"/tpg$TPG/portals delete 0.0.0.0 "$PORT" >/dev/null 2>&1 || true
sudo targetcli /iscsi "$TARGET_IQN"/tpg$TPG/portals delete :: "$PORT" >/dev/null 2>&1 || true
sudo targetcli /iscsi "$TARGET_IQN"/tpg$TPG/portals create "$SERVER_IP" "$PORT" >/dev/null
sudo targetcli /iscsi "$TARGET_IQN"/tpg$TPG/luns create /backstores/block/ml-disk >/dev/null
sudo targetcli /iscsi "$TARGET_IQN"/tpg$TPG set attribute generate_node_acls=1 >/dev/null
sudo targetcli /iscsi "$TARGET_IQN"/tpg$TPG set attribute cache_dynamic_acls=1 >/dev/null
sudo targetcli /iscsi "$TARGET_IQN"/tpg$TPG set attribute demo_mode_write_protect=0 >/dev/null
sudo targetcli / saveconfig >/dev/null || true

IPXE_FILE="$ARTIFACTS_DIR/ipxe-micro-linux.ipxe"
cat > "$IPXE_FILE" <<IPXE
#!ipxe
set initiator-iqn iqn.1993-08.org.debian:client-
echo Booting micro-linux via iSCSI SAN (target: $TARGET_IQN)
dhcp
sanhook iscsi:$SERVER_IP::::$TARGET_IQN
sanboot --no-describe iscsi:$SERVER_IP::::$TARGET_IQN
IPXE

cat <<EOF

iSCSI target ready
  Target IQN : $TARGET_IQN
  Portal     : $SERVER_IP:$PORT
  Backstore  : $NBD_DEV <- $IMG_QCOW2

UEFI-only note: the qcow2 image has GRUB for UEFI. Disable Secure Boot unless you built with SECURE_BOOT=1.

iPXE script written to: $IPXE_FILE
Serve it over HTTP, or type at iPXE prompt:
  chain http://$SERVER_IP/artifacts/$(basename "$IPXE_FILE")

dnsmasq chainload example:
  enable-tftp
  tftp-root=/srv/tftp
  dhcp-match=set:efi64,option:client-arch,7
  dhcp-boot=tag:efi64,ipxe.efi
  dhcp-boot=tag:!efi64,undionly.kpxe

EOF
