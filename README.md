# RPI USB Gadgets

This repo contains scripts, systemd-service and udev files I use for Rasberry Pi based USB gadgets.

## Notes

Due to only really using the UVC and ethernet gadgets, I've only written scripts for the two of them.

My scripts are heavily based off of those that came before me:

- [USB Gadget ConfigFS documentation](https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html) 
- [thagrols' Ethernet Gadget Guide](https://github.com/thagrol/Guides)
- [Plug-and-play Raspberry Pi USB webcam Tutorial](https://www.raspberrypi.com/tutorials/plug-and-play-raspberry-pi-usb-webcam/)
- [uvc-gadget example script](gitlab.freedesktop.org/camera/uvc-gadget/-/blob/master/scripts/uvc-gadget.sh)

I've mostly mix-and-matched the above various scripts and have automated grabbing the Raspberry Pi's
serial number from device-tree information. In the case of the ethernet gadget, I've also created MAC
addresses from the Pi's serial number as well.

Prior to using these scripts, ensure that you've added the following to your `/boot/firmware/config.txt`:

```

```

## Script Usage

Provided you have the correct hardware, the only thing you'll need to change in the scripts is the
`GADGET_NAME` variable.

To use the scripts, you may invoke it like so:

```
ethernetGadget.sh {start|stop}
```

On start, the script should `modprobe libcomposite` and populate `/sys/kernel/config/usb_gadget`.

On stop, the script should deactivate the gadget and de-populate `/sys/kernel/config/usb_gadget`.

When stopping the gadget, I haven't been able to able to unload libcomposite; however the stop
command is generally only run when shutting down. This simply provides a clean shutdown without
error messages littering `journalctl`.

## Ethernet Gadget

<details>

Copy `ethernet_gadget/ethernetGadget.sh` to `/usr/local/bin/`

```
# cp ethernet_gadget/ethernetGadget.sh /usr/local/bin
```

Copy `ethernetGadget.service` to `/etc/systemd/system/`

```
# cp ethernet_gadget/ethernetGadget.service /etc/systemd/system
```

The ethernet gadget is enabled with:

```
# systemctl enable --now ether-gadget
```

This will launch the ethernet gadget during boot, after `network-online.target`. The networking interface
created by the gadget is brought online using `nmcli connection up usb0`.

From here, you may use use `nmcli`, `nmtui` or your favourite GUI tool to configure network settings.

</details>

## UVC Gadget (Webcam)

### TODO: Write this section and clean up the UVC gadget script

The webcam gadget gadget utilises a udev rule to load the corresponding systemd-service after the
kernel has loaded the necessary camera modules.
