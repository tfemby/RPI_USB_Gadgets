#!/bin/bash

## Gadget Names
GADGET_NAME="audio_rndis_config"
CONFIG_FS="/sys/kernel/config"
CONFIGS="configs/c.1"
STRINGS="strings/0x409"
FUNCTIONS_UAC="functions/uac2.usb0"
FUNCTIONS_RNDIS="functions/rndis.usb0"

# Directories
GADGET="${CONFIG_FS}/usb_gadget"
GADGET_DIR="${GADGET}/${GADGET_NAME}"
CONFIGS_DIR="${GADGET_DIR}/${CONFIGS}"
STRINGS_DIR="${GADGET_DIR}/${STRINGS}"
FUNCTIONS_DIR_UAC="${GADGET_DIR}/${FUNCTIONS_UAC}"
FUNCTIONS_DIR_RNDIS="${GADGET_DIR}/${FUNCTIONS_RNDIS}"

# Gadget Info
ID_VEN="0x1d6b"
ID_PRO="0x0104"
BCD_DEV="0x0100"
BCD_VER="0x0200"

# Gather Device Information for Strings Information
STR_SER="$(sed 's/0000\(\w*\)/\1/' <(strings /proc/device-tree/serial-number))"
STR_PRO="$(strings /proc/device-tree/model) - ${GADGET_NAME}"
STR_MFR="$(sed 's/^\(\w*\s*\w*\).*/\1/' <(echo "${STR_PRO}"))"

## Configuration
CON_CON="${GADGET_NAME}"
CON_PWR="250"

## Create MAC Addresses from the Pi's serial Number
MAC="$(sed 's/\(\w\w\)/:\1/g' <(echo "${STR_SER}") | cut -b 2-)"
MAC_HOST="12$(echo "${MAC}" | cut -b 3-)"
MAC_DEV="02$(echo "${MAC}" | cut -b 3-)"

## Gather device information
BOARD="$(strings /proc/device-tree/model)"

# Audio Functions - Match these to your desired UAC2 format
AUDIO_CHANNEL_MASK_CAPTURE=3 # 3 = Stereo (Input to PC)
AUDIO_CHANNEL_MASK_PLAYBACK=3 # 3 = Stereo (Output from PC)
AUDIO_SAMPLE_RATES_CAPTURE=44100,48000
AUDIO_SAMPLE_RATES_PLAYBACK=44100,48000
AUDIO_SAMPLE_SIZE_CAPTURE=2 # 2 = S16LE (16-bit)
AUDIO_SAMPLE_SIZE_PLAYBACK=2 # 2 = S16LE (16-bit)

## Check for root
if [[ $EUID -ne 0 ]]; then
	echo "Root privileges required"
	exit 1
fi

case "$1" in
start)
    ## Load libcomposite
    if [ ! -d $GADGET ]; then
        echo "Loading composite module"
        if ! modprobe libcomposite; then
            "Failed to load libcomposite"
            exit 1
        else
            echo "[ OK ]"
        fi
    else
        echo "libcomposite module already loaded"
    fi
    
    if [ ! -d $GADGET_DIR ] ; then
        echo "Detecting platform:"
        echo -e "\tboard : ${BOARD}"
        echo -e "\tudc   : $(ls /sys/class/udc)"
    
        echo "Creating the USB Gadget"
        mkdir -p "${GADGET_DIR}"
    
        if ! cd "${GADGET_DIR}"; then
            echo "Error creating usb gadget in configfs"
            exit 1
        else
            echo "OK"
        fi
    
        echo "Setting Vendor and Product ID's"
        echo "${ID_VEN}" > "${GADGET_DIR}/idVendor"   # Linux Foundation
        echo "${ID_PRO}" > "${GADGET_DIR}/idProduct"  # Multifunction Composite Gadget
        echo "${BCD_DEV}" > "${GADGET_DIR}/bcdDevice" # v1.0.0
        echo "${BCD_VER}" > "${GADGET_DIR}/bcdUSB"    # USB 2.0
        echo "[ OK ]"
    
        echo "Setting English strings"
        # /sys/kernel/config/usb_gadget/<name>/strings/0x409
        mkdir -p "${STRINGS_DIR}"
        echo "${STR_SER}" > "${STRINGS_DIR}/serialnumber"  # xxxxxxxxxxxx
        echo "${STR_MFR}" > "${STRINGS_DIR}/manufacturer"  # Raspberry Pi
        echo "${STR_PRO}" > "${STRINGS_DIR}/product"       # Raspberry Pi Zero 2 W Rev 1.0
        echo "[ OK ]"
    
        echo "Creating USB device configs"
        # /sys/kernel/config/usb_gadget/<name>/configs/c.1/strings/0x409
        mkdir -p "${CONFIGS_DIR}/${STRINGS}"
        echo "${CON_CON}" > "${CONFIGS_DIR}/${STRINGS}/configuration"
        echo "${CON_PWR}" > "${CONFIGS_DIR}/MaxPower"
        echo "[ OK ]"
    
        echo "Creating USB UAC2 device functions..."
        # /sys/kernel/config/usb_gadget/<name>/functions/uac
        mkdir -p "${FUNCTIONS_DIR_UAC}"
        echo "${AUDIO_CHANNEL_MASK_CAPTURE}" > "${FUNCTIONS_DIR_UAC}/c_chmask"
        echo "${AUDIO_SAMPLE_RATES_CAPTURE}" > "${FUNCTIONS_DIR_UAC}/c_srate"
        echo "${AUDIO_SAMPLE_SIZE_CAPTURE}" > "${FUNCTIONS_DIR_UAC}/c_ssize"
        echo "${AUDIO_CHANNEL_MASK_PLAYBACK}" > "${FUNCTIONS_DIR_UAC}/p_chmask"
        echo "${AUDIO_SAMPLE_RATES_PLAYBACK}" > "${FUNCTIONS_DIR_UAC}/p_srate"
        echo "${AUDIO_SAMPLE_SIZE_PLAYBACK}" > "${FUNCTIONS_DIR_UAC}/p_ssize"
        echo "[ OK ]"

        echo "Creating USB RNDIS device functions..."
        # /sys/kernel/config/usb_gadget/<name>/functions/rndis.usb
        mkdir -p "${FUNCTIONS_DIR_RNDIS}"
        echo "${MAC_HOST}" > "${FUNCTIONS_DIR_RNDIS}/host_addr"
        echo "${MAC_DEV}" > "${FUNCTIONS_DIR_RNDIS}/dev_addr"
        echo "[ OK ]"

        echo "Symlinking functions to configurations"
        ln -s "${FUNCTIONS_DIR_UAC}" "${CONFIGS_DIR}/"
        ln -s "${FUNCTIONS_DIR_RNDIS}" "${CONFIGS_DIR}/"
        echo "[ OK ]"
    
        echo "Binding USB Device Controller"
        cd "${GADGET_DIR}"
        ls /sys/class/udc > "${GADGET_DIR}/UDC"
        echo "[ OK ]"
    else
        echo "Gadget directory already created"
        exit 1
    fi
    
    ## Configure an ipv4 adress to the usb0 interface
    # Sleep for 5 seconds to allow the Pi the configure the gadget
    echo "Sleeping for 5 seconds..."
    sleep 5s
    # Handle IP with NetworkManager
    echo "Bringing up network interface usb0"
    nmcli connection up usb0
    
    # Handle IP using ip-utils
    #ip addr add 10.10.42.1/24 brd + dev usb0
    #ip link set usb0 up
    ;;
stop)
    echo "Stopping the USB Gadget"
    # Ignore all errors here on in a best effort basis
    set +e

    echo "Bringing down network interface usb0"
    nmcli connection down usb0

    if ! cd "${GADGET_DIR}"; then
        echo "Error: No configfs gadget found"
        exit 1
    fi

    echo "Unbinding USB Device Controller"
    echo "" > "${GADGET_DIR}/UDC"
    echo "[ OK ]"

    echo "Clearing configurations"
    rm "${CONFIGS_DIR}/uac2.usb0"
    rm "${CONFIGS_DIR}/rndis.usb0"
    rmdir "${CONFIGS_DIR}/${STRINGS}"
    rmdir "${CONFIGS_DIR}"
    echo "[ OK ]"

    echo "Clearing Gadget Functionality"
    rmdir "${FUNCTIONS_DIR_UAC}"
    rmdir "${FUNCTIONS_DIR_RNDIS}"
    echo "[ OK ]"

    echo "Clearing English strings"
    rmdir "${STRINGS_DIR}"
    echo "[ OK ]"

    echo "Removing Gadget Directory"
    cd "${CONFIG_FS}"
    rmdir "${GADGET_DIR}"
    cd "/"

    set -e
    ;;
*)
    echo "Usage: $0 {start|stop}"
    ;;
esac
