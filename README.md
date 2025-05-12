# RPI USB Gadgets

This repo contains scripts, systemd-service and udev files I use for Rasberry Pi based USB gadgets.

## Notes

Due to only really using the UVC and ethernet gadgets, I've only written scripts for the two of them.

My scripts are heavily based off of those that came before me:

- [USB Gadget ConfigFS documentation](https://www.kernel.org/doc/html/latest/usb/gadget_configfs.html) 
- [thagrols' Ethernet Gadget Guide](https://github.com/thagrol/Guides)
- [Plug-and-play Raspberry Pi USB webcam Tutorial](https://www.raspberrypi.com/tutorials/plug-and-play-raspberry-pi-usb-webcam/)
- [uvc-gadget example script](https://gitlab.freedesktop.org/camera/uvc-gadget/)
- [Red Hat Documentation - Chapter 6: Configuring a network bridge by using nmcli](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/configuring-a-network-bridge_configuring-and-managing-networking#configuring-a-network-bridge-by-using-nmcli_configuring-a-network-bridge)

I've mostly mix-and-matched the above various scripts and have automated grabbing the Raspberry Pi's
serial number from device-tree information. In the case of the ethernet gadget, I've also created MAC
addresses from the Pi's serial number as well.

Prior to using these scripts, ensure that you've added the following to your `/boot/firmware/config.txt`:

```
dtoverlay=dwc2,dr_mode=peripheral
```

Then reboot the Pi. This will cause the Pi to boot with the DWC2 controller running in peripheral mode.

## Script Usage

Provided you have the correct hardware, the only thing you'll need to change in the scripts is the
`GADGET_NAME` variable.

To use the scripts, you may invoke it like so:

```console
root@raspberry:~# ethernetGadget.sh {start|stop}
```

On start, the script should `modprobe libcomposite` and populate `/sys/kernel/config/usb_gadget`.

On stop, the script should deactivate the gadget and de-populate `/sys/kernel/config/usb_gadget`.

When stopping the gadget, I haven't been able to able to unload libcomposite; however the stop
command is generally only run when shutting down. This simply provides a clean shutdown without
error messages littering `journalctl`.

## Ethernet Gadget

<details>

The following is performed on the Raspberry Pi.

Clone this repo:

```console
user@raspberry:~/ $ git clone https://github.com/tfemby/RPI_USB_Gadgets.git
```

Enter the `RPI_USB_Gadgets` directory:

```console
user@raspberry:~/ $ cd RPI_USB_Gadgets
```

Copy `ethernet_gadget/ethernetGadget.sh` to `/usr/local/bin/`:

```console
user@raspberry:~/RPI_USB_Gadgets $ sudo cp ethernet_gadget/ethernetGadget.sh /usr/local/bin
```

Copy `ethernetGadget.service` to `/etc/systemd/system/`:

```console
user@raspberry:~/RPI_USB_Gadgets $ sudo cp ethernet_gadget/ethernetGadget.service /etc/systemd/system
```

The ethernet gadget is enabled with:

```console
user@raspberry:~/RPI_USB_Gadgets $ sudo systemctl enable --now ether-gadget.service
```

This will create the ethernet gadget during boot, after `network-online.target`. The networking interface
created by the gadget is brought online using `nmcli connection up usb0`.

From here, you may use use `nmcli`, `nmtui` or your favourite GUI tool to configure network settings.
The Raspberry Pi itself is responsible for either obtaining an IP address or statically setting it.

### Networking Configuration Options

The Pi will effectively now be connected to your host machine with an "ethernet" connection. If already
configured, the wifi connection will also still work. Thagrols guide (linked above) explains that there are
two ways to make use of this connection:

1. Bridged Access
    - You create a virtual network bridge on the host for bridged access.
        - Your host will act as a layer 2 switch.
    - Allows the Pi to use the hosts physical network connection.
    - The usb0 connection gets it's own IP address that's accessible from other computers on the network.
        - Your networks router will assign an IP Address if you use a DHCP.
        - The Pi will consequently have two IP addresses: One for wifi and one for usb0.
2. Routed Access
    - You create firewall rules which allow the host to forward packets to the Pi.
        - The host will act as a router.
    - Allows the Pi to use the hosts physical connection.
    - The usb0 interface interface gets a local IP address from the Host.
        - The Pi is behind a NAT meaning that unless ports are explicitly opened on the host, other computers
          aren't able to access the Pi.
    - Allows the Host to use the Pi's wifi connection.
        - The inverse of the above: The host is now behind a NAT and port management will be needed to
          communicate with other devices on the network.

#### Bridged Access
Since I use Linux for my desktop, I use Network Manager on my PC as well.
Because I've only needed the bridge setup, I'll cover how to configure a network bridge using Network Manager.

**!!! NOTE: You can only bridge ethernet interfaces!!!**
If you are using wifi on your host, look into configuring routed access. Thragols guide (linked above) contains
a section about how configure a routed setup.

**All of the following is to be performed on your PC; Not on the Raspberry Pi.**

Remove any pre-configured network connections:

```console
user@pc:~/ $ nmcli connection show
NAME             UUID                                  TYPE      DEVICE     
Auto Ethernet    xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  ethernet  enp5s0
lo               xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  loopback  lo         

user@pc:/ $ nmcli connection delete "Auto Ethernet"
Connection 'Auto Ethernet' (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) successfully deleted.
```

Plug your micro-usb into your Pi's data port (if using a Pi Zero or Pi Zero 2) and the other end into a
usb port of your host. I'm not fully sure about how this works on other versions of Pi's but this works
for me.

Now find the usb0 interface on the host. It may have been renamed.

```console
user@pc:~/ $ sudo journalctl -b0 | grep cdc_ether.*renamed.*usb0
May 05 16:00:00 pc kernel: cdc_ether 1-4:1.0 enp1s0f0u4: renamed from usb0

user@pc:~/ $ nmcli device status
DEVICE      TYPE      STATE                   CONNECTION         
enp5s0      ethernet  connected               Auto Ethernet
lo          loopback  connected (externally)  lo                 
enp1s0f0u4  ethernet  disconnected            --                 
```

Now we know that: 

- `enp1s0f0u4` is the name of the usb interface on the host
- `enp5s0` is the name of the ethernet port on the host

Take note of both of these as the names of both will be required when we "connect" these interfaces into
the bridge.

Let's now create a bridge named, `bridge0`.

```console
user@pc:~/ $ nmcli connection add type bridge con-name bridge0 ifname bridge0
Connection 'bridge0' (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) successfully added.

```

Now we'll create connection profiles for our two interfaces - `enp1s0f0u4` & `enp5s0`.

```console
user@pc:~/ $ nmcli connection add type ethernet slave-type bridge con-name bridge0-host-pc ifname enp5s0 master bridge0 
Connection 'bridge0-host-pc' (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) successfully added.

user@pc:~/ $ nmcli connection add type ethernet slave-type bridge con-name bridge0-eth-gadget ifname enp1s0f0u4 master bridge0 
Connection 'bridge0-eth-gadget' (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) successfully added.
```

Each interface connected to `bridge0` doesn't have it's own IP address. On the host, the only interface
which will get an IP address is `bridge0` itself. If you're using DHCP, you don't need to do anything else.
If you want your PC to have be accessible with a static IP, the following command do just that.

```console
user@pc:~/ $ nmcli connection modify bridge0 ipv4.addresses '10.0.0.10/24' ipv4.gateway '10.0.0.1' ipv4.dns '10.0.0.1' ipv4.dns-search 'example.com' ipv4.method manual

```

The previous command doesn't provide any feedback for some reason but you can verify that the `bridge0`
interface now has the ipv4 info set we set just before.

```console
user@pc:~/ $ nmcli connection show bridge0 | grep ipv4
ipv4.method:                            manual
ipv4.dns:                               10.0.0.1
ipv4.dns-search:                        example.com
ipv4.dns-options:                       --
ipv4.dns-priority:                      0
ipv4.addresses:                         10.0.0.10/24
ipv4.gateway:                           10.0.0.1
ipv4.routes:                            --
ipv4.route-metric:                      -1
ipv4.route-table:                       0 (unspec)
ipv4.routing-rules:                     --
ipv4.replace-local-rule:                -1 (default)
ipv4.dhcp-send-release:                 -1 (default)
ipv4.ignore-auto-routes:                no
ipv4.ignore-auto-dns:                   no
ipv4.dhcp-client-id:                    --
ipv4.dhcp-iaid:                         --
ipv4.dhcp-dscp:                         --
ipv4.dhcp-timeout:                      0 (default)
ipv4.dhcp-send-hostname:                yes
ipv4.dhcp-hostname:                     --
ipv4.dhcp-fqdn:                         --
ipv4.dhcp-hostname-flags:               0x0 (none)
ipv4.never-default:                     no
ipv4.may-fail:                          yes
ipv4.required-timeout:                  -1 (default)
ipv4.dad-timeout:                       -1 (default)
ipv4.dhcp-vendor-class-identifier:      --
ipv4.link-local:                        0 (default)
ipv4.dhcp-reject-servers:               --
ipv4.auto-route-ext-gw:                 -1 (default)
```
Likewise, if using DHCP, the above command will look similar.

```console
user@pc:~/ $ nmcli connection show bridge0 | grep ipv4
ipv4.method:                            auto
ipv4.dns:                               --
ipv4.dns-search:                        --
ipv4.dns-options:                       --
ipv4.dns-priority:                      0
ipv4.addresses:                         10.0.0.21/24
ipv4.gateway:                           10.0.0.1
ipv4.routes:                            --
ipv4.route-metric:                      -1
ipv4.route-table:                       0 (unspec)
ipv4.routing-rules:                     --
ipv4.replace-local-rule:                -1 (default)
ipv4.dhcp-send-release:                 -1 (default)
ipv4.ignore-auto-routes:                no
ipv4.ignore-auto-dns:                   no
ipv4.dhcp-client-id:                    --
ipv4.dhcp-iaid:                         --
ipv4.dhcp-dscp:                         --
ipv4.dhcp-timeout:                      0 (default)
ipv4.dhcp-send-hostname:                yes
ipv4.dhcp-hostname:                     --
ipv4.dhcp-fqdn:                         --
ipv4.dhcp-hostname-flags:               0x0 (none)
ipv4.never-default:                     no
ipv4.may-fail:                          yes
ipv4.required-timeout:                  -1 (default)
ipv4.dad-timeout:                       -1 (default)
ipv4.dhcp-vendor-class-identifier:      --
ipv4.link-local:                        0 (default)
ipv4.dhcp-reject-servers:               --
ipv4.auto-route-ext-gw:                 -1 (default)
```

I personally had some issues when only bringing up `bridge0` so I instead bring `down` the hardware
based interfaces + `bridge0` then bring them all back up.

```console
user@pc:~/ $ nmcli connection down bridge0-host-pc
user@pc:~/ $ nmcli connection down bridge0-eth-gadget
user@pc:~/ $ nmcli connection down bridge0
user@pc:~/ $ nmcli connection up bridge0
user@pc:~/ $ nmcli connection up bridge0-host-pc
user@pc:~/ $ nmcli connection up bridge0-eth-gadget
```

You can now reboot the Pi (or just pull it out and plug it back into the pc) and it should be given an
ipv4 address from your networks router.

</details>

## UVC Gadget (Webcam)

### TODO: Write this section and clean up the UVC gadget script

The webcam gadget gadget utilises a udev rule to load the corresponding systemd-service after the
kernel has loaded the necessary camera modules.
