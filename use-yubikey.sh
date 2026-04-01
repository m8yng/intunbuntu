#!/bin/bash
#
# use-yubikey.sh - Insert/remove YubiKey to/from a VM
#
# Usage:
#   use-yubikey.sh insert <vm-name>
#   use-yubikey.sh remove <vm-name>
#

set -e

LIBVIRT_URI="qemu:///system"

die() { echo "Error: $*" >&2; exit 1; }

# Get list of YubiKeys on host: "bus:device vendor:product serial"
get_yubikeys() {
    lsusb | grep -i "yubico" | while read -r line; do
        bus=$(echo "$line" | awk '{print $2}')
        dev=$(echo "$line" | awk '{print $4}' | tr -d ':')
        vid_pid=$(echo "$line" | awk '{print $6}')
        vid=$(echo "$vid_pid" | cut -d: -f1)
        pid=$(echo "$vid_pid" | cut -d: -f2)
        
        # Try to get serial via ykman (may need permissions)
        serial=$(ykman --device "$bus:$dev" info 2>/dev/null | grep "Serial" | awk '{print $3}' || echo "unknown")
        
        echo "$bus $dev $vid $pid $serial"
    done
}

select_yubikey() {
    local keys
    keys=$(get_yubikeys)
    
    if [ -z "$keys" ]; then
        die "No YubiKey found on host"
    fi
    
    local count
    count=$(echo "$keys" | wc -l)
    
    if [ "$count" -eq 1 ]; then
        echo "$keys"
        return
    fi
    
    # Multiple keys - show warning and options
    echo "Warning: Multiple YubiKeys detected!" >&2
    echo "" >&2
    
    local i=1
    while IFS= read -r key; do
        local serial=$(echo "$key" | awk '{print $5}')
        local bus=$(echo "$key" | awk '{print $1}')
        local dev=$(echo "$key" | awk '{print $2}')
        echo "  [$i] Serial: $serial (Bus $bus, Device $dev)" >&2
        i=$((i + 1))
    done <<< "$keys"
    
    echo "" >&2
    read -p "Select YubiKey [1-$count]: " choice >&2
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
        die "Invalid selection"
    fi
    
    echo "$keys" | sed -n "${choice}p"
}

create_usb_xml() {
    local vid="$1"
    local pid="$2"
    
    cat <<EOF
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <vendor id='0x${vid}'/>
    <product id='0x${pid}'/>
  </source>
</hostdev>
EOF
}

cmd_insert() {
    local vm="$1"
    [ -z "$vm" ] && die "Usage: yubikey-hotplug insert <vm-name>"
    
    # Check VM is running
    virsh -c "$LIBVIRT_URI" domstate "$vm" 2>/dev/null | grep -q "running" || \
        die "VM '$vm' is not running"
    
    local key
    key=$(select_yubikey)
    
    local vid=$(echo "$key" | awk '{print $3}')
    local pid=$(echo "$key" | awk '{print $4}')
    local serial=$(echo "$key" | awk '{print $5}')
    
    echo "Inserting YubiKey (serial: $serial) to VM '$vm'..."
    
    local xml
    xml=$(create_usb_xml "$vid" "$pid")
    
    echo "$xml" | virsh -c "$LIBVIRT_URI" attach-device "$vm" /dev/stdin
    
    echo "Done. YubiKey attached to '$vm'"
}

cmd_remove() {
    local vm="$1"
    [ -z "$vm" ] && die "Usage: yubikey-hotplug remove <vm-name>"
    
    # Check VM is running
    virsh -c "$LIBVIRT_URI" domstate "$vm" 2>/dev/null | grep -q "running" || \
        die "VM '$vm' is not running"
    
    # Find YubiKey attached to VM
    local vid pid
    vid=$(virsh -c "$LIBVIRT_URI" dumpxml "$vm" | grep -A2 "vendor id='0x1050'" | grep "vendor" | sed "s/.*id='0x\([^']*\)'.*/\1/")
    
    if [ -z "$vid" ]; then
        die "No YubiKey found attached to VM '$vm'"
    fi
    
    pid=$(virsh -c "$LIBVIRT_URI" dumpxml "$vm" | grep -A2 "vendor id='0x1050'" | grep "product" | sed "s/.*id='0x\([^']*\)'.*/\1/")
    
    echo "Removing YubiKey from VM '$vm'..."
    
    local xml
    xml=$(create_usb_xml "$vid" "$pid")
    
    echo "$xml" | virsh -c "$LIBVIRT_URI" detach-device "$vm" /dev/stdin
    
    echo "Done. YubiKey removed from '$vm'"
}

# Main
case "${1:-}" in
    insert)
        cmd_insert "$2"
        ;;
    remove)
        cmd_remove "$2"
        ;;
    *)
        echo "Usage: use-yubikey.sh <insert|remove> <vm-name>"
        echo ""
        echo "Commands:"
        echo "  insert <vm>  - Attach YubiKey to running VM"
        echo "  remove <vm>  - Detach YubiKey from running VM"
        exit 1
        ;;
esac
