# Gotchas

Small things that will bite you if you don't know about them.

## Login keyring

Intune enrollment requires the GNOME "Login" keyring to exist. Check with

```bash
busctl --user get-property org.freedesktop.secrets \
  /org/freedesktop/secrets/collection/login \
  org.freedesktop.Secret.Collection Label
```

A successful result prints `s "Login"`. If the command errors out, the
keyring is missing — reboot, or open Edge and follow the prompt to create
one (set its password to the user login password).

<img width="400" alt="keyring prompt" src="https://github.com/user-attachments/assets/7a535c27-fee2-4be2-8aef-7b4ee045efaf" />

## Cert-based auth needs a polkit rule

`pcscd`'s default policy allows only active GUI sessions. Intune Portal and
the identity broker run from a non-active context and are rejected —
`sudo ykman piv info` sees the certs but Intune's picker is empty.

The autoinstall drops `/etc/polkit-1/rules.d/99-pcscd.rules` to allow the
`ubuntu` user. Users of custom images can install the same rule; see
[Notes/yubikey-passthrough.md](yubikey-passthrough.md) for the full contents.

## Host pcscd conflict when passing a YubiKey through

If `pcscd` is running on the host, QEMU may fail to claim the USB device
with `error -32`. Stop it before attaching:

```bash
sudo systemctl stop pcscd pcscd.socket
```

Restart it after detaching:

```bash
sudo systemctl start pcscd.socket
```

See [Notes/yubikey-passthrough.md](yubikey-passthrough.md) for the full
manual passthrough flow.
