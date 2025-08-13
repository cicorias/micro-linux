#!/usr/bin/env bash
set -euo pipefail

# 04-test-qemu.sh: Quick headless smoke tests for ISO and qcow2 artifacts

ISO="artifacts/micro-linux-ubuntu-24.04.iso"
QCOW2="artifacts/micro-linux-ubuntu-24.04.qcow2"

if [[ -f "$ISO" ]]; then
  echo "Launching QEMU with ISO (install to test.qcow2)"
  qemu-system-x86_64 -enable-kvm -cpu host -m 1024 \
    -cdrom "$ISO" \
    -drive file=artifacts/test.qcow2,if=virtio,format=qcow2 \
    -boot d -serial mon:stdio -display none || true
else
  echo "ISO not found at $ISO" >&2
fi

if [[ -f "$QCOW2" ]]; then
  echo "Launching QEMU booting qcow2 directly"
  qemu-system-x86_64 -enable-kvm -cpu host -m 1024 \
    -drive file="$QCOW2",if=virtio,format=qcow2 \
    -serial mon:stdio -display none || true
else
  echo "QCOW2 not found at $QCOW2" >&2
fi
