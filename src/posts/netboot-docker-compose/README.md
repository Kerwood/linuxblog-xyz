---
title: PXE booting with Netboot
date: 2020-08-25 12:20:56
author: Patrick Kerwood
excerpt: Netboot gives you the opportunity to boot various operating system installers or utilities using iPXE. It will load a list of all your favorite Linux distros and will pull a fresh image of your choosing, from the internet to boot. 
type: post
blog: true
tags: [netboot, docker-compose, pxe]
---

This post is just a very simple Docker Compose example on Netboot. Theres nothing complicated about it, but its just really one of my favorite projects. It makes installing a new operating system or live booting a utility distro, a breeze.

As you can see in the gif below, when PXE booting Netboot, you are presented with a menu from where you can choose various Linux distibutions to boot.

![](./netboot.xyz.gif)

Netboot uses iPXE to pull fresh images from the internet. It also comes with a WebUI to refresh the list of images and even lets you configure or create your own menus. 


## Docker Compose
```
version: "3.8"
services:
  netbootxyz:
    image: linuxserver/netbootxyz
    container_name: netbootxyz
    environment:
      - PUID=1000
      - PGID=1000
    volumes:
      - netboot-config:/config
    ports:
      - 3000:3000
      - 69:69/udp
      - 8080:80 #optional
    restart: unless-stopped

volumes:
  netboot-config:
```

You can find the WebUI on port `3000`. The other port, `8080`, is just a webserver where you can store any necessary config files like kickstarter or ignition files.

## Configuring DHCP

### ISC DHCP
Add the highlighted lines to your `dhcpd.conf` file in your subnet definition. Replace `10.0.0.27` with the IP of the host running Netboot.
```{6-10}
subnet 10.0.0.0 netmask 255.255.255.0 {
    range 10.0.0.2 10.0.0.254;
    option subnet-mask 255.255.255.0;
    option broadcast-address 10.0.0.255;
    option routers 10.0.0.1;
    # option 66
    option tftp-server-name "10.0.0.27";
    next-server 10.0.0.27;
    # option 67
    option bootfile-name "netboot.xyz.kpxe";
}
```

### Mikrotik

List the DHCP networks.
```
[admin@Mikrotik] > /ip dhcp-server network print detail 
Flags: D - dynamic 
 0   address=10.0.0.0/24 gateway=10.0.0.1 dns-server=8.8.8.8
```
Now add the the `next-server` and `boot-file` options to the network.
```
/ip dhcp-server network set 0 next-server="'10.0.0.27'"
/ip dhcp-server network set 0 boot-file-name="'netboot.xyz.kpxe'"
```

### Final notes
Remember to configure your boot settings in the BIOS to be able to boot in Legacy mode.