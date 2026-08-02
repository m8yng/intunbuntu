# intunbuntu

Autoinstall config and helper scripts to build an Ubuntu Desktop VM for Intune enrollment.

<img width="480" alt="intunbuntu desktop" src="https://github.com/user-attachments/assets/d7b4ec3f-8058-4c82-bd84-6da9784ad721" />

## Overview

`create-intunbuntu-vm.sh` takes a stock Ubuntu Desktop ISO, remasters it with
`autoinstall-desktop.yaml`, and creates a libvirt/QEMU VM that installs
without prompts. On first boot the VM has the Intune Portal client, Edge,
LUKS with TPM2 auto-unlock, and smart card support ready for user sign-in.

## Added on top of stock Ubuntu

| Area | Content |
|---|---|
| Install | Unattended autoinstall |
| Intune stack | `intune-portal`, `microsoft-edge-stable`, `microsoft-azurevpnclient` |
| Disk encryption | LUKS + `clevis-tpm2` auto-unlock |
| Smart card | `opensc`, `pcscd`, `yubikey-manager`, polkit rule for `pcscd` access |
| VPN | `openvpn3-client`, `microsoft-azurevpnclient` |
| Hardening | `pam_pwquality` policy, key-only SSH, GDM smart-card auth disabled, several daemons disabled |
| Tools | `use-yubikey.sh` — USB-passthrough a YubiKey to a running VM |

## Quick start

```bash
./create-intunbuntu-vm.sh \
  --vm-name intune-vm1 \
  --disk-pin 345721 \
  --user-password 'M2!sQ8@vT5#LdR'
```

Downloads the ISO if needed, remasters it, installs, boots. Approximately 20 minutes.

```bash
ssh -i vm_prepare_files/id_ed25519 ubuntu@<vm-ip>
```

## Validated

| Ubuntu | intune-portal | identity-broker | Edge |
|---|---|---|---|
| 26.04 LTS (Resolute) | 1.2605.16 | 3.0.2 | 151.0.4129.59 |
| 24.04 LTS (Noble) | 1.2603.31 | 2.5.2 | 146.x |

## Scripts

### `create-intunbuntu-vm.sh`

| Flag | Required | Description | Default |
|---|---|---|---|
| `--vm-name` | Yes | VM name | — |
| `--disk-pin` | Yes | LUKS PIN, min 6 digits | — |
| `--user-password` | Yes | User password (12+ chars, complexity) | — |
| `--iso` | No | Ubuntu ISO path | `vm_prepare_files/ubuntu-*.iso` |
| `--config` | No | Autoinstall YAML | `autoinstall-desktop.yaml` |
| `--disk` | No | Disk size | `15G` |
| `--cpus` | No | vCPUs | `1` |
| `--memory` | No | RAM in MiB | `3072` |

### `use-yubikey.sh`

```bash
./use-yubikey.sh insert <vm-name>
./use-yubikey.sh remove <vm-name>
```

Prompts for selection if multiple YubiKeys are connected. The key is
exclusively owned by the VM while inserted. Inside the VM, verify with
`ykman piv info` and
`pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so -L`.

## Notes

**Login keyring.** Intune enrollment requires the GNOME "Login" keyring to
exist. Check with

```bash
busctl --user get-property org.freedesktop.secrets \
  /org/freedesktop/secrets/collection/login \
  org.freedesktop.Secret.Collection Label
```

Expected: `s "Login"`. If missing, reboot or open Edge to trigger the
keyring creation prompt (use the same password as the user login).

<img width="400" alt="keyring prompt" src="https://github.com/user-attachments/assets/7a535c27-fee2-4be2-8aef-7b4ee045efaf" />

**Smart card polkit rule.** pcscd's default policy allows only active GUI
sessions. Intune Portal and the identity broker run from a non-active
context and are rejected — `sudo ykman piv info` sees the certs but Intune's
picker is empty. The autoinstall drops
`/etc/polkit-1/rules.d/99-pcscd.rules` to allow the `ubuntu` user.

**Host pcscd conflict.** If `pcscd` is running on the host, QEMU may fail to
claim the USB device (`error -32`). Stop it before attaching:

```bash
sudo systemctl stop pcscd pcscd.socket
```

See [YubiKey USB passthrough to VM](Notes/yubikey-passthrough.md) for manual
XML, verification, and troubleshooting.

## Testing

Static checks:

```bash
make validate      # YAML + cloud-init schema + late-commands bash syntax
make shellcheck    # shellcheck the shell scripts
```

End-to-end in a throwaway VM:

```bash
make test-vm       # creates intunbuntu-test-<timestamp>
make clean-test-vm # tears it down
```

No CI yet. `make validate` runs in a second; `make test-vm` takes about 20 minutes.

## Details

See [`autoinstall-desktop.yaml`](autoinstall-desktop.yaml).

- APT sources added: Edge, Prod, Insiders Fast, Jammy Prod (for `intune-portal`).
- Disabled services: `cups`, `cups-browsed`, `avahi-daemon`, `ModemManager`, `fwupd`, `unattended-upgrades`, `apport`.
- Password policy: min 12 chars with upper, lower, digit, special.

## Remote autoinstall config

Served from `https://intunbuntu.azurewebsites.net/`. A custom LUKS PIN can
be passed in the path, e.g. `https://intunbuntu.azurewebsites.net/123321`.

## Guides

- [YubiKey USB passthrough to VM](Notes/yubikey-passthrough.md)
