# intunbuntu

Autoinstall config and helper scripts to build an Ubuntu Desktop VM for Intune enrollment.

<img width="480" alt="intunbuntu desktop" src="https://github.com/user-attachments/assets/d7b4ec3f-8058-4c82-bd84-6da9784ad721" />

## Overview

The script downloads the Ubuntu ISO, remasters it with the
[autoinstall YAML](autoinstall-desktop.yaml), and boots the VM. Intune
Portal, Edge, LUKS+TPM2 auto-unlock, and smart card support are set up
during install.

## Added on top of stock Ubuntu

| Area | Content |
|---|---|
| Install | Unattended autoinstall |
| Intune stack | `intune-portal`, `microsoft-edge-stable` |
| Disk encryption | LUKS + `clevis-tpm2` auto-unlock |
| Smart card | `opensc`, `pcscd`, `yubikey-manager`, polkit rule for `pcscd` access |
| VPN | `microsoft-azurevpnclient`, `openvpn3-client` |
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

- [Gotchas](Notes/gotchas.md) — login keyring, smart card polkit rule, host pcscd conflict
- [YubiKey USB passthrough to VM](Notes/yubikey-passthrough.md) — manual XML flow and troubleshooting

## Remote autoinstall config

Served from `https://intunbuntu.azurewebsites.net/`. A custom LUKS PIN can
be passed in the path, e.g. `https://intunbuntu.azurewebsites.net/123321`.
