#!/usr/bin/env bash

set -o errexit  #Exit immediately if a pipeline returns a non-zero status
set -o errtrace #Trap ERR from shell functions, command substitutions, and commands from subshell
set -o nounset  #Treat unset variables as an error
set -o pipefail #Pipe will exit with last non-zero status if applicable

cd /root/tuya-convert
TITLE="tuya-convert Commit Switcher"
WORKING_COMMIT=$(git show -s --format="%h")
COMMIT_MESSAGE_LENGTH=50
git fetch origin

for i in $(git log --format="%h" origin/master); do
  TAG=$i
  LINE=$(git log --format='(%ar) %s' -n 1 $i)
  if [ ${#LINE} -gt $COMMIT_MESSAGE_LENGTH ]; then
    LINE=$(
      echo $LINE | \
      cut -c 1-$(($COMMIT_MESSAGE_LENGTH - 3)) | \
      sed 's/\(.*\)$/\1.../'
    )
  fi
  MENU+=( "$TAG" "$LINE" )
done

COMMIT=$(
  whiptail --title "$TITLE" --menu --default-item $WORKING_COMMIT \
  "\nSelect the commit you would like to switch to." \
  19 66 10 "${MENU[@]}" 3>&1 1>&2 2>&3
) || exit $?

if [ "$WORKING_COMMIT" == "$COMMIT" ]; then
  whiptail --title "$TITLE" --msgbox \
    "You have selected the same commit that is currently running.
    \nDoing nothing." \
    11 40
  exit
fi

RESPONSE=$(
  whiptail --title "$TITLE" --yesno \
  "Would you like to switch to the following commit?\n
  \n$(git log --no-decorate -n 1 $COMMIT)" \
  20 60 3>&1 1>&2 2>&3
) || exit $?
git checkout -f $COMMIT

/root/configure_tuya-convert.sh
