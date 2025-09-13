---
title: Setting Up an HA VPN Between Google Cloud and CentOS 9 with strongSwan and BIRD
date: 2025-09-14 14:43:09
author: Patrick Kerwood
excerpt: |
  In this guide, I’ll walk through setting up a site-to-site VPN between Google Cloud and a CentOS 9 VM hosted on DigitalOcean.
  We’ll use strongSwan to establish the IPsec tunnel, and the BIRD Internet Routing Daemon to peer with a Google Cloud Router and exchange routes dynamically using BGP.
type: post
blog: true
tags: [google, vpn]
meta:
- name: description
  content: Step-by-step guide to setting up a Google Cloud HA VPN with strongSwan and BIRD on CentOS 9 for secure multi-cloud connectivity using BGP.
---

{{ $frontmatter.excerpt }}

### VPN Options in Google Cloud
Google Cloud offers two types of VPN:
- **Classic VPN**: Supports only a single tunnel and static routing.
- **HA VPN**: Supports multiple redundant tunnels for high availability, and requires the BGP routing protocol for dynamic route exchange.

For this tutorial, we’ll use HA VPN but configure only a single tunnel.

## Provision the Remote VM
The first step is to provision the CentOS VM that will serve as our remote VPN peer.
This VM must have a public IP address so Google Cloud can establish a connection with it.
I’m using DigitalOcean, but you can use any provider or self-hosted CentOS machine with a public IP.

Here’s an example DigitalOcean CLI command to create a CentOS 9 VM, replace the SSH key and region with your own.

```sh
doctl compute droplet create gcp-vpn \
  --size s-1vcpu-2gb \
  --image centos-stream-9-x64 \
  --region ams3 \
  --ssh-keys 39:e5:cb:0c:6b:fa:ab:5b:03:be:42:6d:86:4b:ec:d5 \
  --wait
```

This command will return details about the VM, including its external IP address.
In this tutorial, the VM’s public IP is `64.227.72.229`.

## Configure Google Cloud VPN
We’ll now configure the VPN on the Google Cloud side using the [gcloud CLI](https://cloud.google.com/sdk/docs/install).
This approach makes the setup reproducible and scriptable.

### Authenticate and Set Project
Authenticate and set your working Google project.

```sh
gcloud auth login
gcloud config set project <your-project-id>
```

### Create the Cloud VPN Gateway
The Cloud VPN gateway is the Google-managed endpoint of the tunnel.
We’ll attach it to the `default` VPC network and place it in region `europe-west3`.

```sh
gcloud compute vpn-gateways create digital-ocean \
    --network=default \
    --region=europe-west3 \
    --stack-type=IPV4_ONLY
```
The command output will include two VPN interfaces. Save the IP address of `interface 0`, as we’ll use it when configuring the CentOS server.

### Define the peer VPN gateway

This represents the DigitalOcean VM. For HA setups, you could define multiple interfaces, but here we only need one.
Replace this IP with the address of your remote VM.

```sh
gcloud compute external-vpn-gateways create do-peer-1 \
   --interfaces 0=64.227.72.229
```
The VPN resources created can be found on the Google VPN product page. 

### Create a Cloud Router
Next we need to create the Cloud Router to handle BGP. The `region` and `network` should be the same as before and the
router must have a private ASN asigned, we will use `65000`.

```sh
gcloud compute routers create vpn-router \
    --region=europe-west3 \
    --network=default \
    --asn=65000
```

### Create the VPN tunnel
The tunnel ties together the VPN Gateway, Peer Gateway, and Cloud Router.
Choose a long and random shared secret, you’ll need the this secret again when configuring strongSwan.

```sh
 gcloud compute vpn-tunnels create do-tunnel-1 \
     --peer-external-gateway=do-peer-1 \
     --peer-external-gateway-interface=0 \
     --region=europe-west3 \
     --ike-version=2 \
     --shared-secret=mj6Ns6K3iiQgYPfSjW5G/hfyUmxn9sU7 \
     --router=vpn-router \
     --vpn-gateway=digital-ocean \
     --interface=0
```

### Attach the Tunnel to the Router 
Bind the Cloud Router to the VPN tunnel.
```sh
gcloud compute routers add-interface vpn-router \
   --interface-name=digital-ocean-do-tunnel-1 \
   --vpn-tunnel=do-tunnel-1 \
   --region=europe-west3
```

### Add a BGP Peer
Finally, define the BGP session with the remote peer (the CentOS VM). For the VM, we’ll use ASN `65001`.
```sh
gcloud compute routers add-bgp-peer vpn-router \
   --peer-name=do-peer-1 \
   --peer-asn=65001 \
   --interface=digital-ocean-do-tunnel-1 \
   --region=europe-west3
```

When this is done, Google assigns link-local IP addresses for the BGP session (one for each side).

### Verify BGP Settings

Run the follow command to verify the BGP peer configuration, note the link-local address for both the vpn-router and the
remote peer, we need that for later.

```sh{15,16}
$ gcloud compute routers describe vpn-router --region europe-west3
...
bgpPeers:
- bfd:
    minReceiveInterval: 1000
    minTransmitInterval: 1000
    multiplier: 5
    sessionInitializationMode: DISABLED
  enable: 'TRUE'
  enableIpv4: true
  enableIpv6: false
  interfaceName: digital-ocean-do-tunnel-1
  ipAddress: 169.254.19.149
  name: do-peer-1
  peerAsn: 65001
  peerIpAddress: 169.254.19.150
...
```

We’ll need the following information to configure the remote VM.
- Google Cloud Router IP: `169.254.19.149`, ASN `65000`
- CentOS VM IP (to configure): `169.254.19.150`, ASN `65001`
- IPsec shared secret: `mj6Ns6K3iiQgYPfSjW5G/hfyUmxn9sU7`

## Configure the remote peer (CentOS VM)

With the Google Cloud side ready, it’s time to prepare the CentOS VM on DigitalOcean.

The main steps are:
- Enable packet forwarding in the kernel.
- Create an XFRM interface for the IPsec tunnel.
- Install and configure strongSwan.
- Install and configure BIRD for BGP.

### Enable packet forwarding
By default, Linux won’t forward packets between interfaces. Since our VM will route traffic between its NIC and the VPN tunnel, we need to enable forwarding.
To enable it immediately (until next reboot):

```sh
sysctl -w net.ipv4.ip_forward=1
``` 

To make the change permanent across reboots, add the following config file:
```sh
cat << EOF > /etc/sysctl.d/99-forwarding.conf
net.ipv4.ip_forward = 1
EOF
```

### Create an XFRM interface
XFRM interfaces allow Linux to treat IPsec tunnels like standard network devices (similar to GRE or WireGuard).
This makes routing and BGP integration much simpler.

We’ll create a systemd unit so the interface comes up automatically on boot.
Save the following as `/etc/systemd/system/ipsec0-interface.service`.

Replace the IPs in the `ip addr add` command with the link-local addresses assigned by Google.

```ini{10}
[Unit]
Description=Interface ipsec0 XFRM setup
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ip link add ipsec0 type xfrm dev eth0 if_id 100
ExecStart=/usr/sbin/ip link set dev ipsec0 mtu 1436
ExecStart=/usr/sbin/ip addr add 169.254.19.150/30 remote 169.254.19.149/30 dev ipsec0
ExecStart=/usr/sbin/ip link set up ipsec0
ExecStop=/usr/sbin/ip link del ipsec0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

- `if_id 100`: ID for binding the IPsec traffic to this interface.
- `mtu 1436`: sets MTU slightly lower than normal to account for IPsec overhead.
- `169.254.19.150/30`: the link-local IP for our VM.
- `169.254.19.149/30`: the link-local IP for the Google Cloud Router.

Reload systemd and enable the service:
```sh
systemctl daemon-reload
systemctl enable ipsec0-interface.service --now
```

Verify the interface was created.

```sh
$ ip address show ipsec0
4: ipsec0@eth0: <NOARP,UP,LOWER_UP> mtu 1436 qdisc noqueue state UNKNOWN group default qlen 1000
    link/none
    inet 169.254.19.150 peer 169.254.19.149/30 scope global ipsec0
       valid_lft forever preferred_lft forever
    inet6 fe80::adbe:6a1d:1176:fc40/64 scope link stable-privacy
       valid_lft forever preferred_lft forever
```

## Install and Configure strongSwan (IPsec tunnel)
Now that the XFRM interface is in place, we can configure the actual IPsec tunnel. We’ll use strongSwan, a popular and reliable implementation of IPsec.

First, enable the EPEL repository and install strongSwan:
```sh
dnf install epel-release
dnf install strongswan strongswan-sqlite
```

### Configure the tunnel
strongSwan relies on configuration files located at `/etc/strongswan/swanctl/conf.d/`.
To set up a new configuration, create a file named `gcp.conf` in this directory and include the following content.

Modify the values to match your setup:
- `64.227.72.229`: The external IP if the VM.
- `34.157.50.13`: The Google Cloud VPN Gateway IP from earlier.
- `mj6Ns6K3iiQgYPfSjW5G/hfyUmxn9sU7`: the shared secret you defined when creating the tunnel in Google Cloud.

```{4,7,16,21,53,56}
connections {
  gcp_tun1 {
    # The external IP of this server
    local_addrs = 64.227.72.229

    # The IP address of Gateway resources interface 0
    remote_addrs = 34.157.50.13

    # IDs for the XFRM virtual interface.
    if_id_out = 100
    if_id_in = 100

    # Both local and remote peer authenticate with PSK
    # The id fields must match what each side expects as the IKE identit
    local {
      id = 64.227.72.229 
      auth = psk
    }

    remote {
      id = 34.157.50.13
      auth = psk
    }

    # IPsec Policy
    children {
      gcp_tun1 {
        # This allows all traffic in the tunnel from both ends
        local_ts = 0.0.0.0/0
        remote_ts = 0.0.0.0/0

        # ESP (IPsec) encryption & integrity
        esp_proposals = aes256gcm16-sha512-modp8192

        # The tunnel won’t initiate immediately, but if traffic matches the selectors,
        # it will trigger negotiation.
        start_action = trap
      }
  }

  # Uses IKEv2 for negotiation.
  version = 2

  # IKE SA crypto suite
  proposals = aes256gcm16-sha512-modp4096
  }
}

# Pre-shared key for the tunnel
secrets {
  ike-gcptun1 {
    # Remote IKE identity
    id = 34.157.50.13

    # The pre-shared used when creating the VPN tunnel resource in Google.
    secret = "mj6Ns6K3iiQgYPfSjW5G/hfyUmxn9sU7"
  }
}
```

### Verify the tunnel

Enable strongSwan on boot and start it now.
```sh
systemctl enable strongswan --now
```

Check that the tunnel is active by running the following command.

```sh
$ swanctl -L
gcp_tun1: IKEv2, no reauthentication, rekeying every 14400s
  local:  64.227.72.229
  remote: 34.157.50.13
  local pre-shared key authentication:
    id: 64.227.72.229
  remote pre-shared key authentication:
    id: 34.157.50.13
  gcp_tun1: TUNNEL, rekeying every 3600s
    local:  0.0.0.0/0
    remote: 0.0.0.0/0
```
You can also verify this in the Google Cloud Console, go to the VPN product page, open the Cloud VPN Tunnels tab, and locate your tunnel.
The VPN tunnel status should show *Established* along with a green checkmark.

## Install and Configure BIRD (BGP routing)
At this point, the IPsec tunnel is established, traffic can flow, but neither side yet knows which routes are available.
To resolve this, we’ll use BGP with BIRD routing daemon.

In this section, rather than providing a complete BIRD configuration upfront, we’ll build it step by step, showing the results at each stage.

Start by installing BIRD using the following command.
```sh
dnf install bird
```

### Set the Router ID
Let’s start simple, open `/etc/bird.conf`.
About 15 lines down, you’ll find the router id setting. This ID is typically an IP address assigned to the router. Uncomment it and set it to the server’s external IP address.

```
router id 64.227.72.229;
```

### Add the BGP Peer
Next, add the following block of configuration to set up the peer for the Google Cloud Router.
- `local`: The link-local address provided by Google and the ASN you assigned to this server.
- `neighbor`: The link-local address assigned to the Cloud Router and its corresponding ASN.

The `ipv4` block defines which routes are imported and exported to the routing table. We’ll revisit and modify this later, but for now, leave it as is.
```{3,4}
protocol bgp gcp_vpn {
        description "GCP HA VPN";
        local 169.254.43.246 as 65001;
        neighbor 169.254.43.245 as 65000; 
        hold time 20;
        ipv4 {
                import all;
                export all;
        };
}
```

Save the file, then enable and start BIRD. The BGP session should now be established.
```
systemctl enable bird --now
```

### Verify the BGP Session
Run the following to check if the BGP session is up.

```sh
birdc show protocols all gcp_vpn
```

You should see `BGP state: Established` along with the details of the peer.
```{5}
Name       Proto      Table      State  Since         Info
gcp_vpn    BGP        ---        up     17:25:48.512  Established
  Description:        GCP HA VPN
  Created:            17:25:44.461
  BGP state:          Established
    Neighbor address: 169.254.19.149
    Neighbor AS:      65000
    Local AS:         65001
    Neighbor ID:      169.254.19.149
...
```

### View Learned Routes

Running the following command will display the routes that BIRD has learned.
```sh
birdc show route
```
You should see the subnet that corresponds to the region where the Cloud Router is deployed.
```
Table master4:
10.156.0.0/20        unicast [gcp_vpn 18:29:53.482] * (100) [AS65000?]
        via 169.254.19.149 on ipsec0
```
If you want to advertise additional subnets from other regions within the same VPC, you can edit the Cloud Router resource and add those subnets to the advertised list.

Running the `ip route` command will show that BIRD has successfully added the route to the routing table.
```
$ ip route
...
10.156.0.0/20 via 169.254.19.149 dev ipsec0 proto bird metric 32
```

### Advertising Routes
So far, the CentOS VM is learning routes from Google Cloud. However, it’s not yet advertising any routes back, Google still doesn’t know which networks exist on your VM side. That’s what we’ll configure next.

By default, Bird isn’t advertising any networks to Google Cloud. To verify this.
```
birdc show route export gcp_vpn
```

You’ll likely see nothing. You can also confirm in the Google Cloud Console under Cloud Router → Advertised routes, it will be empty.

### Enable direct route export

Go back and edit the `/etc/bird.conf` file.

Inside, you’ll find a section like the one below. This configuration block exports all directly connected routes that the server is part of, but it is disabled by default.
Uncomment the `disabled` configuration to enable it.

Since IPv6 is out of scope for this tutorial, you can also comment out the IPv6 section.
```{2,4}
protocol direct {
        #disabled;               # Disable by default
        ipv4;                    # Connect to default IPv4 table
        #ipv6;                   # ... and to default IPv6 table
}
```

Save the file and restart BIRD.
```
systemctl restart bird
```

Now check again, you should see all connected networks.
```
$ birdc show route export gcp_vpn
BIRD 3.1.2 ready.
Table master4:
64.227.64.0/20       unicast [direct1 19:13:32.461] * (240)
        dev eth0
10.18.0.0/16         unicast [direct1 19:13:32.461] * (240)
        dev eth0
10.133.0.0/16        unicast [direct1 19:13:32.461] * (240)
        dev eth1
169.254.19.148/30    unicast [direct1 19:13:32.461] * (240)
        dev ipsec0
```

### Apply a route filter
Now BIRD is advertising all directly connected routes from the server.
But if you want to advertise only the `10.18.0.0/16` route, you’ll need to add a filter to the export configuration.

Edit the `/etc/bird.conf` file and add the following filter block. Then, update the export configuration to use `filter local_filter`.

```{1-4,13}
filter local_filter {
        if (net ~ [10.18.0.0/16]) then accept;
        reject;
}

protocol bgp gcp_vpn {
        description "GCP HA VPN";
        local 169.254.43.246 as 65001;
        neighbor 169.254.43.245 as 65000; 
        hold time 20;
        ipv4 {
                import all;
                export filter local_filter;
        };
}
```

Save the file and restart BIRD again.
```
systemctl restart bird
```

Check the exported routes again and you should only see the `10.18.0.0/16` route.

```
$ birdc show route export gcp_vpn
BIRD 3.1.2 ready.
Table master4:
10.18.0.0/16         unicast [direct1 19:13:32.461] * (240)
        dev eth0
```
### Clean up duplicate routes

If you run the ip route command, you may see all your routes listed twice.
This happens because BIRD learns all routes from the kernel and then exports them again.
```
$ ip route
default via 64.227.64.1 dev eth0 proto static metric 100
10.18.0.0/16 dev eth0 proto bird scope link metric 32
10.18.0.0/16 dev eth0 proto kernel scope link src 10.18.0.6 metric 100
10.133.0.0/16 dev eth1 proto bird scope link metric 32
10.133.0.0/16 dev eth1 proto kernel scope link src 10.133.0.13 metric 101
10.156.0.0/20 via 169.254.19.149 dev ipsec0 proto bird metric 32
10.198.0.0/20 via 169.254.19.149 dev ipsec0 proto bird metric 32
64.227.64.0/20 dev eth0 proto bird scope link metric 32
64.227.64.0/20 dev eth0 proto kernel scope link src 64.227.72.229 metric 100
169.254.19.148/30 dev ipsec0 proto kernel scope link src 169.254.19.150
169.254.19.148/30 dev ipsec0 proto bird scope link metric 32
```

While this doesn’t cause any functional issues, it can be annoying to see. Let’s fix it.

In the `protocol kernel` block, filter all exports by replacing `export all` with a filter.
The configuration below will now export only BGP-learned routes.

```{5-8}
protocol kernel {
        ipv4 {                    # Connect protocol to IPv4 table by channel
#               table master4;    # Default IPv4 table is master4
#               import all;       # Import to table, default is import all
                export filter {
                        if source = RTS_BGP then accept;  # only export BGP-learned routes
                        reject;                           # reject everything else
                };
        };
#       learn;                  # Learn alien routes from the kernel
#       kernel table 10;        # Kernel table to synchronize with (default: main)
}
```

Restart BIRD one last time:

```
systemctl restart bird
```
Now your routing table will be clean, only real BGP-learned and exported routes remain.

You now have a fully functional IPsec VPN tunnel between Google Cloud and your CentOS server, with dynamic BGP routing for subnet advertisement.
This setup allows communication between your Google Cloud VPC and on-premises infrastructure, with the flexibility to advertise exactly the subnets you want.


## References
- [Google: Create an HA VPN gateway to a peer VPN gateway](https://cloud.google.com/network-connectivity/docs/vpn/how-to/creating-ha-vpn)
- [BIRD Internet Routing Protocol](https://bird.network.cz/)
- [XFRM Interfaces on Linux](https://docs.strongswan.org/docs/latest/features/routeBasedVpn.html#_xfrm_interfaces_on_linux)
---

