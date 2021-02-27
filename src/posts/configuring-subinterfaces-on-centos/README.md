---
title: Configuring subinterfaces on CentOS
date: 2021-02-27 15:47:26
author: Patrick Kerwood
excerpt: In this post I will show you how to create subinterfaces on your CentOS server. It's easy and only takes a couple of minutes to setup, after that just trunk your VLAN's with 802.1q to the server.
blog: true
tags: [network, centos]
---
In this post I will show you how to create subinterfaces on your CentOS server. It's easy and only takes a couple of minutes to setup, after that just trunk your VLAN's with 802.1q to the server.

I used CentOS 8 Stream as my OS, but any RHEL/CentOS related distribution will probably work just the same. I'll create two subinterfaces for VLAN 10 and 20. One will be with DHCP enabled and the other will be with a static IP configuration.

## Enable 802.1q
First we must enable the `8021q` kernel module. Below command will temporary enable the module until next reboot.
```sh
modprobe 8021q
```

Verify that the module loaded.
```sh
lsmod | grep 8021q
```

Run below command to make the operating system load `8021q` on boot.
```sh
echo 8021q >> /etc/modules
```
## Configure subinterfaces
Get the name of your network interface, mine is `eno1` which I'll be using in this example. Locate the network configuration for the interface, located at `/etc/sysconfig/network-scripts`. The configuration file name would be `ifcfg-<interface-name>`.

Delete everything in that file, we dont need that, and replace it with below config. Remeber to replace `eno1` with your own interface name.
```
TYPE=Ethernet
DEVICE=eno1
ONBOOT=yes
BOOTPROTO=none
NAME=eno1
```

Configure the subinterface for VLAN 10. Create a new file called `ifcfg-eno1.10` and paste in the below config, this will setup the subinterface with DHCP. The last line, `DEFROUTE=yes`, tells the operating system to use this interface as your default route. 
```
DEVICE=eno1.10
BOOTPROTO=dhcp
ONBOOT=yes
VLAN=yes
DEFROUTE=yes
```

Configure the subinterface for VLAN 20. Create a new file called `ifcfg-eno1.20` and paste in the below config. This will setup the subinterface with a static IP configuration.
```
DEVICE=eno1.20
BOOTPROTO=none
ONBOOT=yes
IPADDR=10.0.0.2
PREFIX=24
GATEWAY=10.0.0.1
DNS1=8.8.8.8
DNS2=8.8.4.4
VLAN=yes
```

Restart Network Manager to enable the interfaces.
```
systemctl restart NetworkManager
```
---