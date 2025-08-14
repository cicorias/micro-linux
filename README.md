# micro-linux

Minimal Ubuntu 24.04 installable image for x86_64 with automated, repeatable builds.

## Purpose

Produce a small, installable Ubuntu 24.04 (Noble) image for x86_64. Validate artifacts quickly in QEMU/Hyper‑V before using on hardware.

## Scope

- Minimal, bootable, installable image (x86_64)
- Subiquity autoinstall (non-interactive)
- Rootfs via mmdebstrap
- Artifacts: ISO and qcow2
- QEMU smoke tests; Hyper‑V optional

## Build host requirements

- Ubuntu 24.04 (x86_64)
- Packages:
  - mmdebstrap
  - qemu-system-x86
  - xorriso, mtools, grub-pc-bin, grub-efi-amd64-bin
  - squashfs-tools, e2fsprogs
  - cloud-init (for schema validation)
  - openssh-server (target)

Note: The setup script enables the Ubuntu 'universe' repo as needed.

## Trying different autoinstall templates and configurations

Templates:
- Autolayout (installer chooses): `autoinstall/user-data.autolayout.template`
- Minimal UEFI (ESP + single root): `autoinstall/user-data.minimal.template`
- A/B layout (ESP + rootA + rootB + data): `autoinstall/user-data.template`

Notes
- Regenerate the seed after switching templates (overwrites `autoinstall/user-data`).
- Validate with `cloud-init schema` to catch YAML issues.
- For A/B, prefer a ≥24G target disk.
- Networking defaults to DHCP; see overrides below.

## Run steps (copy/paste)

### Autolayout (baseline)

```zsh
# Generate seed (installer picks layout)
sudo STORAGE_MODE=auto ./scripts/02-seed.sh

# Validate schema (recommended)
cloud-init schema --config-file autoinstall/user-data

# Rebuild installer ISO (use Server Live ISO)
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh

# Install in QEMU with UEFI (creates ~24G target by default)
sudo ./scripts/04-test-qemu.sh --iso
```

### Minimal UEFI (ESP + root)

```zsh
# Generate seed from the minimal template
sudo USER_DATA_TEMPLATE=autoinstall/user-data.minimal.template ./scripts/02-seed.sh

# Validate schema
cloud-init schema --config-file autoinstall/user-data

# Build ISO and run UEFI install test
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh
sudo ./scripts/04-test-qemu.sh --iso
```

### A/B layout (ESP + rootA + rootB + data)

```zsh
# Generate seed from the A/B template
sudo USER_DATA_TEMPLATE=autoinstall/user-data.template ./scripts/02-seed.sh

# Validate schema
cloud-init schema --config-file autoinstall/user-data

# Build ISO and run UEFI install test (use ≥24G target disk)
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh
INSTALL_SIZE_GB=24 sudo ./scripts/04-test-qemu.sh --iso
```

### Optional: Networking overrides

`scripts/02-seed.sh` writes a netplan file into the seed. Defaults to DHCP.

```zsh
# DHCP (default)
sudo NET_MODE=dhcp USER_DATA_TEMPLATE=autoinstall/user-data.minimal.template ./scripts/02-seed.sh

# Static example
sudo NET_MODE=static IFACE=enp0s1 ADDR=192.168.1.50 PREFIX=24 GATEWAY=192.168.1.1 \
  USER_DATA_TEMPLATE=autoinstall/user-data.template \
  ./scripts/02-seed.sh
```

### Optional: Quick checks

```zsh
# Show rendered storage section
sed -n '/^  storage:/,/^  late-commands:/p' autoinstall/user-data

# Focus on fs_esp block
sed -n '/- id: fs_esp/,/^- id:/p' autoinstall/user-data
```

## Using the image

For bare metal, see [using image](./doc/using-image.md).

## Building artifacts

Run the scripts in order (root required). Provide the official Ubuntu 24.04 Server Live ISO via SOURCE_ISO.

```zsh
sudo ./scripts/00-setup-build-host.sh
sudo ./scripts/01-rootfs.sh
sudo NET_MODE=dhcp ./scripts/02-seed.sh
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh
sudo SIZE_GB=8 ./scripts/03b-image-qcow2.sh
```

Quick reference:

```zsh
sudo NET_MODE=dhcp ./scripts/02-seed.sh
sudo SOURCE_ISO=/path/to/ubuntu-24.04-live-server-amd64.iso ./scripts/03-image.sh
sudo SIZE_GB=8 ./scripts/03b-image-qcow2.sh
```

## Directory layout (suggested)

```
.
├─ autoinstall/
│  ├─ user-data      # cloud-init user-data (with per-build hashed password)
│  └─ meta-data      # cloud-init meta-data
├─ scripts/
│  ├─ 01-rootfs.sh         # build minimal rootfs (includes openssh-server)
│  ├─ 02-seed.sh           # generate password and autoinstall seed
│  ├─ 03-image.sh          # assemble ISO (hybrid) with autoinstall seed
│  ├─ 03b-image-qcow2.sh   # assemble qcow2 disk image with GRUB
│  └─ 04-test-qemu.sh      # smoke tests for ISO and qcow2
├─ artifacts/
└─ README.md
```

## Security notes

- Per-build plaintext password is written to artifacts/password.txt (never commit it).
- Only the hashed password goes into autoinstall user-data.
- Consider disabling password auth and using SSH keys for production.



