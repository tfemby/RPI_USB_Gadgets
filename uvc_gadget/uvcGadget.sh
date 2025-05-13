#!/usr/bin/env bash

## Gadget Names
GADGET_NAME="uvcGadget"
CONFIG_FS="/sys/kernel/config"
CONFIGS="configs/c.1"
STRINGS="strings/0x409"

## Directories
GADGET="${CONFIG_FS}/usb_gadget"
GADGET_DIR="${GADGET}/${GADGET_NAME}"
CONFIGS_DIR="${GADGET_DIR}/${CONFIGS}"
STRINGS_DIR="${GADGET_DIR}/${STRINGS}"

## Gadget Info
ID_VEND="0x0525"  # Netchip Technology, Inc.
ID_PROD="0xa4a2"  # Linux-USB Ethernet/RNDIS Gadget
BCD_DEV="0x0100"  # v1.0.0
BCD_VER="0x0200"  # USB 2.0

## Gather device information for Strings
STR_SER="$(sed 's/0000\(\w*\)/\1/' <(strings /proc/device-tree/serial-number))"
STR_PRO="$(strings /proc/device-tree/model) - Webcam"
STR_MFR="$(sed 's/^\(\w*\s*\w*\).*/\1/' <(echo "${STR_PRO}"))"

# Later on, this function is used to tell the usb subsystem that we want
# to support a particular format, framesize and frameintervals
create_frame() {
    # Example usage:
    # create_frame <function name> <width> <height> <format> <name> <intervals>

    FUNCTION=$1
    WIDTH=$2
    HEIGHT=$3
    FORMAT=$4
    NAME=$5

    wdir="functions/${FUNCTION}/streaming/${FORMAT}/${NAME}/${HEIGHT}p"

    mkdir -p "${wdir}"
    echo "${WIDTH}" > "${wdir}/wWidth"
    echo "${HEIGHT}" > "${wdir}/wHeight"
    echo $(( "${WIDTH}" * "${HEIGHT}" * 2 )) > "${wdir}/dwMaxVideoFrameBufferSize"
    cat <<EOF > "${wdir}/dwFrameInterval"
$6
EOF
}

# This function sets up the UVC gadget function in configfs and binds us
# to the UVC gadget driver.
create_uvc() {
    CONFIG=$1
    FUNCTION=$2

    echo "Creating UVC gadget functionality : ${FUNCTION}"
    mkdir "functions/${FUNCTION}"

    create_frame "${FUNCTION}" 640 480 uncompressed u "333333
416667
500000
666666
1000000
1333333
2000000
"
    create_frame "${FUNCTION}" 1280 720 uncompressed u "1000000
1333333
2000000
"
    create_frame "${FUNCTION}" 1920 1080 uncompressed u "2000000"
    create_frame "${FUNCTION}" 640 480 mjpeg m "333333
416667
500000
666666
1000000
1333333
2000000
"
    create_frame "${FUNCTION}" 1280 720 mjpeg m "333333
416667
500000
666666
1000000
1333333
2000000
"
    create_frame "${FUNCTION}" 1920 1080 mjpeg m "333333
416667
500000
666666
1000000
1333333
2000000
"

    mkdir "functions/${FUNCTION}/streaming/header/h"
    cd "functions/${FUNCTION}/streaming/header/h"
    ln -s ../../uncompressed/u
    ln -s ../../mjpeg/m
    cd ../../class/fs
    ln -s ../../header/h
    cd ../../class/hs
    ln -s ../../header/h
    cd ../../class/ss
    ln -s ../../header/h
    cd ../../../control
    mkdir header/h
    ln -s header/h class/fs
    ln -s header/h class/ss
    cd ../../../

    # This configures the USB endpoint to allow 3x 1024 byte packets per
    # microframe, which gives us the maximum speed for USB 2.0. Other
    # valid values are 1024 and 2048, but these will result in a lower
    # supportable framerate.
    echo 2048 > "functions/${FUNCTION}/streaming_maxpacket"

    ln -s "functions/${FUNCTION}" "${CONFIG}"
}

# This subroutine removes all of the previously created uvc functions.
delete_uvc() {
    # Example usage:
    #     delete_uvc <target config> <function name>
    #     delete_uvc config/c.1 uvc.0
    CONFIG=$1
    FUNCTION=$2

    echo "Deleting UVC gadget functionality: ${FUNCTION}"
    rm "${CONFIG}"/"${FUNCTION}"
    rm functions/"${FUNCTION}"/control/class/{f,s}s/h
    rm functions/"${FUNCTION}"/streaming/class/{f,h,s}s/h
    rm functions/"${FUNCTION}"/streaming/header/h/{u,m}
    rmdir functions/"${FUNCTION}"/streaming/uncompressed/u/{108,72,48}0p
    rmdir functions/"${FUNCTION}"/streaming/uncompressed/u
    rmdir functions/"${FUNCTION}"/streaming/mjpeg/m/{108,72,48}0p
    rmdir functions/"${FUNCTION}"/streaming/mjpeg/m
    rmdir functions/"${FUNCTION}"/streaming/header/h
    rmdir functions/"${FUNCTION}"/control/header/h
    rmdir functions/"${FUNCTION}"
}

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
        modprobe libcomposite
        echo "[ OK ]"
    else
        echo "Composite module already loaded"
    fi
    
    # Configure the gadget through libcomposites configfs (/sys/kernel/configs)
    echo "Creating Gadget Directory"
    
    if [ ! -d $GADGET_DIR ]; then
        echo "Detecting platform:"
        echo "  board : ${STR_PRO}"
        echo "  udc   : $(ls /sys/class/udc)"
    
        echo "Creating the USB gadget directory"
        mkdir -p "${GADGET_DIR}"
    
        if ! cd "${GADGET_DIR}"; then
            echo "Error creating usb gadget in configfs"
            exit 1;
        else
            echo "[ OK ]"
        fi
    
        echo "Setting Vendor and Product ID's"
        echo "${ID_VEND}" > "${GADGET_DIR}/idVendor"   # Netchip Technology, Inc.
        echo "${ID_PROD}" > "${GADGET_DIR}/idProduct"  # Linux-USB Ethernet/RNDIS Gadget
        echo "${BCD_DEV}" > "${GADGET_DIR}/bcdDevice"  # v1.0.0
        echo "${BCD_VER}" > "${GADGET_DIR}/bcdUSB"     # USB 2.0
        echo "[ OK ]"
    
        echo "Setting English Strings"
        mkdir -p "${STRINGS_DIR}"
        echo "${STR_SER}" > "${STRINGS_DIR}/serialnumber" # 0000xxxxxxxx
        echo "${STR_MFR}" > "${STRINGS_DIR}/manufacturer" # Raspberry Pi
        echo "${STR_PRO}" > "${STRINGS_DIR}/product"      # Raspberry Pi Zero 2 W Rev 1.0 
        echo "[ OK ]"
    
        echo "Creating Configs"
        mkdir -p "${CONFIGS_DIR}"
        echo "[ OK ]"
    
        echo "Creating Functions"
        create_uvc "${CONFIGS_DIR}" uvc.0
        echo "[ OK ]"
    
        echo "Binding USB Device Controller"
        ls /sys/class/udc > "${GADGET_DIR}/UDC"
        echo "[ OK ]"
    fi
    
    # Run uvc-gadget. The -c flag sets libcamera as a source, arg 0 selects
    # the first available camera on the system. All cameras will be listed,
    # you can re-run with -c n to select camera n or -c ID to select via
    # the camera ID.
    #uvc-gadget -c 0 uvc.0

    # The above has been commented out because it's being run by the systemd
    # service. Don't uncomment it unless you know what you're doing.
    ;;
stop)
    echo "Stopping the USB gadget"
    # Ignore all errors here on a best effort basis
    set +e

    if ! cd "${GADGET_DIR}"; then
        echo "Error: no configfs gadget found"
        exit 1
    fi

    echo "Unbinding USB Device Controller"
    echo "" > "${GADGET_DIR}/UDC"
    echo "[ OK ]"

    # This has it's own echo message in the subroutine
    delete_uvc "${CONFIGS_DIR}" uvc.0

    echo "Clearing configurations"
    rmdir "${CONFIGS_DIR}"
    echo "[ OK ]"

    echo "Clearing English strings"
    rmdir "${STRINGS_DIR}"
    echo "[ OK ]"

    echo "Removing gadget directory"
    cd "${CONFIG_FS}"
    rmdir "${GADGET_DIR}"
    echo "[ OK ]"

    set -e
    ;;
*)
    echo "Usage: $0 {start|stop}"
    ;;
esac

