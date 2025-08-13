# micro-linux

Minimal Ubuntu 24.04 installable image for x86_64 with automated, repeatable builds.

## Purpose

This repository aims to produce a very small Ubuntu 24.04 (Noble) installable image for x86_64 devices. The resulting artifact should be easy to validate in a VM (QEMU or Hyper‑V) so you can verify image size and basic functionality before using it on real hardware.

## Scope

- Small, bootable, installable Ubuntu 24.04 image (x86_64)
- Automated provisioning via Subiquity autoinstall (non-interactive)
- Root filesystem assembled with mmdebstrap for minimal size
- Testable locally using QEMU, and optionally in Hyper‑V

Non-goals (for now): desktop environments, full server profiles, or platform-specific drivers beyond generic x86_64.

## Build host requirements

- Build OS: Ubuntu 24.04 (x86_64)
- Suggested packages (install as needed):
  - mmdebstrap
  - qemu-system-x86 (for local testing)
  - xorriso, mtools, grub-pc-bin, grub-efi-amd64-bin (ISO/EFI boot assembly)
  - squashfs-tools, e2fsprogs (filesystem images)
  - cloud-init, curtin, subiquity (for autoinstall support)

Note: Exact package set may vary depending on your final image layout (e.g., BIOS-only vs. UEFI, ISO/hybrid image vs. raw disk image).

## Approach (high level)

1) Establish a minimal root filesystem with mmdebstrap
	- Use mmdebstrap to create a minimal Ubuntu 24.04 rootfs tailored to your needs (base + a few essential packages).
	- Prune locales, docs, and recommends to reduce size (only as appropriate for your use-case).

2) Configure Subiquity autoinstall
	- Provide an autoinstall seed (cloud-init user-data and meta-data) for a non-interactive installation.
	- The autoinstall “identity” section will include a per-build password (see Security below). The build process will surface this password in its output.

3) Assemble a bootable installable image
	- Package the minimal rootfs and autoinstall seed into a bootable, installable artifact (ISO/hybrid ISO, or a raw disk image with appropriate bootloader).
	- Include GRUB and support for BIOS and/or UEFI as needed.

4) Validate in virtualization
	- Boot the artifact in QEMU or Hyper‑V to confirm bootability, autoinstall behavior, and on-disk footprint after install.

## Autoinstall and per-build password

- Autoinstall uses Subiquity with cloud-init style configuration.
- The identity section specifies the initial user and a hashed password. For security, each build injects a unique, per-build password.
- The build should output the generated password (e.g., to the console and/or an artifact file) so testers can log in after installation.

Recommendation: Emit both the plaintext (for immediate testing) and the hashed form (what goes into autoinstall). Never commit plaintext passwords to the repo.

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

Expected behavior: VM boots, autoinstall runs without prompts, system reboots to a minimal Ubuntu 24.04 with the per-build credentials.

### Hyper‑V (optional pointers)

- Create Generation 2 VM for UEFI.
- Attach the ISO as DVD, add a small VHDX (e.g., 4–8 GB minimum depending on your package set).
- Boot; autoinstall proceeds automatically.

## Directory layout (suggested)

```
.
├─ autoinstall/
│  ├─ user-data      # cloud-init user-data (with per-build hashed password)
│  └─ meta-data      # cloud-init meta-data
├─ scripts/          # build scripts (mmdebstrap, image assembly, password emission)
├─ artifacts/        # built images (ISO/raw) and logs
└─ README.md
```

## Security notes

- Treat the per-build plaintext password as sensitive. Print once to the build log and/or write to a local artifacts file excluded from version control.
- Store only a secure hash (e.g., SHA-512 via mkpasswd or openssl) in the autoinstall config.
- Consider rotating credentials or disabling password auth for production images, switching to SSH keys.

## Status

This repo documents the intended approach and constraints. Build scripts and CI wiring can be added next to automate: rootfs creation (mmdebstrap), autoinstall seeding, bootable image assembly, and VM validation.

