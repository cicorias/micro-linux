# PXE-boot the qcow2 image directly (no ISO)

This repo's `03b-image-qcow2.sh` builds a fully bootable disk (ESP + GRUB + rootA/rootB). You can deploy it over the network by exposing the qcow2 as an iSCSI LUN and using iPXE to SAN-boot.

## Quick start

1) Build the qcow2 (on Ubuntu 24.04):

    sudo scripts/03b-image-qcow2.sh

2) Export it as iSCSI:

    sudo apt-get install -y qemu-utils targetcli-fb
    sudo scripts/05-serve-iscsi.sh artifacts/micro-linux-ubuntu-24.04.qcow2 <SERVER_IP>

The script attaches the qcow2 to `/dev/nbdX`, creates an iSCSI target (demo mode, no auth), and writes `artifacts/ipxe-micro-linux.ipxe`.

3) Chainload iPXE from PXE (dnsmasq example):

```
enable-tftp
tftp-root=/srv/tftp
dhcp-match=set:efi64,option:client-arch,7
dhcp-boot=tag:efi64,ipxe.efi
dhcp-boot=tag:!efi64,undionly.kpxe
```

Place `ipxe.efi` (UEFI) and `undionly.kpxe` (BIOS) in `/srv/tftp`.

4) On the iPXE prompt (or via HTTP):

```
chain http://<SERVER_IP>/artifacts/ipxe-micro-linux.ipxe
```

iPXE will attach the LUN and boot the qcow2's own GRUB/Kernel.

## Notes

- Secure Boot: disable for testing, or build the image with `SECURE_BOOT=1` so it uses `shim-signed`.
- Persistence: clients will install/modify the same network disk. For per‑node clones, export separate qcow2s or use LVM/zvol snapshots.
- Security: demo mode is open; add CHAP and explicit initiator ACLs in `targetcli` for production.
- Alternatives: you can also export the qcow2 over NBD and use GRUB/iPXE `sanboot` with `nbd://` (less widely supported than iSCSI).
