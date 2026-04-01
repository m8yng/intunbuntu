# intunbuntu

A collection of scripts and YAML files that helps automatically prepare an Intune-ready Ubuntu environment.

<img width="480" alt="intunbuntu desktop" src="https://github.com/user-attachments/assets/d7b4ec3f-8058-4c82-bd84-6da9784ad721" />

---

## `create-intunbuntu-vm.sh`

Creates a libvirt/QEMU VM with Ubuntu 24.04 Desktop — fully automated.
Downloads the ISO if needed, remasters it, installs unattended, and boots the VM.

```
./create-intunbuntu-vm.sh --vm-name NAME --disk-pin PIN --user-password 'PASS' [options]
```

| Flag | Required | Description | Default |
|------|----------|-------------|---------|
| `--vm-name` | Yes | VM name | — |
| `--disk-pin` | Yes | LUKS encryption pin (min 6 digits) | — |
| `--user-password` | Yes | User password (min 12 chars, upper/lower/digit/special) | — |
| `--iso` | No | Ubuntu ISO path | `vm_prepare_files/ubuntu-24.04.4-desktop-amd64.iso` |
| `--config` | No | Autoinstall YAML | `autoinstall-desktop.yaml` |
| `--disk` | No | Disk size | `15G` |
| `--cpus` | No | vCPUs | `1` |
| `--memory` | No | RAM in MiB | `3072` |

```bash
./create-intunbuntu-vm.sh \
  --vm-name intune-vm1 \
  --disk-pin 345721 \
  --user-password 'M2!sQ8@vT5#LdR' \
  --cpus 2 --memory 4096
```

The installation includes `apt update` and `apt full-upgrade`.

SSH access (key auto-generated in `vm_prepare_files/`):
```bash
ssh -i vm_prepare_files/id_ed25519 ubuntu@<vm-ip>
```

---

## `use-yubikey.sh`

Hotplug a YubiKey to a running VM.

```bash
./use-yubikey.sh insert <vm-name>   # Attach YubiKey
./use-yubikey.sh remove <vm-name>   # Detach YubiKey
```

If multiple YubiKeys are connected, prompts for selection.

---

## First login

> **Important:** The "Login" keyring must exist before enrolling in Intune Portal.
>
> Check: `busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Label`
>
> Expected output: `s "Login"`
>
> If the command fails, **reboot and check again**. The keyring is typically created on the next login.
>
> If it still doesn't exist after a reboot, open Microsoft Edge — you will be prompted to create a "Login" keyring password. Enter the same password as your user login password.
>
> **Intune Portal enrollment will fail without this keyring.**

<img width="400" alt="keyring prompt" src="https://github.com/user-attachments/assets/7a535c27-fee2-4be2-8aef-7b4ee045efaf" />

---

## What's preconfigured

See [`autoinstall-desktop.yaml`](autoinstall-desktop.yaml) for full details.

- Default user: `ubuntu`
- Ubuntu Desktop Minimal install
- LUKS full-disk encryption with Clevis TPM2 auto-unlock
- SSH server with key-only auth (password auth disabled)
- Passwordless sudo for `ubuntu` user
- Password policy: min 12 chars, requires uppercase, lowercase, digit, and special character
- Disabled services: cups, cups-browsed, avahi-daemon, ModemManager, fwupd, unattended-upgrades, apport
- Quiet boot splash

### APT repositories

- [Microsoft Edge](https://packages.microsoft.com/repos/edge/) (stable)
- [Microsoft Prod](https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb)
- [Microsoft Insiders Fast](https://packages.microsoft.com/config/ubuntu/24.04/insiders-fast.list)
- [Microsoft Ubuntu Jammy Prod](https://packages.microsoft.com/ubuntu/22.04/prod) (for intune-portal)

### Preinstalled packages

- `microsoft-edge-stable`
- `microsoft-azurevpnclient`
- `intune-portal`
- `clevis`, `clevis-luks`, `clevis-tpm2`, `clevis-initramfs`, `tpm2-tools`

---

## Remote config

YAML config served at: https://intunbuntu.azurewebsites.net/

Custom LUKS PIN: `https://intunbuntu.azurewebsites.net/123321`

Validated with `ubuntu-24.04.4-desktop-amd64.iso` (noble).

---

## Guides

- [YubiKey USB passthrough to VM](yubikey-passthrough.md)
