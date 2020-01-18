#!/usr/bin/env bash

# Setup script
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT

function error_exit() {
  REASON=$1
  MSG="\e[91mERROR: \e[93m$EXIT@"
  if [ -z "$REASON" ]; then
    MSG="$MSG$LINE:"
    REASON="A failure has occured."
  else
    MSG="$MSG`echo $(( $LINE - 1 ))`:"
  fi
  echo -e "$MSG \e[97m$REASON\e[39m\e[49m"
  exit $EXIT
}
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

# Download setup and login script
GITHUB=https://github.com/
GITHUB_REPO=whiskerz007/proxmox_tuya-convert_container
GITHUB_REPO_BRANCH=master
URL=${GITHUB}${GITHUB_REPO}/raw/${GITHUB_REPO_BRANCH}
wget -qL ${URL}/{install_tuya-convert,login}.sh

# Check for dependencies
which iw >/dev/null || (
  apt update
  apt install -y iw ||
    die "Unable to install prerequisites."
)

# Verify valid storage location
LXC_STORAGE=${1:-local-lvm}
pvesm list $LXC_STORAGE >&/dev/null ||
  die "'$LXC_STORAGE' is not a valid storage ID.\n\n\n" 
pvesm status -content images -storage $LXC_STORAGE >&/dev/null ||
  die "'$LXC_STORAGE' does not allow 'Disk image' to be stored."

# Get WLAN interfaces capable of being passed to LXC
FAILED_SUPPORT=false
mapfile -t WLANS < <(
  iw dev | \
  sed -n 's/phy#\([0-9]\)*/\1/p; s/[[:space:]]Interface \(.*\)/\1/p'
)
for i in $(seq 0 2 $((${#WLANS[@]}-1)));do
  FEATURES=( $(
    iw phy${WLANS[i]} info | \
    sed -n '/\bSupported interface modes:/,/\bBand/{/Supported/d;/Band/d;s/\( \)*\* //;p;}'
  ) )
  SUPPORTED=false
  for feature in "${FEATURES[@]}"; do
    if [ "AP" == $feature ]; then
      SUPPORTED=true
      WLANS_READY+=(${WLANS[i+1]})
    fi
  done
  if ! $SUPPORTED; then
    FAILED_SUPPORT=true
  fi
done
if [ ${#WLANS_READY[@]} -eq 0 ] && $FAILED_SUPPORT; then
  die "One or more of the detected WiFi adapters do not support 'AP mode'. Try another adapter."
elif [ ${#WLANS_READY[@]} -eq 0 ]; then
  die "Unable to identify usable WiFi adapters. If the adapter is currently attached, check your drivers."
elif [ ${#WLANS_READY[@]} -eq 1 ]; then
  WLAN=${WLANS_READY[0]}
else
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
fi
echo -e "\nUsing $WLAN..."

# Get the next guest VM/LXC ID
CTID=$(pvesh get /cluster/nextid)
echo "Next ID is $CTID"

# Download latest Debian LXC template
pveam update
OSTYPE=debian
OSVERSION=${OSTYPE}-10
mapfile -t TEMPLATES < <(
  pveam available -section system | \
  sed -n "s/.*\($OSVERSION.*\)/\1/p" | \
  sort -t - -k 2 -V
)
TEMPLATE="${TEMPLATES[-1]}"
pveam download local $TEMPLATE ||
  die "A problem occured while downloading the LXC template."

# Create variables for container disk
STORAGE_TYPE=`pvesm status -storage $LXC_STORAGE | awk 'NR>1 {print $2}'`
if [ "$STORAGE_TYPE" = "dir" ]; then
    DISK_EXT=".raw"
    DISK_REF="$CTID/"
elif [ "$STORAGE_TYPE" = "zfspool" ]; then
    DISK_PREFIX="subvol"
    DISK_FORMAT="subvol"
fi
DISK=${DISK_PREFIX:-vm}-${CTID}-disk-0${DISK_EXT-}
ROOTFS=${LXC_STORAGE}:${DISK_REF-}${DISK}

# Create LXC
pvesm alloc $LXC_STORAGE $CTID $DISK 2G --format ${DISK_FORMAT:-raw}
if [ "$STORAGE_TYPE" != "zfspool" ]; then
  mkfs.ext4 $(pvesm path $ROOTFS)
fi
ARCH=$(dpkg --print-architecture)
HOSTNAME=tuya-convert
TEMPLATE_STRING="local:vztmpl/${TEMPLATE}"
pct create $CTID $TEMPLATE_STRING -arch $ARCH -cores 1 -hostname $HOSTNAME \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp -ostype $OSTYPE \
  -rootfs $ROOTFS -storage $LXC_STORAGE

# Pass network interface to LXC
cat <<EOF >> /etc/pve/lxc/${CTID}.conf
lxc.net.1.type: phys
lxc.net.1.name: ${WLAN}
lxc.net.1.link: ${WLAN}
lxc.net.1.flags: up
EOF

# Setup container for tuya-convert
pct start $CTID
pct push $CTID install_tuya-convert.sh /root/install_tuya-convert.sh -perms 755
pct push $CTID login.sh /root/login.sh -perms 755
pct exec $CTID /root/install_tuya-convert.sh $WLAN
pct stop $CTID

echo -e "\n\n\n" \
    "******************************\n" \
    "* Successfully Create New CT *\n" \
    "*        CT ID is $CTID        *\n" \
    "******************************\n\n"
