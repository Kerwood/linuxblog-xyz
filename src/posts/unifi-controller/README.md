---
title: Setting up a UniFi Controller
date: 2021-10-21 11:53:15
author: Patrick Kerwood
excerpt: This is a Docker Compose configuration example on deploying a UniFi Controller.
type: post
blog: true
tags: [docker-compose]
meta:
  - name: description
    content: How to setup UniFi Controller with Docker Compose
---

{{ $frontmatter.excerpt }}

Below is the Docker Compose configuration with my usual [Traefik setup.](/posts/traefik-2-docker-compose)
The webinterface will of course be served on `https://unifi.example.org` which by default will be port 443, but you still have to map port `8080` to the host.
Port `8080` is used for device discovery and communication, without it your devices would not appear in the interface.

I'v seen a lot of different guides on which ports to open in a firewall or forward to, but basically you just need port `8080` and a port for the webinterface.
This is the minimum setup and will be sufficient for most use cases.

There is no official container image from Ubiquiti. There are two popular unofficial images, one if from [linuxserver.io](https://hub.docker.com/r/linuxserver/unifi-controller) and the other is from [jacobalberty](https://hub.docker.com/r/jacobalberty/unifi).
I have been using `jacobalberty` for years and never had issues with that one, so I'm sticking with that.

## Docker Compose

- Change the image version you want to use, at the time of writing the current major version is 6.
- Change where you want the volume data be on the host.
- Change the URL you want to use in the host rule.

```yaml{10,18,22}
version: "3.8"

networks:
  default:
    external:
      name: traefik-proxy

services:
  unifi-controller:
    image: jacobalberty/unifi:v6
    container_name: unifi_controller
    restart: unless-stopped
    ports:
      - 8080:8080
    environment:
      TZ: Europe/Copenhagen
    volumes:
      - /unifi-data:/unifi
    labels:
      - traefik.enable=true
      - traefik.http.services.unifi.loadbalancer.server.port=8443
      - traefik.http.routers.unifi.rule=Host(`unifi.example.org`)
      - traefik.http.services.unifi.loadbalancer.server.scheme=https
      - traefik.http.routers.unifi.tls.certresolver=le
      - traefik.http.routers.unifi.entrypoints=websecure
```

## Setting the Inform address with DHCP

If you have a lot of UAP's in your environment, the easiest way of setting the Inform address is with a DHCP server. By setting the DHCP option 43, the UAP will take that setting (IP) and use that for the inform address and UAP will magically appear on the controller.

Note that you are not able to set the controller communication port, so your controller has to use `8080` for that.

Here's a couple of exampels i swooped from [this UBNT article](https://help.ui.com/hc/en-us/articles/204909754-UniFi-Device-Adoption-Methods-for-Remote-UniFi-Controllers). I use the Miktorik option and it works flawlessly.

The HEX string works as follows.

- IP: `192.168.3.10`
  - Suboption: `01` (do not change)
  - Length of payload: `04` (do not change)
  - 192: `C0`
  - 168: `A8`
  - 3: `03`
  - 10: `0A`
    - Result: `0104C0A8030A`

### Mikrotik

```
/ip dhcp-server option add code=43 name=unifi value=0x0104C0A8030A
/ip dhcp-server network set 0 dhcp-option=unifi

# Why 0104C0A8030A ?
#
# 01: suboption
# 04: length of the payload (must be 4)
# C0A8030A: 192.168.3.10
```

### ISC DHCP

```
# ...
option space ubnt;
option ubnt.unifi-address code 1 = ip-address;

class "ubnt" {
  match if substring (option vendor-class-identifier, 0, 4) = "ubnt";
  option vendor-class-identifier "ubnt";
  vendor-option-space ubnt;
}

subnet 10.10.10.0 netmask 255.255.255.0 {
  range 10.10.10.100 10.10.10.160;
  option ubnt.unifi-address 201.10.7.31;  ### UniFi Controller IP ###
  option routers 10.10.10.2;
  option broadcast-address 10.10.10.255;
  option domain-name-servers 168.95.1.1, 8.8.8.8;
  # ...
}
```

### Cisco CLI

```
# assuming your UniFi is at 192.168.3.10
ip dhcp pool <pool name>
network <ip network> <netmask>
default-router <default-router IP address>
dns-server <dns server IP address>
option 43 hex 0104C0A8030A # 192.168.3.10 -> CO A8 03 0A

# Why 0104C0A8030A ?
#
# 01: suboption
# 04: length of the payload (must be 4)
# C0A8030A: 192.168.3.10
```

---
