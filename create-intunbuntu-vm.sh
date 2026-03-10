#!/usr/bin/env bash
#
# Create a libvirt VM for Ubuntu 24.04.4 with autoinstall.
#
# Usage:
#   ./create-intunbuntu-vm.sh --vm-name NAME --disk-pin PIN --user-password 'PASS' [options]
#
# Required:
#   --vm-name NAME       VM name
#   --disk-pin PIN       LUKS disk encryption pin, at least 6 digits
#   --user-password 'PASS' User password in single quotes, min 12 chars with upper/lower/digit/special
#
# Optional:
#   --iso PATH          Ubuntu ISO path (default: vm_prepare_files/ubuntu-24.04.4-desktop-amd64.iso)
#   --config PATH       Autoinstall YAML (default: autoinstall-desktop.yaml)
#   --disk SIZE         Disk size (default: 15G)
#   --cpus N            Number of vCPUs (default: 1)
#   --memory SIZE       RAM in MiB (default: 3072)
#
# Examples:
#   ./create-intunbuntu-vm.sh --vm-name test1 --disk-pin 123456 --user-password 'tV9#Kp6!Zx3@Wd'
#   ./create-intunbuntu-vm.sh --vm-name test2 --disk-pin 111111 --user-password 'Zp3@F7!kL9#rWx' --cpus 2 --memory 4096

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONN="qemu:///system"
IMG_DIR="/var/lib/libvirt/images"
NVRAM_TEMPLATE="/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.ms.fd"
ISO_DOWNLOAD_URL="https://releases.ubuntu.com/noble"
PREPARE_DIR="${SCRIPT_DIR}/vm_prepare_files"

UBUNTU_ISO="${PREPARE_DIR}/ubuntu-24.04.4-desktop-amd64.iso"
LUKS_PIN=""
USER_PASSWORD=""
VM_NAME=""
DISK_SIZE="15G"
VCPUS=1
MEMORY_MIB=3072
LOCAL_CONFIG="${SCRIPT_DIR}/autoinstall-desktop.yaml"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm-name)  VM_NAME="$2";       shift 2 ;;
        --iso)      UBUNTU_ISO="$2";    shift 2 ;;
        --disk-pin) LUKS_PIN="$2";      shift 2 ;;
        --user-password) USER_PASSWORD="$2"; shift 2 ;;
        --config)   LOCAL_CONFIG="$2";  shift 2 ;;
        --disk)     DISK_SIZE="$2";     shift 2 ;;
        --cpus)     VCPUS="$2";         shift 2 ;;
        --memory)   MEMORY_MIB="$2";    shift 2 ;;
        *) echo "ERROR: Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$VM_NAME" ]]; then
    echo "Usage: $0 --vm-name NAME --disk-pin PIN --user-password 'PASS' [options]"
    exit 1
fi

if [[ -z "$LUKS_PIN" ]]; then
    echo "ERROR: LUKS disk pin required. Use --disk-pin PIN"
    echo "  PIN must be numeric (e.g. 123456)"
    exit 1
fi

if [[ ! "$LUKS_PIN" =~ ^[0-9]{6,}$ ]]; then
    echo "ERROR: --disk-pin must be at least 6 digits (e.g. 123456)"
    exit 1
fi

if [[ -z "$USER_PASSWORD" ]]; then
    echo "ERROR: User password required. Use --user-password 'PASS'"
    echo "  At least 12 characters, must include uppercase, lowercase, digit, and special character"
    echo "  Wrap in single quotes to prevent shell escaping: --user-password '!MyP@ss1234'"
    exit 1
fi

if [[ ${#USER_PASSWORD} -lt 12 ]]; then
    echo "ERROR: Password must be at least 12 characters (got ${#USER_PASSWORD})"
    exit 1
fi
if [[ ! "$USER_PASSWORD" =~ [a-z] ]]; then
    echo "ERROR: Password must contain at least one lowercase letter"
    exit 1
fi
if [[ ! "$USER_PASSWORD" =~ [A-Z] ]]; then
    echo "ERROR: Password must contain at least one uppercase letter"
    exit 1
fi
if [[ ! "$USER_PASSWORD" =~ [0-9] ]]; then
    echo "ERROR: Password must contain at least one digit"
    exit 1
fi
if [[ ! "$USER_PASSWORD" =~ [^a-zA-Z0-9] ]]; then
    echo "ERROR: Password must contain at least one special character"
    exit 1
fi

MEMORY_KIB=$((MEMORY_MIB * 1024))
DISK_PATH="${IMG_DIR}/${VM_NAME}.qcow2"
ISO_BASENAME="$(basename "$UBUNTU_ISO" .iso)"
PATCHED_ISO="${PREPARE_DIR}/${ISO_BASENAME}-autoinstall-patched.iso"
AUTOINSTALL_ISO="${PREPARE_DIR}/autoinstall.iso"

check_dependencies() {
    local cmds=(virsh qemu-system-x86_64 swtpm xorriso curl openssl)
    local missing=()

    for cmd in "${cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required commands: ${missing[*]}"
        exit 1
    fi
}

check_environment() {
    if command -v kvm-ok &>/dev/null; then
        if ! kvm-ok &>/dev/null; then
            echo "WARNING: kvm-ok reports KVM is not available. VM will be slow (TCG fallback)."
        fi
    elif [[ ! -r /dev/kvm ]]; then
        echo "WARNING: /dev/kvm not accessible. KVM may not be available."
    fi

    if ! virsh -c "$CONN" version &>/dev/null; then
        echo "ERROR: Cannot connect to $CONN. Is libvirtd running?"
        exit 1
    fi

    if ! virsh -c "$CONN" net-info default &>/dev/null; then
        echo "ERROR: libvirt 'default' network not found."
        echo "  Start it: virsh -c $CONN net-start default"
        exit 1
    fi
}

check_preflight() {
    if virsh -c "$CONN" dominfo "$VM_NAME" &>/dev/null; then
        echo "ERROR: VM '$VM_NAME' already exists. Remove it first:"
        echo "  virsh -c $CONN destroy $VM_NAME 2>/dev/null"
        echo "  virsh -c $CONN undefine $VM_NAME --nvram"
        exit 1
    fi

    local required_files=("$UBUNTU_ISO" "$NVRAM_TEMPLATE" "$OVMF_CODE" "$LOCAL_CONFIG")
    for f in "${required_files[@]}"; do
        if [[ ! -f "$f" ]]; then
            echo "ERROR: Required file not found: $f"
            exit 1
        fi
    done
}

download_iso() {
    if [[ -f "$UBUNTU_ISO" ]]; then
        return
    fi

    local url="${ISO_DOWNLOAD_URL}/$(basename "$UBUNTU_ISO")"
    echo "ISO not found: $UBUNTU_ISO"
    echo "Downloading from $url ..."
    mkdir -p "$(dirname "$UBUNTU_ISO")"

    if ! curl --location --fail --progress-bar "$url" -o "$UBUNTU_ISO"; then
        rm -f "$UBUNTU_ISO"
        echo "ERROR: Failed to download ISO from $url"
        exit 1
    fi
    echo "Downloaded: $UBUNTU_ISO"
}

prepare_ssh_key() {
    local key_path="${PREPARE_DIR}/id_ed25519"

    if [[ -f "${key_path}.pub" ]]; then
        SSH_PUBLIC_KEY=$(cat "${key_path}.pub")
        echo "Using existing SSH key: ${key_path}.pub"
    else
        ssh-keygen -t ed25519 -f "$key_path" -N "" -C "intunbuntu-vm"
        SSH_PUBLIC_KEY=$(cat "${key_path}.pub")
        echo "Generated SSH key: ${key_path}.pub"
    fi
}

prepare_autoinstall() {
    cp "$LOCAL_CONFIG" "$TMPDIR/user-data"
    echo "Using config: $LOCAL_CONFIG"

    if ! grep -q 'autoinstall' "$TMPDIR/user-data"; then
        echo "ERROR: Config is not a valid autoinstall YAML"
        head -5 "$TMPDIR/user-data"
        exit 1
    fi

    local password_hash
    password_hash=$(openssl passwd -6 "$USER_PASSWORD")
    sed -i "s|__USER_PASSWORD_HASH__|${password_hash}|g" "$TMPDIR/user-data"
    sed -i "s|__DISK_PIN__|${LUKS_PIN}|g" "$TMPDIR/user-data"
    sed -i "s|__USER_PASSWORD__|${USER_PASSWORD}|g" "$TMPDIR/user-data"
    sed -i "s|__VM_NAME__|${VM_NAME}|g" "$TMPDIR/user-data"
    sed -i "s|__SSH_PUBLIC_KEY__|${SSH_PUBLIC_KEY}|g" "$TMPDIR/user-data"

    echo "Substituted: password, disk pin, hostname, SSH key."
}

remaster_iso() {
    echo "Remastering ISO..."

    xorriso -osirrox on -indev "$UBUNTU_ISO" -extract / "$TMPDIR/iso" 2>/dev/null
    chmod -R u+w "$TMPDIR/iso/"

    # Strip cloud-config/bootcmd lines for the ISO-embedded autoinstall.yaml
    grep -v '^#cloud-config' "$TMPDIR/user-data" \
        | grep -v '^bootcmd:' \
        | grep -v '^\s*- echo.*cmdline' \
        | grep -v '^\s*- mount.*cmdline' \
        > "$TMPDIR/iso/autoinstall.yaml"

    # Patch GRUB: add 'autoinstall' to kernel cmdline to bypass confirmation
    local grub_files=("$TMPDIR/iso/boot/grub/grub.cfg" "$TMPDIR/iso/boot/grub/loopback.cfg")
    for f in "${grub_files[@]}"; do
        if [[ -f "$f" ]]; then
            sed -i 's|linux\t/casper/vmlinuz|linux\t/casper/vmlinuz autoinstall|g' "$f"
        fi
    done

    rm -f "$PATCHED_ISO"
    xorriso -as mkisofs \
        -r -V 'Ubuntu 24.04.4 LTS amd64' \
        --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:"$UBUNTU_ISO" \
        --protective-msdos-label \
        -partition_cyl_align off \
        -partition_offset 16 \
        --mbr-force-bootable \
        -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b --interval:local_fs:12988432d-12998591d::"$UBUNTU_ISO" \
        -appended_part_as_gpt \
        -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
        -c '/boot.catalog' \
        -b '/boot/grub/i386-pc/eltorito.img' \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --grub2-boot-info \
        -eltorito-alt-boot \
        -e '--interval:appended_partition_2_start_3247108s_size_10160d:all::' \
        -no-emul-boot \
        -boot-load-size 10160 \
        -o "$PATCHED_ISO" \
        "$TMPDIR/iso" 2>/dev/null

    echo "Patched ISO: $PATCHED_ISO"
}

build_cidata_iso() {
    mkdir -p "$TMPDIR/cidata"

    if ! head -1 "$TMPDIR/user-data" | grep -q '#cloud-config'; then
        sed -i '1i #cloud-config' "$TMPDIR/user-data"
    fi
    cp "$TMPDIR/user-data" "$TMPDIR/cidata/user-data"
    touch "$TMPDIR/cidata/meta-data"
    grep -v '^#cloud-config' "$TMPDIR/user-data" > "$TMPDIR/cidata/autoinstall.yaml"

    rm -f "$AUTOINSTALL_ISO"
    xorriso -as mkisofs \
        -volid CIDATA \
        -joliet -rock \
        -o "$AUTOINSTALL_ISO" \
        "$TMPDIR/cidata/" 2>/dev/null

    echo "CIDATA ISO: $AUTOINSTALL_ISO"
}

create_resources() {
    echo "Creating VM: $VM_NAME (disk: $DISK_SIZE, cpus: $VCPUS, ram: ${MEMORY_MIB}M)"
    virsh -c "$CONN" vol-create-as default "${VM_NAME}.qcow2" "$DISK_SIZE" --format qcow2
}

define_vm() {
    cat <<EOF | virsh -c "$CONN" define /dev/stdin
<domain type='kvm'>
  <name>${VM_NAME}</name>
  <metadata>
    <libosinfo:libosinfo xmlns:libosinfo="http://libosinfo.org/xmlns/libvirt/domain/1.0">
      <libosinfo:os id="http://ubuntu.com/ubuntu/24.04"/>
    </libosinfo:libosinfo>
  </metadata>

  <memory unit='KiB'>${MEMORY_KIB}</memory>
  <vcpu placement='static'>${VCPUS}</vcpu>
  <cpu mode='host-passthrough' check='none' migratable='on'/>

  <os firmware='efi'>
    <type arch='x86_64' machine='pc-q35-noble'>hvm</type>
    <firmware>
      <feature enabled='yes' name='enrolled-keys'/>
      <feature enabled='yes' name='secure-boot'/>
    </firmware>
    <loader readonly='yes' secure='yes' type='pflash'>${OVMF_CODE}</loader>
    <nvram template='${NVRAM_TEMPLATE}'/>
    <boot dev='cdrom'/>
    <boot dev='hd'/>
  </os>

  <features>
    <acpi/>
    <apic/>
    <smm state='on'/>
  </features>

  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' discard='unmap'/>
      <source file='${DISK_PATH}'/>
      <target dev='vda' bus='virtio'/>
    </disk>

    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${PATCHED_ISO}'/>
      <target dev='sda' bus='sata'/>
      <readonly/>
    </disk>

    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='${AUTOINSTALL_ISO}'/>
      <target dev='sdb' bus='sata'/>
      <readonly/>
    </disk>

    <interface type='network'>
      <source network='default'/>
      <model type='virtio'/>
    </interface>

    <graphics type='spice' autoport='yes'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>

    <video>
      <model type='virtio' heads='1' primary='yes'/>
    </video>

    <sound model='ich9'/>
    <audio id='1' type='spice'/>

    <channel type='unix'>
      <target type='virtio' name='org.qemu.guest_agent.0'/>
    </channel>

    <!-- TPM 2.0 required for clevis auto-unlock and Secure Boot -->
    <tpm model='tpm-tis'>
      <backend type='emulator' version='2.0'/>
    </tpm>

    <rng model='virtio'>
      <backend model='random'>/dev/urandom</backend>
    </rng>
  </devices>
</domain>
EOF
}

print_summary() {
    echo ""
    echo "VM '$VM_NAME' created successfully."
    echo ""
    echo "  Disk:     $DISK_PATH ($DISK_SIZE)"
    echo "  CPUs:     $VCPUS"
    echo "  RAM:      ${MEMORY_MIB}M"
    echo "  Disk pin: $LUKS_PIN"
    echo "  Password: $USER_PASSWORD"
    echo "  ISO:      $PATCHED_ISO"
    echo ""
}

install_and_boot() {
    echo "Starting installation..."
    virsh -c "$CONN" start "$VM_NAME"

    local start_time
    start_time=$(date +%s)
    echo "Waiting for install to complete (VM will shut off when done)..."
    echo "  You can use virt-manager to monitor the VM."
    while true; do
        local state
        state=$(virsh -c "$CONN" domstate "$VM_NAME" 2>/dev/null)
        if [[ "$state" != "running" ]]; then
            break
        fi
        sleep 30
    done

    local end_time duration mins secs
    end_time=$(date +%s)
    duration=$(( end_time - start_time ))
    mins=$(( duration / 60 ))
    secs=$(( duration % 60 ))
    echo "Installation complete in ${mins}m ${secs}s."

    virsh -c "$CONN" change-media "$VM_NAME" sda --eject 2>/dev/null
    virsh -c "$CONN" change-media "$VM_NAME" sdb --eject 2>/dev/null

    echo "Booting from disk..."
    virsh -c "$CONN" start "$VM_NAME"
}

print_commands() {
    echo ""
    echo "VM '$VM_NAME' is ready."
    echo ""
    echo "Commands:"
    echo "  Console:  virt-manager --connect $CONN --show-domain-console $VM_NAME"
    echo "  SSH:      ssh -i ${PREPARE_DIR}/id_ed25519 ubuntu@\$(virsh -c $CONN domifaddr $VM_NAME | awk '/ipv4/{print \$4}' | cut -d/ -f1)"
    echo "  Destroy:  virsh -c $CONN destroy $VM_NAME"
    echo "  Remove:   virsh -c $CONN destroy $VM_NAME 2>/dev/null; virsh -c $CONN undefine $VM_NAME --nvram"
    echo "            sudo rm -f $DISK_PATH"
}

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$PREPARE_DIR"

check_dependencies
check_environment
download_iso
UBUNTU_ISO="$(realpath "$UBUNTU_ISO")"
check_preflight
prepare_ssh_key
prepare_autoinstall
remaster_iso
build_cidata_iso
create_resources
define_vm
print_summary
install_and_boot
print_commands
