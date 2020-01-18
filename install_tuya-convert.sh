#!/usr/bin/env bash

# Setup script
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR:LXC] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  exit $EXIT
}
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}

# Default variables
LOCALE=${1:-en_US.UTF-8}

# Prepare container OS
msg "Customizing container OS..."
echo "root:tuya" | chpasswd
sed -i "s/\(# \)\($LOCALE.*\)/\2/" /etc/locale.gen
export LANGUAGE=$LOCALE LANG=$LOCALE
locale-gen >/dev/null
cd /root

# Detect DHCP address
while [ "$(hostname -I)" = "" ]; do
  COUNT=$((${COUNT-} + 1))
  warn "Failed to grab an IP address, waiting...$COUNT"
  if [ $COUNT -eq 10 ]; then
    die "Unable to verify assigned IP address."
  fi
  sleep 1
done

# Update container OS
msg "Updating container OS..."
apt-get update >/dev/null
apt-get -qqy upgrade &>/dev/null

# Install prerequisites
msg "Installing prerequisites..."
echo "samba-common samba-common/dhcp boolean false" | debconf-set-selections
apt-get -qqy install \
  git curl network-manager net-tools samba &>/dev/null

# Clone tuya-convert
msg "Cloning tuya-convert..."
git clone --quiet https://github.com/ct-Open-Source/tuya-convert

# Configure tuya-convert
msg "Configuring tuya-convert..."
./configure_tuya-convert.sh

# Install tuya-convert
msg "Running tuya-convert/install_prereq.sh..."
cd tuya-convert
./install_prereq.sh &>/dev/null
systemctl disable dnsmasq &>/dev/null
systemctl disable mosquitto &>/dev/null

# Customize OS
msg "Customizing OS..."
cat <<EOL >> /etc/samba/smb.conf
[tuya-convert]
  path = /root/tuya-convert
  browseable = yes
  writable = yes
  public = yes
  force user = root
EOL
cat <<EOL >> /etc/issue
  ******************************
    The tuya-convert files are
    shared using samba at
    \4{eth0}
  ******************************

  Login using the following credentials
    username: root
    password: tuya

EOL
sed -i "s/^\(root\)\(.*\)\(\/bin\/bash\)$/\1\2\/root\/login.sh/" /etc/passwd

# Cleanup
msg "Cleanup..."
rm -rf /root/install_tuya-convert.sh /var/{cache,log}/* /var/lib/apt/lists/*
