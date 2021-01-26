---
title: VPN mesh with Nebula
date: 2020-11-29 15:18:36
author: Patrick Kerwood
excerpt: Nebula is a VPN mesh technology that Slack has created and later open sourced. It is absolutly great for creating an overlay networks between nodes in different locations, whether it's Azure, Amazon, on-prem or in your garage. Even if your nodes are behind a NAT or firewall, Nebula will sprinkle som magic and punch a hole in that sucker.
type: post
blog: true
tags: [vpn, nebula]
---
Nebula is a VPN mesh technology that Slack has created and later open sourced. It is absolutly great for creating an overlay network between nodes in different locations, whether it's Azure, Amazon, on-prem or in your garage. Even if your nodes are behind a NAT or firewall, Nebula will sprinkle som magic and punch a hole in that sucker.

--- 

[[toc]]


[https://github.com/slackhq/nebula](https://github.com/slackhq/nebula)
> Nebula is a scalable overlay networking tool with a focus on performance, simplicity and security. It lets you seamlessly connect computers anywhere in the world. Nebula is portable, and runs on Linux, OSX, Windows, iOS, and Android. It can be used to connect a small number of computers, but is also able to connect tens of thousands of computers.

The only downside to Nebula is that you'll have to do everything by hand, creating certificates, copying them to the nodes, creating systemd unit files etc. Or you'll have to create the automation your self.

## Getting started
You can basically read the Github `README.md`, which will explain how stuff works, so I'm not going to repeat it here. 

I will point out though that you need a minimum of one "Lighthouse", a node that is reachable from anywhere. This is the node that will initiate the connections between nodes and which configuration will be slightly different from the others.

The Lighthouse node requires very few resources, so a $5 VPS at [Digital Ocean](https://www.digitalocean.com/) will be fine. That is in fact what I'm using.

## Setting up the Lighthouse
SSH into your Lighthouse node.

Go to the Github project [release page](https://github.com/slackhq/nebula/releases), download the binaries and extract them..

```sh
curl -LO https://github.com/slackhq/nebula/releases/download/v1.3.0/nebula-linux-amd64.tar.gz
tar -zxvf nebula-linux-amd64.tar.gz
```

This will unpack two binary files, `nebula` and `nebula-cert`. The first is the actual nebula service and the latter is used to create the CA and client certificates. Have a look at [step 3 and 4](https://github.com/slackhq/nebula#3-a-nebula-certificate-authority-which-will-be-the-root-of-trust-for-a-particular-nebula-network) of the `README.md` for more information.

Create the certificate authority. Below command creates the `ca.crt` and `ca.key` files.
```sh
./nebula-cert ca -name "Myorganization, Inc"
```

Create a client certificate for the Lighthouse node. Below command will create the `lighthouse01.crt` and `lighthouse01.key` files. This is also where you define the Nebula hostname, IP/Subnet and groups.
```sh
./nebula-cert sign -name lighthouse01 -ip 10.99.0.1/24
```
Create the `/etc/nebula` directory, move the client certificate and key into it and then move the `nebula` binary to `/usr/local/bin`. Also copy the `ca.crt` to keep it together with the config file. 

We'll keep the `ca.key` and a copy of the `ca.crt` in the working directory.
```sh
mkdir /etc/nebula
mv nebula /usr/local/bin
mv lighthouse01.crt lighthouse01.key /etc/nebula
cp ca.crt /etc/nebula
```

Download the example config file from Github.
```sh
curl -L -o /etc/nebula/config.yml https://raw.githubusercontent.com/slackhq/nebula/master/examples/config.yml
```
### Lighthouse config
Now we need to edit the config, I will go through the sections that needs to be edited for a minimum setup.
```sh
vim /etc/nebula/config.yml
```

Change below lines to match the files that got moved to `/etc/nebula`.
```yaml
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/lighthouse01.crt
  key: /etc/nebula/lighthouse01.key
```

Comment out below lines. We dont need them.
```yaml
# static_host_map:
#   "192.168.100.1": ["100.64.22.11:4242"]
```

Change the `am_lighthouse` property to `true` and comment out the IP address.
```yaml
lighthouse:
  am_lighthouse: true
  interval: 60
  hosts:
#    - "192.168.100.1"
```

The last part is the IP filter or firewall. You can keep it as is, but maybe comment out or delete the last rule.
```yaml
firewall:
  conntrack:
    tcp_timeout: 12m
    udp_timeout: 3m
    default_timeout: 10m
    max_connections: 100000

  outbound:
    # Allow all outbound traffic from this node
    - port: any
      proto: any
      host: any

  inbound:
    # Allow icmp between any nebula hosts
    - port: any
      proto: icmp
      host: any

     # Allow tcp/443 from any host with BOTH laptop and home group
#    - port: 443
#      proto: tcp
#      groups:
#        - laptop
#        - home
```

Save and quit.

### Starting Nebula with systemd

Now we just need to fire up Nebula. There's a systemd unit file in the Github project, lets use that.

```sh
curl -L -o /etc/systemd/system/nebula.service https://raw.githubusercontent.com/slackhq/nebula/master/examples/service_scripts/nebula.service
```
If you are using SELinux, you'll need to change the security context of the Nebula binary, or else systemd will not be able to execute it.
```sh
chcon -v -u system_u -t bin_t /usr/local/bin/nebula
```

Do a `daemon-reload` and start Nebula.
```sh
systemctl daemon-reload
systemctl start nebula
```

Your Lighthouse should be up and running, verify that Nebula runs.
```sh
systemctl status nebula
```

## Adding nodes to nebula

Adding nodes is almost the same process as before. Go the working directory, on the Lighthouse node, where `nebula-cert` is located and create a client certificate for the node.

Remember that its the certificate that determines the hostname, IP address and groups of the node. 
```sh
./nebula-cert sign -name "server1" -ip "10.99.0.2/24" -groups "servers,http"
```

This will create `server1.crt` and `server1.key`.

Now repeat the steps.
- SSH to the node and create the `/etc/nebula` directory. Copy the two newly created files and the original Lighthouse `ca.crt` file to the directory.
- Download the config file into `/etc/nebula`.
- Download the Nebula binary and move it the to `/usr/local/bin`. Remember to set the security context if you are using SELinux.
- Download the systemd unit file to `/etc/systemd/system/` and do a daemon reload.

Edit the config file which is a bit different than the Lighthouse config.

Change the paths.
```yaml
pki:
  ca: /etc/nebula/ca.crt
  cert: /etc/nebula/server1.crt
  key: /etc/nebula/server1.key
```

Set a static host map. The `10.99.0.1` is the Nebula IP and the `x.x.x.x` is the public IP, both belonging to the Lighthouse node.
```yaml
static_host_map:
  "10.99.0.1": ["x.x.x.x:4242"]
```

Change the IP of the `hosts` property to the Nebula IP of the Lighthouse.
```yaml{5}
lighthouse:
  am_lighthouse: false
  interval: 60
  hosts:
    - "10.99.0.1"
```

Here's an optional step. If you have a lot of interfaces on your node, eg. if you use Docker, you can limit the interfaces that Nebula will try and initiate a handshake on.
```yaml
lighthouse:
  ...
  local_allow_list:
    interfaces:
      eth0: true
```

Last step is to configure the firewall settings. They are pretty self explanatory, here's the example from the default config that allows TCP port 443 from any host with BOTH laptop and home groups.
```yaml
firewall:
  ...
  inbound:
    - port: 443
      proto: tcp
      groups:
        - laptop
        - home
```

Save and quit.

Start Nebula.
```sh
systemctl start nebula
```

Verify it started.
```sh
systemctl status nebula
```

Ping the Lighthouse on the Nebula IP.
```sh
ping 10.99.0.1
```
---