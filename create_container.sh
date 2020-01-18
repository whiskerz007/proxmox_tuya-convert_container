#!/usr/bin/env bash

# Setup script
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}
function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG $REASON"
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
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
  apt-get update >/dev/null
  apt-get -qqy install iw &>/dev/null ||
    die "Unable to install prerequisites."
)

# Verify valid storage location
STORAGE=${1:-local-lvm}
pvesm list $STORAGE >&/dev/null ||
  die "'$STORAGE' is not a valid storage ID.\n\n\n" 
pvesm status -content images -storage $STORAGE >&/dev/null ||
  die "'$STORAGE' does not allow 'Disk image' to be stored."
info "Using '$STORAGE' for storage location."

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
info "Using '$WLAN' wireless interface."

# Get the next guest VM/LXC ID
CTID=$(pvesh get /cluster/nextid)
info "Container ID is $CTID."

# Download latest Debian LXC template
msg "Updating LXC template list..."
pveam update >/dev/null
msg "Downloading LXC template..."
OSTYPE=debian
OSVERSION=${OSTYPE}-10
mapfile -t TEMPLATES < <(
  pveam available -section system | \
  sed -n "s/.*\($OSVERSION.*\)/\1/p" | \
  sort -t - -k 2 -V
)
TEMPLATE="${TEMPLATES[-1]}"
pveam download local $TEMPLATE >/dev/null ||
  die "A problem occured while downloading the LXC template."

# Create variables for container disk
STORAGE_TYPE=$(pvesm status -storage $STORAGE | awk 'NR>1 {print $2}')
case $STORAGE_TYPE in
  dir|nfs)
    DISK_EXT=".raw"
    DISK_REF="$CTID/"
    ;;
  zfspool)
    DISK_PREFIX="subvol"
    DISK_FORMAT="subvol"
    ;;
esac
DISK=${DISK_PREFIX:-vm}-${CTID}-disk-0${DISK_EXT-}
ROOTFS=${STORAGE}:${DISK_REF-}${DISK}

# Create LXC
msg "Creating LXC container..."
pvesm alloc $STORAGE $CTID $DISK 2G --format ${DISK_FORMAT:-raw} >/dev/null
if [ "$STORAGE_TYPE" != "zfspool" ]; then
  mkfs.ext4 $(pvesm path $ROOTFS) &>/dev/null
fi
ARCH=$(dpkg --print-architecture)
HOSTNAME=tuya-convert
TEMPLATE_STRING="local:vztmpl/${TEMPLATE}"
pct create $CTID $TEMPLATE_STRING -arch $ARCH -cores 1 -hostname $HOSTNAME \
  -net0 name=eth0,bridge=vmbr0,ip=dhcp -ostype $OSTYPE \
  -rootfs $ROOTFS -storage $STORAGE >/dev/null

# Pass network interface to LXC
cat <<EOF >> /etc/pve/lxc/${CTID}.conf
lxc.net.1.type: phys
lxc.net.1.name: ${WLAN}
lxc.net.1.link: ${WLAN}
lxc.net.1.flags: up
EOF

# Setup container for tuya-convert
msg "Starting LXC container..."
pct start $CTID
pct push $CTID install_tuya-convert.sh /root/install_tuya-convert.sh -perms 755
pct push $CTID login.sh /root/login.sh -perms 755
pct exec $CTID /root/install_tuya-convert.sh $WLAN
pct stop $CTID

info "Successfully created tuya-convert LXC to $CTID."
