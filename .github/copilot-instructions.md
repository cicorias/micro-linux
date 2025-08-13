# AI agent instructions for micro-linux

This repo builds a minimal Ubuntu 24.04 (x86_64) installable image using a tiny rootfs (mmdebstrap) + Subiquity autoinstall. It emits both ISO and qcow2 artifacts. Test via QEMU/Hyper‑V. Build host must be Ubuntu 24.04.

## Architecture & workflow
1) Build minimal rootfs with mmdebstrap (include openssh-server).
2) Prepare Subiquity autoinstall seed (cloud-init user-data/meta-data).
3) Assemble bootable installable artifacts: ISO (hybrid) and qcow2 disk image with GRUB for BIOS/UEFI.
4) Validate boot, autoinstall, A/B fallback, and installed footprint in a VM.

Non-goals: desktop stacks or large package sets—keep it small and bootable.

## Repo layout & conventions
- `README.md` is authoritative for goals/constraints.
- Suggested (create if missing):
  - `autoinstall/` → `user-data`, `meta-data` (cloud-init seed)
  - `scripts/` → ordered, idempotent build scripts: `01-rootfs.sh`, `02-seed.sh`, `03-image.sh` (ISO), `03b-image-qcow2.sh` (qcow2), `04-test-qemu.sh`
  - `artifacts/` → ISO and qcow2 images, logs, and emitted plaintext password (never commit)
- Convention: write all generated files to `artifacts/`; don’t pollute the repo.

## Build host & deps (Ubuntu 24.04)
`mmdebstrap qemu-system-x86 xorriso mtools grub-pc-bin grub-efi-amd64-bin squashfs-tools e2fsprogs cloud-init curtin subiquity`

## Key patterns (examples)
- mmdebstrap minimal rootfs (with SSH server):
  ```bash
  mmdebstrap --variant=minbase --include=systemd-sysv,openssh-server \
    noble artifacts/rootfs http://archive.ubuntu.com/ubuntu
  ```
- Per-build password (emit plaintext; store hash in autoinstall):
  ```bash
  PW=$(openssl rand -base64 18)
  HASH=$(mkpasswd -m sha-512 "$PW" 2>/dev/null || openssl passwd -6 "$PW")
  mkdir -p artifacts && echo "$PW" > artifacts/password.txt
  # Use $HASH in autoinstall identity.password
  ```
- Subiquity autoinstall seed (user-data):
  ```yaml
  autoinstall:
    version: 1
    identity: { hostname: micro, username: ubuntu, password: $6$... }
  ```

Validate autoinstall format:
```bash
cloud-init schema --config-file autoinstall/user-data
```

TODOs:
- Netplan: decide DHCP/static and add to autoinstall or first-boot.
- Cloud-init in target: Subiquity uses cloud-init during install; decide whether to keep it post-install.

## Testing (QEMU)
```bash
qemu-system-x86_64 -enable-kvm -cpu host -m 1024 \
  -cdrom artifacts/micro-linux-ubuntu-24.04.iso \
  -drive file=artifacts/test.qcow2,if=virtio,format=qcow2 \
  -boot d -serial mon:stdio -display none
```

```bash
# Boot qcow2 directly
qemu-system-x86_64 -enable-kvm -cpu host -m 1024 \
  -drive file=artifacts/micro-linux-ubuntu-24.04.qcow2,if=virtio,format=qcow2 \
  -serial mon:stdio -display none
```

## Filesystems & partitioning (OTA/fallback)
- ESP: FAT32; root partitions: ext4.
- Use A/B root partitions (rootA, rootB) to enable OTA updates and fallback.
- GRUB manages default/next entries via grubenv; on boot success, a systemd unit marks success; otherwise GRUB falls back.
- Curtin/storage sketch: GPT with p1 ESP (FAT32), p2 rootA (ext4), p3 rootB (ext4), optional p4 data (ext4).

## Security & outputs
- Never commit plaintext passwords; only under `artifacts/` and print once to build logs.
- Only the hashed password goes into `autoinstall/user-data`.

## PR expectations
- Scripts run on Ubuntu 24.04, are idempotent, and keep image small (no recommends/docs unless needed).
- Document new scripts in `README.md` and ensure QEMU smoke test works for both ISO and qcow2; verify A/B fallback where applicable.

Note: The ISO builder remasters the official Ubuntu installer ISO by injecting `autoinstall/` and patching boot configs to add `autoinstall ds=nocloud;s=/cdrom/autoinstall/`. Provide `SOURCE_ISO` when running.

## CI
- CI hooks are deferred for now. When added, validate: ISO and qcow2 builds, autoinstall success, and A/B fallback behavior in QEMU.
