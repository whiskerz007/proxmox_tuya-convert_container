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
  [ ! -z ${CTID-} ] && cleanup_failed
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
function cleanup_failed() {
  if [ ! -z ${MOUNT+x} ]; then
    pct unmount $CTID
  fi
  if $(pct status $CTID &>/dev/null); then
    if [ "$(pct status $CTID | awk '{print $2}')" == "running" ]; then
      pct stop $CTID
    fi
    pct destroy $CTID
  elif [ "$(pvesm list $STORAGE --vmid $CTID)" != "" ]; then
    pvesm free $ROOTFS
  fi
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
wget -qL ${URL}/{commit_switcher,configure_tuya-convert,install_tuya-convert,login}.sh

# Check for dependencies
which iw >/dev/null || (
  apt-get update >/dev/null
  apt-get -qqy install iw &>/dev/null ||
    die "Unable to install prerequisites."
)

# Generate graphical menu for storage location
while read -r line; do
  TAG=$(echo $line | awk '{print $1}')
  TYPE=$(echo $line | awk '{printf "%-10s", $2}')
  FREE=$(
    echo $line | \
    numfmt --field 4-6 --from-unit=K --to=iec --format %.2f | \
    awk '{printf( "%9sB", $6)}'
  )
  ITEM="  Type: $TYPE Free: $FREE "
  OFFSET=2
  if [[ $((${#ITEM} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
    MSG_MAX_LENGTH=$((${#ITEM} + $OFFSET))
  fi
  STORAGE_MENU+=( "$TAG" "$ITEM" "OFF" )
done < <(pvesm status -content rootdir | awk 'NR>1')
if [ $((${#STORAGE_MENU[@]}/3)) -eq 0 ]; then
  warn "'Container' needs to be selected for at least one storage location."
  die "Unable to detect valid storage location."
elif [ $((${#STORAGE_MENU[@]}/3)) -eq 1 ]; then
  STORAGE=${STORAGE_MENU[0]}
else
  while [ -z "${STORAGE:+x}" ]; do
    STORAGE=$(
      whiptail --title "Storage Pools" --radiolist \
      "Which storage pool would you like to use?\n\n" \
      15 $(($MSG_MAX_LENGTH + 23)) 6 "${STORAGE_MENU[@]}" 3>&1 1>&2 2>&3
    ) || exit
  done
fi
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
if [ -z ${WLANS_READY+x} ] && $FAILED_SUPPORT; then
  die "One or more of the detected WiFi adapters do not support 'AP mode'. Try another adapter."
elif [ -z ${WLANS_READY+x} ]; then
  die "Unable to identify usable WiFi adapters. If the adapter is currently attached, check your drivers."
elif [ ${#WLANS_READY[@]} -eq 1 ]; then
  WLAN=${WLANS_READY[0]}
else
  for interface in "${WLANS_READY[@]}"; do
    CMD="udevadm info --query=property /sys/class/net/$interface"
    MAKE=$($CMD | sed -n -e 's/ID_VENDOR_FROM_DATABASE=//p')
    MODEL=$($CMD | sed -n -e 's/ID_MODEL_FROM_DATABASE=//p')
    OFFSET=2
    if [[ $((${#MAKE} + ${#MODEL} + $OFFSET)) -gt ${MSG_MAX_LENGTH:-} ]]; then
      MSG_MAX_LENGTH=$((${#MAKE} + ${#MODEL} + $OFFSET))
    fi
    WLAN_MENU+=( $interface "$MAKE $MODEL " "off")
  done
  while [ -z "${WLAN:+x}" ]; do
    WLAN=$(
      whiptail --title "WLAN Interfaces" --radiolist --notags \
      "Which WLAN interface would you like to use for the container?\n\n" \
      15 $(($MSG_MAX_LENGTH + 14)) 6 "${WLAN_MENU[@]}" 3>&1 1>&2 2>&3
    ) || exit
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

# Set container timezone to match host
MOUNT=$(pct mount $CTID | cut -d"'" -f 2)
ln -fs $(readlink /etc/localtime) ${MOUNT}/etc/localtime
pct unmount $CTID && unset MOUNT

# Setup container for tuya-convert
msg "Starting LXC container..."
pct start $CTID
pct push $CTID commit_switcher.sh /root/commit_switcher.sh -perms 755
pct push $CTID configure_tuya-convert.sh /root/configure_tuya-convert.sh -perms 755
pct push $CTID install_tuya-convert.sh /root/install_tuya-convert.sh -perms 755
pct push $CTID login.sh /root/login.sh -perms 755
pct exec $CTID /root/install_tuya-convert.sh $LANG
pct stop $CTID

info "Successfully created tuya-convert LXC to $CTID."
