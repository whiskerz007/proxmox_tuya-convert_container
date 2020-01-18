#!/usr/bin/env bash

# Setup script
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
trap "{ echo -e '\nTerminate'; exit 1; }" SIGINT SIGTERM

cd /root/tuya-convert/
git fetch origin >/dev/null
WORKING_COMMIT=$(git show -s --format='%h')
LATEST_COMMIT=$(git show-ref --hash=7 origin/master)
if [ "$WORKING_COMMIT" != "$LATEST_COMMIT" ]; then
  RESPONSE=$(
    whiptail --title "tuya-convert Out Of Date" --yesno --defaultno \
    "Would you like to change your current version?" \
    9 40 \
    3>&1 1>&2 2>&3
  ) && /root/commit_switcher.sh
fi
./start_flash.sh
echo "tuya-convert exited with code:$?"
