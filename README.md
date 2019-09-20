# Proxmox Tuya-Convert v2.0 Container

This script will create a Proxmox LXC container with the latest Debian-stretch and setup tuya-convert 2.0. This process is still experimental and very tempermental. Using brute-force, connecting and disconnection during the process, I have been successful with all devices EXCEPT light-bulbs.
This process has been confirmed working by multiple others with various levels of interaction.

To create a new LXC container in the `local-lvm` storage, run the following in a SSH session or the console from Proxmox interface

```
bash -c "$(wget -qO - https://raw.githubusercontent.com/sirredz/proxmox_tuya-convert_container/master/create_container.sh)" -s local-lvm
```

During the setup process, you will prompted to select a wireless interface. This interface will be assigned to container. _(Note: When the container is running, no other container or VM will have access to the interface.)_ After the successful completion of the script, start the container identified by the script, then use the login credentials shown to start the tuya-convert script. If you need to stop tuya-convert, press `CTRL + C` and it will be halted and you will be brought back to the login prompt. If you login again it will start tuya-convert again.

## Prerequisites

In order for this script to work appropriately, you must first have the wireless NIC's drivers installed and setup correctly for your WiFi adapter in Proxmox. The beginning the of the script will test for valid WLAN interfaces. An error will be produced if one can not be found.

## Custom Firmware

To add custom firmware (not supplied by tuya-convert), connect to the samba share created by the container (details are provided at the login prompt) and add the binary to the `tuya-convert/files/` folder. Your binary will listed under the custom firmware menu.

## It is highly recommended you flash SONOFF.BIN with the WIFI Manager enabled by default. This will prevent 'bricking' the device as a result of typing the SSID or PASSWORD incorrectly, during setup. I suggest you take your time when adding your WIFI credentials for the first time.

DigiblurDIY has provided the latest Tasmota BIN files with WiFiManager enabled here: (Thanks Travis!)
All you have to do is start your Tuya-Convert container, and drop the BIN file in the files folder using SAMBA bfore you start the conversion process. The script will index the folder contents for you.

https://github.com/digiblur/Sonoff-Tasmota/tree/development/generic
