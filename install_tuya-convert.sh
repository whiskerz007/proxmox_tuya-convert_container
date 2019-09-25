#!/bin/bash

WLAN=$1
LOCALE=${2:-en_US.UTF-8}
trap '{ exit $?; }' ERR

# Detect DHCP address
while [ "$(hostname -I)" = "" ]; do
    COUNT=$(($COUNT + 1))
    echo "   *-> Failed to grab an IP address, waiting...$COUNT"
    if [ $COUNT -eq 10 ]; then
        echo "ERROR: Unable to verify assigned IP address."
        exit 1
    fi
    sleep 1
done


# Set parameters for OS
echo -e "tuya\ntuya" | passwd
sed -i "s/\(# \)\($LOCALE.*\)/\2/" /etc/locale.gen
export LANGUAGE=$LOCALE LANG=$LOCALE LC_ALL=$LOCALE
locale-gen

# Install tuya-convert
apt update
apt upgrade -y
apt install -y git curl net-tools samba libssl-dev
git clone https://github.com/kueblc/tuya-convert/tree/new-api
find tuya-convert -name \*.sh -exec sed -i -e "s/sudo -E//" -e "s/sudo //" {} \;
cd tuya-convert
./install_prereq.sh
systemctl disable mosquitto
echo "Setting $WLAN interface for tuya-convert ..."
sed -i "s/^\(WLAN=\)\(.*\)/\1$WLAN/" config.txt

# Customize OS
cat <<EOL >> /etc/samba/smb.conf
[tuya-convert]
  path = /root/tuya-convert
  browseable = yes
  writable = yes
  public = yes
  force user = root
EOL
echo -e \
 " *****************************\n"\
  " The tuya-convert files are\n"\
  " shared using samba at\n"\
  " \4{eth0}\n"\
  "*****************************\n\n"\
  "Login using the following credentials\n"\
  " username: root\n"\
  " password: tuya\n\n" >> /etc/issue
sed -i "s/^\(root\)\(.*\)\(\/bin\/bash\)$/\1\2\/root\/login.sh/" /etc/passwd

rm /root/install_tuya-convert.sh
