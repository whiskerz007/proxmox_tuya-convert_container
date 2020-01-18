#!/usr/bin/env bash

# Setup script
set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable
trap "{ echo -e '\nTerminate'; exit 1; }" SIGINT SIGTERM

cd /root/tuya-convert/
git fetch origin >/dev/null
mapfile -t REF < <(git show-ref master | sed -e 's/^\(.*\)\(\s.*$\)/\1/')
if [ "${REF[0]}" != "${REF[1]}" ]; then
  echo -e "\n\n"\
        "There is a \e[1mnew version\e[0m of '\e[100;93mtuya-convert\e[39;49m'. Consider running the\n"\
        "script found at the following URL to ensure best possible outcome.\n\n"\
        "https://github.com/whiskerz007/proxmox_tuya-convert_container\n"
  read -n 1 -p "--Press any key to continue--"
fi
./start_flash.sh
echo "tuya-convert exited with code:$?"
