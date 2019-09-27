#!/bin/bash

trap "{ echo -e '\nTerminate'; ./stop_flash.sh; exit 1; }" SIGINT SIGTERM

cd /root/tuya-convert/
git fetch origin >/dev/null
mapfile -t REF < <(git show-ref master | sed -e 's/^\(.*\)\(\s.*$\)/\1/')
#if [ "${REF[0]}" != "${REF[1]}" ]; then
#  echo -e "\n\n"\
#        "There is a \e[1mnew version\e[0m of '\e[100;93mtuya-convert\e[39;49m'. Consider running the\n"\
#        "script found at the following URL to ensure best possible outcome.\n\n"\
#        "https://github.com/SirRedZ/ProxMox-Tuya-Convert-2.0-Container\n"
#  read -n 1 -p "--Press any key to continue--"
#fi
echo   "Thank you for choosing this LXC Container created by Whiskerz007 & Tollbringer.\n Special thanks to Colin Kuebler & all contributers to the Tuya Convert Project!"
sleep 5
./start_flash.sh
echo "tuya-convert exited with code:$?"
function menu1 (){
while true; do
  echo -e "\n\n\n\nHere are you options for flashing your device\n\n" \
    "    1) BACKUP only and UNDO\n" \
    "    2) FLASH loader to user2\n" \
    "    3) FLASH third-party firmware\n"
  read -n 1 -p "Which flash mechanism would you like? " RESPONSE
  if [[ "$RESPONSE" =~ ^[0-9]+$ ]] && [ $RESPONSE -ge 1 -a $RESPONSE -le 2 ]; then
    echo -e "\n\nYou selected $RESPONSE"
    break
  elif [[ "$RESPONSE" =~ ^[0-9]+$ ]] && [ $RESPONSE -eq 3 ]; then
    menu2
    break
  fi
done
}
function menu2 () {
  while true; do
    mapfile -t FILES < <(find /root/tuya-convert/files/ -type f -exec basename {} \;)
    mapfile -t LINKS < <(find /root/tuya-convert/files/ -type l -exec readlink {} \;)
    for link in "${LINKS[@]}"; do
      for i in "${!FILES[@]}"; do
        if [[ ${FILES[i]} = "$link" ]] || [[ ${FILES[i]} = "upgrade.bin" ]] || [[ ${FILES[i]} = "user2.bin" ]] ; then
          unset 'FILES[i]'
        fi
      done
    done
    FILES=("${FILES[@]}")
    echo -e "\n\nHere is the list of third-party firmwares\n\n" \
      "    1) Sonoff-tasmota (packaged with tuya-convert)"
    for i in "${!FILES[@]}"; do
      echo -e "     $((i+2))) ${FILES[$i]}"
    done
    echo -e "\n     b) Go back to previous menu\n"
    if [ ${#FILES[@]} -le 8 ]; then
      CHAR=1
    else
      CHAR=2
    fi
    read -e -n $CHAR -p "Which third-party firmware would you like to use? " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ $CHOICE -eq 1 ]; then
      echo -e "\n\nYou selected $CHOICE"
      break
    elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ $CHOICE -le $((${#FILES[@]}+1)) -a $CHOICE -gt 0 ]; then
      FIRMWARE=${FILES[$CHOICE-2]}
      RESPONSE=4
      break
    elif [[ "$CHOICE" == "b" ]]; then
      menu1
      break
    fi
  done
}
menu1
curl_cmd="curl --fail -m 2"
case $RESPONSE in
  1)
    $curl_cmd http://10.42.42.42/undo
    ;;
  2)
    $curl_cmd http://10.42.42.42/flash2
    ;;
  3)
    $curl_cmd http://10.42.42.42/flash3
    ;;
  4)
    echo -e "\nUsing $FIRMWARE firmware..."
    $curl_cmd http://10.42.42.42/flash3?url=http://10.42.42.1/files/$FIRMWARE
    ;;
esac
RESULT=$?
if [ $RESULT -ne 0 ]; then
  echo -e "\nWARNING: An error occured when trying to flash device. Dropping to shell...\n"
  /bin/bash
else
  if [ $RESPONSE -eq 1 ]; then
    SLEEP=2
  else
    SLEEP=75
  fi
  echo -e "\n\nWaiting for flash to complete.\nSleeping for $SLEEP seconds...\n"
  sleep $SLEEP
fi
./stop_flash.sh
