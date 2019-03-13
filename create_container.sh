#!/bin/bash

# Check for dependencies
dpkg -s iw &> /dev/null
RESULT=$?
if [ $RESULT -ne 0 ]; then
    apt update && apt install -y iw || { \
    echo -e "\n\n\nERROR: Unable to install prerequisites." && \
    exit 1
    }
fi
unset RESULT

# Verify valid storage location
LXC_STORAGE=${1:-local-lvm}
pvesm list $LXC_STORAGE >& /dev/null || { \
echo -e "\n\n\nERROR: '$LXC_STORAGE' is not a valid storage ID.\n\n\n" && \
exit 1
}

# Get WLAN interfaces capable of being passed to LXC
mapfile -t WLANS < <(ip link show | sed -n "s/.*\(wl.*\)\:.*/\1/p")
for i in "${WLANS[@]}"; do
  ip link set dev $i up >& /dev/null
  RESULT=$?
  if [ $RESULT -eq 0 ]; then
    WLANS_READY+=($i)
  fi
done
if [ ${#WLANS_READY[@]} -eq 0 ]; then
  echo -e "\n\nERROR: Unable to identify usable WiFi adapters. If the adapter is currently attached, check your drivers.\n\n"
  exit 1
fi
while true; do
  echo -e "\n\nHere are all of your available WiFi interfaces...\n"
  for i in "${!WLANS_READY[@]}"; do
    echo "$i) ${WLANS_READY[$i]}"
  done
  echo
  read -n 1 -p "Which interface would you like to use? " WLAN
  if [[ "${WLAN}" =~ ^[0-9]+$ ]] && [ ! -z ${WLANS_READY[$WLAN]} ]; then
    WLAN=${WLANS_READY[$WLAN]}
    break
  fi
done
unset RESULT
echo -e "\nUsing $WLAN..."

trap '{ echo -e "\n\nERROR: Failed to properly configure container.\nEXIT: $?\n"; exit 1; }' ERR

# Get the next guest VM/LXC ID
CTID=$(cat<<EOF | python3
import json
with open('/etc/pve/.vmlist') as vmlist:
        vmids = json.load(vmlist)
if 'ids' not in vmids:
        print(100)
else:
        last_vm = sorted(vmids['ids'].keys())[-1:][0]
        print(int(last_vm)+1)
EOF
)
echo "Next ID is $CTID"

# Download latest Debian LXC template
pveam update && \
mapfile -t DEBIANS < <(pveam available -section system | sed -n "s/.*\(debian.*\)/\1/p") && \
DEBIAN="${DEBIANS[-1]}" && \
pveam download local $DEBIAN && \
TEMPLATE="local:vztmpl/${DEBIAN}" || { \
echo -e "\n\nERROR: A problem occured while downloading the LXC template.\n\n"
exit 1
}

# Create LXC and add WLAN interface
DISK=vm-${CTID}-disk-0
ROOTFS=${LXC_STORAGE}:${DISK}
pvesm alloc $LXC_STORAGE $CTID $DISK 2G
mke2fs /dev/pve/${DISK}
pct create $CTID $TEMPLATE -arch amd64 -cores 1 -hostname tuya-convert \
    -net0 name=eth0,bridge=vmbr0,ip=dhcp,type=veth -ostype debian \
    -rootfs $ROOTFS -storage $LXC_STORAGE
cat <<EOF >> /etc/pve/lxc/${CTID}.conf
lxc.net.1.type: phys
lxc.net.1.name: ${WLAN}
lxc.net.1.link: ${WLAN}
lxc.net.1.flags: up
EOF

# Setup container for tuya-convert
trap '{ echo -e "\n\nERROR: Failed to properly configure container.\nEXIT: $?\n"; pct stop $CTID; pct destroy $CTID; exit 1; }' ERR
pct start $CTID
pct push $CTID install_tuya-convert.sh /root/install_tuya-convert.sh -perms 755
pct push $CTID login.sh /root/login.sh -perms 755
pct exec $CTID -- bash -c "cd /root; ./install_tuya-convert.sh $WLAN"
pct stop $CTID

echo -e "\n\n\n" \
    "******************************\n" \
    "* Successfully Create New CT *\n" \
    "*        CT ID is $CTID        *\n" \
    "******************************\n\n"
