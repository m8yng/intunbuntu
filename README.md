# intunbuntu

Automatically prepare an Intune-ready Ubuntu environment.

<img width="800" height="500" alt="image" src="https://github.com/user-attachments/assets/d7b4ec3f-8058-4c82-bd84-6da9784ad721" />

## create-intunbuntu-vm.sh

Creates a libvirt/QEMU VM with Ubuntu 24.04 Desktop, fully automated via autoinstall.
Downloads the Ubuntu ISO if not present, remasters it, installs unattended, and boots the VM.

```
Usage: ./create-intunbuntu-vm.sh --vm-name NAME --disk-pin PIN --user-password 'PASS' [options]

Required:
  --vm-name NAME          VM name
  --disk-pin PIN          LUKS disk encryption pin, at least 6 digits
  --user-password 'PASS'  User password in single quotes, min 12 chars with upper/lower/digit/special

Optional:
  --iso PATH              Ubuntu ISO path (default: vm_prepare_files/ubuntu-24.04.4-desktop-amd64.iso)
  --config PATH           Autoinstall YAML (default: autoinstall-desktop.yaml)
  --disk SIZE             Disk size (default: 15G)
  --cpus N                Number of vCPUs (default: 1)
  --memory SIZE           RAM in MiB (default: 3072)
```

Example:
```bash
./create-intunbuntu-vm.sh --vm-name intune-vm1 --disk-pin 345721 --user-password 'M2!sQ8@vT5#LdR' --cpus 2 --memory 4096
```

The installation process includes `apt update` and `apt full-upgrade`.

An SSH key pair is generated in `vm_prepare_files/` for key-based access:
```bash
ssh -i vm_prepare_files/id_ed25519 ubuntu@<vm-ip>
```

---
> **Important:** Please ensure the "Login" keyring is created.
> ```shell
> $ busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Label
> ```
> If it exists, you should see the output `s "Login"`. If it is not present, the fastest way to create one is to open Microsoft Edge. You will be prompted to create a "Login" keyring password — enter the same password as your user login password. If you skip this step, Intune Portal enrollment will fail.
> <img width="800" alt="image" src="https://github.com/user-attachments/assets/7a535c27-fee2-4be2-8aef-7b4ee045efaf" />

---


## What's preconfigured

See [`autoinstall-desktop.yaml`](autoinstall-desktop.yaml) for full details.

- Default user: `ubuntu`
- Ubuntu Desktop Minimal install
- LUKS full-disk encryption with clevis TPM2 auto-unlock
- SSH server with key-only auth (password auth disabled)
- Passwordless sudo for `ubuntu` user
- Password policy: min 12 chars, requires uppercase, lowercase, digit, and special character
- Disabled services: cups, avahi-daemon, ModemManager, fwupd, unattended-upgrades, apport
- Quiet boot splash

### APT repositories

- [Microsoft Edge](https://packages.microsoft.com/repos/edge/) (stable)
- [Microsoft Prod](https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb)
- [Microsoft Insiders Fast](https://packages.microsoft.com/config/ubuntu/24.04/insiders-fast.list)
- [Microsoft Ubuntu Jammy Prod](https://packages.microsoft.com/ubuntu/22.04/prod) (for intune-portal)

## What's preinstalled

- `microsoft-edge-stable`
- `microsoft-azurevpnclient`
- `intune-portal`
- `clevis`, `clevis-luks`, `clevis-tpm2`, `clevis-initramfs`, `tpm2-tools`

## For portable use

YAML config directly served at: https://intunbuntu.azurewebsites.net/

Custom LUKS PIN (6-digit numeric): `https://intunbuntu.azurewebsites.net/123321`

Validated with `ubuntu-24.04.4-desktop-amd64.iso` (noble).
