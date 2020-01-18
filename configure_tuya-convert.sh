#!/usr/bin/env bash

# Setup script
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable

cd /root/tuya-convert
find ./ -name \*.sh -exec sed -i -e "s/sudo \(-\S\+ \)*//" {} \;

WLAN=$(iw dev | sed -n 's/[[:space:]]Interface \(.*\)/\1/p')
sed -i "s/^\(WLAN=\)\(.*\)/\1$WLAN/" config.txt
