# YubiKey Passthrough

Pass a YubiKey from the host to a libvirt/QEMU guest VM.

> **Note:** The YubiKey is exclusively owned by the guest while attached. Detach to use it on the host again.

## 1. Find the device (host)

```bash
lsusb | grep -i yubi
```

```
Bus 003 Device 005: ID 1050:0406 Yubico.com Yubikey 4/5 U2F+CCID
```

The `ID` field is `vendor:product` — in this case `1050:0406`. Use these values in the commands below.

Product IDs vary by model and mode (e.g. `0x0406`, `0x0407`, `0x0402`). Always check with `lsusb` first.

## 2. Install guest dependencies (guest)

```bash
sudo apt install -y yubikey-manager pcscd libu2f-udev libccid
```

## 3. Stop host pcscd (host)

The host's PC/SC smart card daemon competes with QEMU for the USB device. Stop it before attaching:

```bash
sudo systemctl stop pcscd pcscd.socket
```

Without this, the guest will fail with `can't set config #1, error -32` and the YubiKey won't be usable.

To re-enable after detaching:

```bash
sudo systemctl start pcscd.socket
```

## 4. Attach (host)

Hot-plug — no VM reboot needed:

```bash
echo '<hostdev mode="subsystem" type="usb" managed="yes">
  <source><vendor id="0x1050"/><product id="0x0406"/></source>
</hostdev>' | virsh -c qemu:///system attach-device VM_NAME /dev/stdin
```

Add `--config` to persist across VM reboots.

## 5. Verify (guest)

```bash
sudo systemctl restart pcscd
ykman info
```

## Detach (host)

```bash
echo '<hostdev mode="subsystem" type="usb" managed="yes">
  <source><vendor id="0x1050"/><product id="0x0406"/></source>
</hostdev>' | virsh -c qemu:///system detach-device VM_NAME /dev/stdin
```
