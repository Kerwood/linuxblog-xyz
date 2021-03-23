---
title: Creating a WireGuard VPN exit node
date: 2021-01-24 12:45:49
author: Patrick Kerwood
excerpt: In this how-to I'll create a WireGuard VPN exit node, which is NAT'ing connections for clients. I will give an example on using both iptables and firewalld and how to forward ports to a WireGuard client.
type: post
blog: true
tags: [wireguard, vpn]
---
{{ $frontmatter.excerpt }}

--- 

[[toc]]

## Install WireGuard
Create a VPS some where in the world. For this example I'll be using [Digital Ocean](https://www.digitalocean.com/).

WireGuard has a fantastic support for different platforms. In this how-to I will be using CentOS 7 for the server, but have a look at [https://www.wireguard.com/install/](https://www.wireguard.com/install/) for installing on a different platform. 

### CentOS 7
Install `epel-release` and the [ELRepo](http://elrepo.org/tiki/HomePage) repository.
```sh
yum install epel-release https://www.elrepo.org/elrepo-release-7.el7.elrepo.noarch.rpm
```

Install `yum-plugin-elrepo`.
```sh
yum install yum-plugin-elrepo
```

Install WireGuard.
```sh
yum install kmod-wireguard wireguard-tools
```

## Setting up the WireGuard server
Create a directory for the WireGuard configuration files, if it does not exist.
```sh
mkdir -p /etc/wireguard
```

Create keys for the server. Files `wg_private.key` and `wg_public.key` will be saved to the `/etc/wireguard` directory.
```sh
wg genkey | tee /etc/wireguard/wg_private.key | wg pubkey | tee /etc/wireguard/wg_public.key
```
Create a configuration file for the WireGuard interface at `/etc/wireguard/wg0.conf`. Add the content of the `wg_private.key` file. The `Address` property is the IP address of the VPN network. The server will get the IP address of `10.99.0.1`.
```ini{2,7}
[Interface]
Address = 10.99.0.1/24
SaveConfig = true
ListenPort = 51820
PrivateKey = <wg_private.key>
```

### Using Firewalld

Enable masquerade and open port `51820` for WireGuard and reload firewalld.
```sh
firewall-cmd --permanent --zone public --add-masquerade
firewall-cmd --permanent --zone public --add-port=51820/udp
firewall-cmd --reload
```

A lot of other guides will tell you to set `net.ipv4.ip_forward=1`. This is not nessacary when using firewalld. The `--add-masquerade` option will do this for you.


### Using Iptables

Enable IPv4 forwarding and make sysctl apply the changes.
```sh
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf && sysctl -p
```

Enable masquerade and open port `51820` for WireGuard. Replace `<public interface>` with your servers public interface.
```sh
iptables -t nat -A POSTROUTING -o <public interface> -j MASQUERADE
iptables -I INPUT 1 -p udp --dport 51820 -j ACCEPT
```

::: tip
Remember to make your iptables rules persistant upon reboot. How you do that is out of this scope, but have a look at `iptables-persistent`.
:::

Add below lines to your `wg0.conf` file.
```ini
[Interface]
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT
...
```

### Bring the interface up

Bring the WireGuard interface up.
```sh
$ wg-quick up wg0
[#] ip link add wg0 type wireguard
[#] wg setconf wg0 /dev/fd/63
[#] ip -4 address add 10.99.0.1/24 dev wg0
[#] ip link set mtu 1420 up dev wg0
[#] firewall-cmd --zone internal --add-interface wg0
success
```

Verify the interface.
```sh
$ wg
interface: wg0
  public key: EgmmIi/UC6F/VlDU37/QpBO1zilROKPS2gLYdudgJFY=
  private key: (hidden)
  listening port: 51820
```

Enable the interface to start on boot.
```sh
systemctl enable wg-quick@wg0
```


## Setting up the client

Setting up the client is almost the same procedure as setting up the server. Install WireGuard on your client, generate the private and public keys in the `/etc/wireguard` directory. Create the `wg0.conf` with below content.

- Give your client an IP address in the VPN address range.
- Add the *client* private key.
- Add the *server* public key.
- Add the server public IP address

```ini{2,4,7,8}
[Interface]
Address = 10.99.0.2/24
SaveConfig = true
PrivateKey = <wg_private.key>

[Peer]
PublicKey = <server public key>
Endpoint = <server ip>:51820
AllowedIPs = 0.0.0.0/0
```
The `[Peer]` section is the configuration for connecting to the server. The `AllowedIPs` property is not only an IP filter, but also the subnets that is going to be routed through the VPN. The value `0.0.0.0/0` tells the client to route all traffic through the VPN.

No specific firewall configuration is needed.

Start the interface. 
```sh
wg-quick up wg0
```
::: warning
If you specified `0.0.0.0/0` as `AllowdIPs`, you will lose any SSH connections to the client. Go through the next step and setup the client on the server before activating the interface. To test your connection, you could run `wg-quick up wg0 && sleep 30 && wg-quick down wg0` and see where it goes.
:::

## Adding the client to the server

At this point, both the server and client is configured. The last step is to add the client to the server configuration. You can add the `[Peer]` section to the server configuration manually or run below command on the server.
```sh
wg set wg0 peer <client public key> allowed-ips 10.99.0.2
```

Because we have the `SaveConfig = true` option in the server configuration, WireGuard will save the running config to `wg0.conf`, when bringing down the interface. A `[Peer]` section will be added for each of your peers.


## Port Forwarding

You can forward connections on a giving port, from the server to a WireGuard client. Below exampels shows how to forward HTTP and HTTPS to the client we setup.
### Using Firewalld

On the server, enable masquerade on the internal interface and forward the ports you want. 
```sh
firewall-cmd --permanent --zone internal --add-masquerade
firewall-cmd --permanent --zone public --add-forward-port=port=443:proto=tcp:toport=443:toaddr=10.99.0.2
firewall-cmd --permanent --zone public --add-forward-port=port=80:proto=tcp:toport=80:toaddr=10.99.0.2
firewall-cmd --reload
```

Add below lines to the to the `[Interface]` section. This will add/remove the `wg0` interface on the internal zone on interface up/down. Remember to bring the interface down before editing `wg0.conf` or WireGuard will overwrite your changes.
```ini
[Interface]
PostUp = firewall-cmd --zone internal --add-interface wg0
PostDown = firewall-cmd --zone internal --remove-interface wg0
...
```
### Using Iptables

On the server, enable masquerade on the `wg0` interface and forward the ports you want.
```sh
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE
iptables -t nat -A PREROUTING -i <public interface> -p tcp --dport 80 -j DNAT --to-destination 10.99.0.2
iptables -t nat -A PREROUTING -i <public interface> -p tcp --dport 443 -j DNAT --to-destination 10.99.0.2
```
---