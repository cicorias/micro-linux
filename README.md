# micro-linux

Minimal Ubuntu 24.04 installable image for x86_64 with automated, repeatable builds.

## Purpose

This repository aims to produce a very small Ubuntu 24.04 (Noble) installable image for x86_64 devices. The resulting artifact should be easy to validate in a VM (QEMU or Hyper‑V) so you can verify image size and basic functionality before using it on real hardware.

## Scope

- Small, bootable, installable Ubuntu 24.04 image (x86_64)
- Automated provisioning via Subiquity autoinstall (non-interactive)
- Root filesystem assembled with mmdebstrap for minimal size
- Produce two artifact formats:
  - ISO (installable media)
  - Raw disk image in qcow2 format (bootable disk)
- Testable locally using QEMU, and optionally in Hyper‑V

Non-goals (for now): desktop environments, full server profiles, or platform-specific drivers beyond generic x86_64.

## Build host requirements

- Build OS: Ubuntu 24.04 (x86_64)
- Suggested packages (install as needed):
  - mmdebstrap
  - qemu-system-x86 (for local testing)
  - xorriso, mtools, grub-pc-bin, grub-efi-amd64-bin (ISO/EFI boot assembly)
  - squashfs-tools, e2fsprogs (filesystem images)
  - cloud-init (for schema validation; installer ISO provides curtin/subiquity during install)
  - openssh-server (included in the installed system for remote access)

Note: Exact package set may vary depending on your final image layout (e.g., BIOS-only vs. UEFI, ISO/hybrid image vs. raw disk image). The setup script enables the Ubuntu 'universe' repository as needed.

## Approach (high level)

1) Establish a minimal root filesystem with mmdebstrap
	- Use mmdebstrap to create a minimal Ubuntu 24.04 rootfs tailored to your needs (base + a few essential packages).
	- Prune locales, docs, and recommends to reduce size (only as appropriate for your use-case).
  - Ensure essential services like `openssh-server` are included for remote access post-install.

2) Configure Subiquity autoinstall
	- Provide an autoinstall seed (cloud-init user-data and meta-data) for a non-interactive installation.
	- The autoinstall “identity” section will include a per-build password (see Security below). The build process will surface this password in its output.

3) Assemble a bootable installable image
	- Package the minimal rootfs and autoinstall seed into a bootable, installable artifact (ISO/hybrid ISO, or a raw disk image with appropriate bootloader).
	- Include GRUB and support for BIOS and/or UEFI as needed.
  - Emit both an ISO and a qcow2 disk image under `artifacts/`.

4) Validate in virtualization
	- Boot the artifact in QEMU or Hyper‑V to confirm bootability, autoinstall behavior, and on-disk footprint after install.
  - GRUB should include entries for both rootA and rootB; use grubenv to manage default/next entries for OTA fallback.

## Autoinstall and per-build password

- Autoinstall uses Subiquity with cloud-init style configuration.
- The identity section specifies the initial user and a hashed password. For security, each build injects a unique, per-build password.
- The build should output the generated password (e.g., to the console and/or an artifact file) so testers can log in after installation.

Recommendation: Emit both the plaintext (for immediate testing) and the hashed form (what goes into autoinstall). Never commit plaintext passwords to the repo.

## Filesystems and partitioning (OTA-ready)

- Filesystems:
  - EFI System Partition (ESP): FAT32 (vfat)
  - Root partitions: ext4
- Recommended partitioning for OTA and fallback (A/B scheme):
  - p1: EFI (FAT32), ~256–512 MiB
  - p2: rootA (ext4)
  - p3: rootB (ext4)
  - p4: data (ext4) optional, for persistent state/logs
- Boot and OTA flow:
  - System boots via GRUB; default “slot” (A or B) is recorded in `grubenv`.
  - OTA updates write the new OS to the inactive root (flip A↔B), update kernel/initrd in `/boot` on that slot, and set next boot to the new slot.
  - On successful boot, a systemd unit marks `boot_success=1` in `grubenv` to persist selection. If the new slot fails to boot, GRUB falls back to the previous slot.

Minimal curtin storage sketch (illustrative):

```yaml
storage:
  version: 1
  config:
    - { id: disk0, type: disk, ptable: gpt, wipe: superblock-recursive, grub_device: true }
    - { id: esp, type: partition, device: disk0, size: 512M, flag: boot }
    - { id: rootA, type: partition, device: disk0, size: 8G }
    - { id: rootB, type: partition, device: disk0, size: 8G }
    - { id: data,  type: partition, device: disk0, size: -1 }
    - { id: fs_esp,  type: format, fstype: vfat, volume: esp }
    - { id: fs_rootA,type: format, fstype: ext4, volume: rootA }
    - { id: fs_rootB,type: format, fstype: ext4, volume: rootB }
    - { id: fs_data, type: format, fstype: ext4, volume: data }
    - { id: mnt_esp,  type: mount,  path: /boot/efi, device: fs_esp }
    - { id: mnt_root, type: mount,  path: /,        device: fs_rootA }
```

Notes:
- Initial install mounts rootA at `/`. Provision GRUB with menuentries for both A and B and enable `grubenv` (`grub-editenv`).
- An OTA agent should: write to the inactive root, validate, set GRUB next entry to the updated slot, and only mark success after boot completes.

## Testing the image

You can validate the artifact’s size and installation flow using virtualization. Below are optional examples; adapt paths and flags to your artifact type.

### QEMU (optional example)

```
# Optional: BIOS boot
qemu-system-x86_64 \
  -m 1024 \
  -enable-kvm \
  -cpu host \
  -cdrom out/micro-linux-ubuntu-24.04.iso \
  -boot d \
  -drive file=out/test-disk.qcow2,if=virtio,format=qcow2 \
  -display none -serial mon:stdio

# Optional: UEFI boot (if ISO/artifact supports UEFI)
qemu-system-x86_64 \
  -m 1024 \
  -enable-kvm \
  -cpu host \
  -bios /usr/share/OVMF/OVMF_CODE.fd \
  -cdrom out/micro-linux-ubuntu-24.04.iso \
  -boot d \
  -drive file=out/test-disk.qcow2,if=virtio,format=qcow2 \
  -display none -serial mon:stdio
```

### QEMU (boot qcow2 disk directly)

```
qemu-system-x86_64 -enable-kvm -cpu host -m 1024 \
  -drive file=artifacts/micro-linux-ubuntu-24.04.qcow2,if=virtio,format=qcow2 \
  -serial mon:stdio -display none
```

## Building artifacts

Run the scripts in order (root required for image steps). Start with the build host setup to install required packages and UEFI support. For the installer ISO remaster, provide the official Ubuntu 24.04 installer ISO via SOURCE_ISO:

```
sudo ./scripts/00-setup-build-host.sh
sudo ./scripts/01-rootfs.sh
sudo NET_MODE=dhcp ./scripts/02-seed.sh   # or NET_MODE=static IFACE=eth0 ADDR=192.168.1.10 PREFIX=24 GATEWAY=192.168.1.1 ./scripts/02-seed.sh
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh   # Use the Server Live ISO, not Desktop
sudo SIZE_GB=8 ./scripts/03b-image-qcow2.sh
```

Then proceed with autoinstall seed and image creation (quick reference):

```bash
sudo NET_MODE=dhcp ./scripts/02-seed.sh
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh
sudo SIZE_GB=8 ./scripts/03b-image-qcow2.sh
```

Expected behavior: VM boots, autoinstall runs without prompts, system reboots to a minimal Ubuntu 24.04 with the per-build credentials.

### Hyper‑V (optional pointers)

- Create Generation 2 VM for UEFI.
- Attach the ISO as DVD, add a small VHDX (e.g., 4–8 GB minimum depending on your package set).
- Boot; autoinstall proceeds automatically.

## Validating autoinstall files

You can validate the `autoinstall/user-data` against the cloud-init schema on the build host:

```
cloud-init schema --config-file autoinstall/user-data
```

The seed script attempts validation automatically if cloud-init is installed on the build host.

Note: Subiquity autoinstall leverages cloud-init; even if you minimize the target image, keeping cloud-init in the installed system can be useful for first-boot customization. If you decide to remove it post-install, ensure your autoinstall and any first-boot configuration do not depend on it.

TODO:
- Netplan: define DHCP/static as needed and add to autoinstall (or first-boot) configuration.
- Decide whether cloud-init should remain installed in the final system; document the rationale.

## Directory layout (suggested)

```
.
├─ autoinstall/
│  ├─ user-data      # cloud-init user-data (with per-build hashed password)
│  └─ meta-data      # cloud-init meta-data
├─ scripts/          # build scripts (mmdebstrap, image assembly, password emission)
│  ├─ 01-rootfs.sh         # build minimal rootfs (includes openssh-server)
│  ├─ 02-seed.sh           # generate per-build password and autoinstall seed (A/B + GRUB)
│  ├─ 03-image.sh          # assemble ISO (hybrid) with autoinstall seed
│  ├─ 03b-image-qcow2.sh   # assemble qcow2 disk image with GRUB
│  └─ 04-test-qemu.sh      # smoke tests for ISO and qcow2
├─ artifacts/        # built images (ISO/raw) and logs
└─ README.md
```

## Security notes

- Treat the per-build plaintext password as sensitive. Print once to the build log and/or write to a local artifacts file excluded from version control.
- Store only a secure hash (e.g., SHA-512 via mkpasswd or openssl) in the autoinstall config.
- Consider rotating credentials or disabling password auth for production images, switching to SSH keys.
 - Include `openssh-server` so the installed system supports remote access immediately after install.

## Status

This repo documents the intended approach and constraints. Scripts are scaffolded under `scripts/`. CI hooks are deferred for now but should eventually verify: ISO and qcow2 builds, autoinstall success, and A/B fallback behavior in QEMU.

