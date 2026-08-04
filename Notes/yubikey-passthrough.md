# YubiKey Passthrough

Pass a YubiKey from the host to a libvirt/QEMU guest VM.

> The YubiKey is exclusively owned by the guest while attached. Detach to use it on the host again.

For VMs created by this repo, `./use-yubikey.sh insert <vm-name>` does
steps 1 and 4 in one command. You still need step 3 on the host if `pcscd`
is running there. This document is the manual reference and covers
troubleshooting for custom images.

## 1. Find the device (host)

```bash
lsusb | grep -i yubi
```

```
Bus 003 Device 005: ID 1050:0406 Yubico.com Yubikey 4/5 U2F+CCID
```

The `ID` field is `vendor:product`. Product IDs vary by model and mode
(e.g. `0x0406`, `0x0407`, `0x0402`). Always check with `lsusb` first.

## 2. Install guest dependencies

```bash
sudo apt install -y yubikey-manager opensc pcscd pcsc-tools libnss3-tools libccid
```

Included by default in `autoinstall-desktop.yaml`.

## 3. Stop host pcscd (host)

The host's PC/SC daemon competes with QEMU for the USB device. Stop it
before attaching:

```bash
sudo systemctl stop pcscd pcscd.socket
```

Without this, the guest fails with `can't set config #1, error -32`.

Re-enable after detaching:

```bash
sudo systemctl start pcscd.socket
```

## 4. Attach (host)

Hot-plug — no VM reboot needed:

```bash
echo '<hostdev mode="subsystem" type="usb" managed="yes">
  <source><vendor id="0x1050"/><product id="0x0406"/></source>
</hostdev>' | virsh -c qemu:///system attach-device <VM_NAME> /dev/stdin
```

Add `--config` to persist across VM reboots.

## 5. Verify (guest)

```bash
sudo systemctl restart pcscd
ykman info
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so -L
```

`ykman info` should show the device. `pkcs11-tool -L` should list a slot
with the YubiKey token.

## Detach (host)

```bash
echo '<hostdev mode="subsystem" type="usb" managed="yes">
  <source><vendor id="0x1050"/><product id="0x0406"/></source>
</hostdev>' | virsh -c qemu:///system detach-device <VM_NAME> /dev/stdin
```
