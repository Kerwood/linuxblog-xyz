---
title: "Talos and Cilium with BGP Load Balancing on MikroTik"
description: "Build a Talos Kubernetes cluster on Proxmox with Cilium as CNI, and announce LoadBalancer Services to a MikroTik router over BGP with ECMP across the worker nodes, with the Cilium Gateway on top."
date:
  created: 2026-11-07 22:00:00
authors:
  - kerwood
slug: talos-cilium-bgp-mikrotik
categories:
  - "Kubernetes"
  - "Networking"
tags:
  - "kubernetes"
  - "networking"
  - "proxmox"
---

In this post, I’ll build a Talos Linux Kubernetes cluster on Proxmox with Cilium as the CNI, and use BGP to announce LoadBalancer Services to a MikroTik router. The router learns a route to every Service IP through each of the workers, and spreads the traffic across them with ECMP. On top of that, the Cilium Gateway routes host names to applications behind a single IP.

<!-- more -->




Out of the box, a `type: LoadBalancer` Service on a bare-metal cluster stays at `EXTERNAL-IP <pending>` forever.
There is no cloud provider to hand out an IP and point a load balancer at the nodes. Something inside the cluster
has to do that job.

Cilium can do it on its own. Its LB-IPAM feature hands out IPs to LoadBalancer Services from a pool you define,
and its BGP control plane announces those IPs to your router. The router then knows that the Service IP lives
behind the worker nodes, and since every worker announces it, the router gets several equal routes and load
balances between them.

The setup in this post consists of the following.

| Component   | Version                           |
|-------------|-----------------------------------|
| Talos Linux | v1.14.5                           |
| Kubernetes  | 1.36.5                            |
| Cilium      | 1.20.4                            |
| RouterOS    | 7.23 (BGP multipath needs 7.22+)  |

## Architecture

The setup involves three networks, and the router connects all of them.

- **The client network, `10.0.10.0/24`.** This is the existing network where laptops, phones and everything else
  lives. The router is the default gateway.
- **The node network, VLAN 30, `10.0.30.0/24`.** The three Talos VMs live here, with the router at `10.0.30.1` as
  their default gateway. Proxmox puts the VMs on the VLAN by tagging their network devices with `30`.
- **The Service network, `10.0.100.0/24`.** This is where the LoadBalancer Services get their IPs. It is not a
  network in the usual sense, since no device has an address in it. It only exists as routes on the router.

The two workers each open a BGP session to the router. When a LoadBalancer Service gets an IP, say `10.0.100.10`,
both workers announce `10.0.100.10/32` with themselves as the next hop. The router now has two equal routes for
the same IP, and installs both as one ECMP route.

When a client on `10.0.10.0/24` connects to `10.0.100.10`, the traffic goes to its default gateway, the router.
The router hashes the connection to one of the two workers, and Cilium on that worker delivers it to a pod behind
the Service. The reply goes back the same way.

Only the workers speak BGP. The control plane never announces anything, so it never receives Service traffic.

### Why the Nodes Need Their Own Network

It is tempting to put the nodes on the client network, but that breaks in a subtle way.

A request from a client to `10.0.100.10` goes through the router, since that is the only place the route exists.
The reply from the worker, however, is addressed to the client, and if the client sits on the same network as the
worker, the reply is delivered directly, without passing the router. The router only ever sees half of the TCP
connection. Its connection tracking marks it as invalid and drops it. On top of that, the router notices that it is
forwarding traffic back out the same interface it came in on, and starts sending ICMP redirects that bypass ECMP
entirely.

Putting the nodes on their own network makes the traffic symmetric. The client and the worker are on different
networks, so both directions have to go through the router. That is why the nodes live on VLAN 30. A VLAN makes it
possible to have a separate network for the nodes without separate cables or switches, since the router and Proxmox
simply tag the traffic.

!!! info "Any separate network will do"

    This post uses VLAN 30 for the nodes, but there is nothing special about it. Any network that is separate from
    the clients and routed by the router works the same way, whether it is another VLAN ID or a dedicated port on
    the router. Creating the VLAN on the router, the switch and the Proxmox bridge is out of scope for this post, so
    it is assumed to be in place already, with DHCP on `10.0.30.0/24`.

### Why the Services Need Their Own Range

The Service IPs can’t come from the client network or the node network either, for the same reason in reverse.

If a Service IP was inside `10.0.10.0/24`, a client would consider it a neighbour on its own network. Instead of
sending the traffic to the router, it would send an ARP request asking who has the IP. In BGP mode, nobody answers
ARP for a Service IP, so the connection never gets anywhere. The same goes for the router and the nodes on
`10.0.30.0/24`.

So the Service IPs need a range of their own that no device sits on, which is `10.0.100.0/24` in this post. Every
client and every node then sees it as a remote network, and sends the traffic to its default gateway, which is
exactly the router that has the BGP routes. There is nothing special about `10.0.100.0/24` itself. Any range works,
as long as it is unused in your network and doesn’t overlap the pod CIDR `10.244.0.0/16` or the Service CIDR
`10.96.0.0/12` inside the cluster.

The range shows up in two places later, and they must match. Cilium hands out IPs from it, and the router only
accepts BGP routes inside it.

## IP Plan

| What                    | Value                   | Notes                                        |
|-------------------------|-------------------------|----------------------------------------------|
| Clients                 | 10.0.10.0/24            | Your existing network                        |
| Kubernetes nodes        | VLAN 30, 10.0.30.0/24   | Gateway 10.0.30.1 on the router              |
| Kubernetes API VIP      | 10.0.30.20              | Held by the control plane                    |
| talos-cp-1              | 10.0.30.21              | MAC `BC:24:11:30:00:21`                      |
| talos-w-1               | 10.0.30.22              | MAC `BC:24:11:30:00:22`                      |
| talos-w-2               | 10.0.30.23              | MAC `BC:24:11:30:00:23`                      |
| LoadBalancer pool       | 10.0.100.0/24           | Only exists as BGP routes                    |
| Gateway IP              | 10.0.100.20             | From the LoadBalancer pool                   |
| Pod CIDR                | 10.244.0.0/16           | Talos default, never leaves the cluster      |
| Service CIDR            | 10.96.0.0/12            | Talos default, internal                      |
| Router AS               | 64512                   | Private AS, used by the router               |
| Cluster AS              | 64513                   | Private AS, shared by all workers            |

The nodes get their IPs from the DHCP server on the router. Each VM gets a static MAC address and a static lease,
so the DHCP server stays the single source of truth for addressing. The Kubernetes API VIP is the exception. It is
not handed out by the DHCP server, **so make sure it is outside the DHCP pool.**

## Mikrotik Configuration

This assumes VLAN 30 already exists on the router as an interface called `vlan30`, with the address `10.0.30.1/24`
and a DHCP server on it.

### Static Leases

```
/ip dhcp-server lease
add address=10.0.30.21 comment=talos-cp-1 mac-address=BC:24:11:30:00:21 server=vlan30
add address=10.0.30.22 comment=talos-w-1 mac-address=BC:24:11:30:00:22 server=vlan30
add address=10.0.30.23 comment=talos-w-2 mac-address=BC:24:11:30:00:23 server=vlan30
```

!!! info "Inside or outside the pool"

    Static leases only need to be inside the DHCP network, not inside the pool. A static lease reserves its address
    either way, but keeping the nodes outside the pool means the address can’t already be handed out to another
    client before the static lease is created.

### BGP Instance

The `multipath` setting is the maximum number of equal routes to install for the same prefix, which is what gives us
ECMP. With `4`, the router spreads the traffic across up to four workers, which leaves room to add two more. If you
plan to run more BGP workers than that, increase it, otherwise the extra workers still announce the routes but only
act as backups, receiving no traffic until one of the first four goes away.

```
/routing bgp instance
add name=talos as=64512 router-id=10.0.30.1 multipath=4
```

### BGP Filters

The input filter should only accept `/32` routes inside the LoadBalancer pool. That protects the rest of the network from a
misconfigured cluster, like one announcing a default route or the client network. The output filter rejects
everything, since the nodes use the router as their default gateway and don’t need any routes from it.

```
/routing filter rule
add chain=talos-in rule="if (dst in 10.0.100.0/24 && dst-len == 32) { accept }"
add chain=talos-in rule="reject"
add chain=talos-out rule="reject"
```

### BGP Connection

Instead of configuring one connection per worker, the router can listen for peers from a whole subnet. Nodes `.16` to
`.31` fit in `10.0.30.16/28`, so new workers can peer without touching the router.

```
/routing bgp connection
add name=talos instance=talos local.role=ebgp local.address=10.0.30.1 \
    remote.address=10.0.30.16/28 remote.as=64513 \
    connect=no listen=yes hold-time=9s keepalive-time=3s \
    input.filter=talos-in \
    output.filter-chain=talos-out
```

With `connect=no` and `listen=yes`, the router never opens a session itself, it only accepts sessions opened by the
workers. Each worker that connects from the subnet gets its own session. The control plane is inside the subnet as
well, but since it doesn’t run BGP, it never connects.

The timers are much shorter than the defaults on purpose. Each side sends a keepalive every 3 seconds, and if
nothing is heard for 9 seconds, the session is torn down and that worker’s routes are withdrawn. With the defaults,
a dead worker could stay in the ECMP group for minutes.

!!! info

    Planned shutdowns, like a drain or a reboot, close the session immediately, so the timers only matter when a
    node dies.

If your firewall has a default drop rule on the input chain, allow TCP port 179 from the nodes, otherwise the
sessions never come up. The source range is the same subnet the router listens for peers on.

```
/ip firewall filter
add chain=input action=accept protocol=tcp dst-port=179 src-address=10.0.30.16/28 \
    in-interface=vlan30 place-before=0 comment="BGP from Talos workers"
```

### ECMP Hash Policy (Optional)

This step is optional. Everything works with the default hash policy, but changing it gives a more even spread of
the traffic when there are only a few clients.

With several equal routes for the same IP, the router has to pick one for every connection. It hashes some fields of
the packets, and the result picks which of the equal routes to use. Packets with the same fields always get the same
route, which is what keeps a TCP connection on the same worker.

| Policy         | Hashes on                                                        | Spreads traffic |
|----------------|------------------------------------------------------------------|-----------------|
| `l3` (default) | Source IP and destination IP                                     | Per client      |
| `l4`           | Source and destination IP, protocol, source and destination port | Per connection  |

With the default `l3`, everything from one client to a Service IP takes the same route, so a single busy client
always loads a single worker. With `l4`, the source port is part of the hash too, and since every new connection
gets a new source port, each connection can land on a different worker. That gives a much more even spread, even
with only a handful of clients. Each connection still stays on one worker for as long as it lives.

```
/ip settings set ipv4-multipath-hash-policy=l4
```

The setting is global for the router, so it applies to every ECMP route, not only the ones from the cluster.

There is a catch with `l4`. The default RouterOS firewall has a FastTrack rule, which moves established connections
onto a fast path that skips most of the router’s processing. The handshake goes through the normal path and follows
the `l4` hash. Once the connection is FastTracked, it is forwarded by FastPath, which
[caches routes by destination address only](https://manual.mikrotik.com/docs/cli-reference/ip/settings/), so it may
pick a different worker than the `l4` hash did for the handshake. That worker has never seen the connection and
answers with a reset, so clients randomly get `Connection reset by peer`.

The fix is to keep the traffic to and from the LoadBalancer pool off FastTrack, with two accept rules placed before
the FastTrack rule.

```
/ip firewall filter
add chain=forward action=accept connection-state=established,related \
    dst-address=10.0.100.0/24 place-before=[find action=fasttrack-connection] \
    comment="no fasttrack for BGP LB pool"
add chain=forward action=accept connection-state=established,related \
    src-address=10.0.100.0/24 place-before=[find action=fasttrack-connection] \
    comment="no fasttrack for BGP LB pool"
```

The Service traffic now goes through the normal routing path, where every packet follows the `l4` hash. Everything
else keeps FastTrack. The cost is a bit more CPU on the router for the Service traffic, which is nothing to worry
about at homelab scale.

## Building the Talos Image

Talos images are built by the [Image Factory](https://factory.talos.dev). We need the QEMU guest agent extension, so
Proxmox can see the IP of the VMs and shut them down gracefully.

Go to [factory.talos.dev](https://factory.talos.dev) and click through the wizard.

1. **Hardware Type:** Cloud Server.
2. **Talos Linux Version:** 1.14.5.
3. **Cloud:** Nocloud.
4. **Machine Architecture:** amd64, with SecureBoot left off.
5. **System Extensions:** search for and select `siderolabs/qemu-guest-agent`.
6. **Customization:** leave the extra kernel arguments empty.

The last page shows the schematic ID. With only the guest agent extension, it is always the same.

```sh
SCHEMATIC=ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
TALOS=v1.14.5
```

Download the ISO and upload it to the ISO storage in Proxmox, or download it directly on the Proxmox host.

```sh
curl -Lo talos-$TALOS-nocloud-amd64.iso \
  https://factory.talos.dev/image/$SCHEMATIC/$TALOS/nocloud-amd64.iso
```

## Creating the VMs

Create the three VMs in the Proxmox UI and boot them from the Talos ISO.

| VM         | Size                    |
|------------|-------------------------|
| talos-cp-1 | 2 vCPU / 2 GB / 10 GB   |
| talos-w-1  | 2 vCPU / 2 GB / 10 GB   |
| talos-w-2  | 2 vCPU / 2 GB / 10 GB   |

These are proof-of-concept sizes, just enough to run Talos, Cilium and a test app. 2 GB of memory, 2 cores and a
10 GB disk is the minimum Talos asks for on a control plane node, and the
[recommended sizes](https://docs.siderolabs.com/talos/v1.14/getting-started/system-requirements) are a lot larger,
so give the nodes more if you plan to run real workloads on them.

There are a few settings you need to get right.

- **MAC address:** set the static MAC address from the IP plan on the network device, so the VM gets its static
  lease from the DHCP server.
- **VLAN tag:** set it to `30` on the same network device, so the VM ends up on the node network.
- **QEMU Guest Agent:** enable it under **System** in the create wizard, or later under **Options**.
- **CPU type:** leave it at the default `x86-64-v2-AES`. Talos requires the x86-64-v2 instruction set, so don’t pick
  the old `kvm64` type, which makes the VM hang during boot at 100% CPU. `host` works too, but it ties the VM to the
  host’s CPU model and can block live migration between different hosts.
- **Ballooning:** untick **Ballooning Device** under **Memory** in the create wizard. It is hidden until you tick
  **Advanced** at the bottom of the wizard. Kubernetes schedules workloads based on the memory the node reports, and memory the
  hypervisor takes back later is not something it can plan around.

Since all three VMs are identical, you only need to create the first one. Before starting it, right-click it and
choose **Clone** to create the other two. A clone gets a new random MAC address, so remember to change it to the
static MAC address from the IP plan under **Hardware**, **Network Device**, before starting the clone.

Start the VMs. Each one boots into maintenance mode, gets its IP from the static lease and waits for a machine
configuration.

## Generating the Talos Configuration

Talos ships with Flannel as its CNI and kube-proxy for Services. Cilium replaces both, so they need to be turned off.

The control plane also gets a virtual IP for the Kubernetes API. The API endpoint is baked into every config file
and every kubeconfig, and if it points at the IP of a single node, that node can never be replaced. With a VIP, the
endpoint never has to change, and more control plane nodes can be added later.

Talos has the VIP built in. All control plane nodes get the same VIP in their config and hold an election through
etcd. The winner adds the VIP to its network interface and announces it with gratuitous ARP. If that node goes away,
another control plane node takes over the VIP. Note that this is plain layer 2, and it has nothing to do with BGP or
Cilium.

The VIP is assigned to a network interface, so we need its name. Check it on the control plane node.

```sh
talosctl get links --insecure -n 10.0.30.21
```

Verify that the physical interface with the MAC address from the IP plan is called `eth0`. If it has another name,
use that in the patch below.

Create `patches/controlplane.yaml`.

```yaml
# No Flannel and no kube-proxy, Cilium replaces both.
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
$patch: delete
---
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
---
# Virtual IP for the Kubernetes API.
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: 10.0.30.20 # The virtual IP
link: eth0       # The interface to announce it on
```

Create `patches/worker.yaml`. It puts a label on the workers, which Cilium uses later to decide which nodes speak
BGP.

```yaml
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  bgp: enabled
```

Generate the secrets and the configuration. The second argument to `gen config` is the Kubernetes API endpoint,
which is the VIP. The `$SCHEMATIC` and `$TALOS` variables are the ones set in
[Building the Talos Image](#building-the-talos-image).

```sh
SCHEMATIC=ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
TALOS=v1.14.5
K8S=1.36.5

talosctl gen secrets -o secrets.yaml

talosctl gen config homelab https://10.0.30.20:6443 \
  --with-secrets secrets.yaml \
  --install-image factory.talos.dev/nocloud-installer/$SCHEMATIC:$TALOS \
  --kubernetes-version $K8S \
  --config-patch-control-plane @patches/controlplane.yaml \
  --config-patch-worker @patches/worker.yaml
```

The Kubernetes version is pinned on purpose. Talos 1.14 defaults to Kubernetes 1.37, but at the time of writing,
Cilium 1.20 is only tested up to 1.36. Note that it has to be the full patch version, since `1.36` on its own is
not a valid image tag.

Keep `secrets.yaml`, `controlplane.yaml` and `talosconfig` somewhere safe. They contain the keys to the cluster.

## Installing Talos

Apply the configuration to the nodes. They are still in maintenance mode, which is why `--insecure` is needed.

```sh
talosctl apply-config --insecure -n 10.0.30.21 -f controlplane.yaml
talosctl apply-config --insecure -n 10.0.30.22 -f worker.yaml
talosctl apply-config --insecure -n 10.0.30.23 -f worker.yaml
```

Each node installs Talos to its disk and reboots. If a VM boots into the ISO again, move the disk before the
CD-ROM in the boot order under **Options**, or remove the ISO from the VM.

Next, set up `talosctl` to talk to the cluster. Merge the generated `talosconfig` into your default talosconfig file
at `~/.talos/config`. The cluster is added as a new context and becomes the current one, so `talosctl` works from
any directory.

```sh
talosctl config merge ./talosconfig
```

!!! tip "Optionally, keep the talosconfig local"

    Instead of merging, you can point `talosctl` at the file in the current directory with the `TALOSCONFIG`
    environment variable. This keeps the cluster’s credentials together with the rest of its files, and the endpoint
    and node are then written to `./talosconfig`. The variable only lives in the current shell, and since the path is
    relative, run `talosctl` from the cluster directory and export it again in a new terminal.

    ```sh
    export TALOSCONFIG=./talosconfig
    ```

Then set the endpoint and the default node. The endpoint is where `talosctl` connects, and the node is the default
target for commands when you don't give `-n`.

```sh
talosctl config endpoint 10.0.30.21
talosctl config node 10.0.30.21
```

The `talosctl` endpoint is the IP of the control plane node and not the VIP. The VIP only exists while etcd is
running, and if etcd ever breaks, `talosctl` is the tool you need to fix it.

Setting the default node to the control plane only is on purpose. Commands like `reboot` and `upgrade` would
otherwise hit every node at once.

!!! warning "Multiple control plane nodes"

    The bootstrap command below is only run against one control plane node, even when there are more. It creates the etcd
    cluster, and the other control plane nodes find it and join it on their own. Running it on more than one node
    would create separate etcd clusters that never join up.

    The endpoint, on the other hand, can list all the control plane nodes.

    ```sh
    talosctl config endpoint 10.0.30.21 10.0.30.24 10.0.30.25
    ```

Bootstrap etcd on the control plane. This is done exactly once, for the lifetime of the cluster.

```sh
talosctl bootstrap
```

Once etcd is up, the control plane node claims the VIP. Check that all three nodes have found each other, and that
the VIP is in place. Talos nodes discover the other members of the cluster on their own, so this works before
Kubernetes is fully up.

```sh
talosctl get members
```

```
NODE         NAMESPACE   TYPE     ID              VERSION   HOSTNAME        MACHINE TYPE   OS                ADDRESSES
10.0.30.21   cluster     Member   talos-m6q-4yv   1         talos-m6q-4yv   worker         Talos (v1.14.5)   ["10.0.30.23"]
10.0.30.21   cluster     Member   talos-u82-vcs   1         talos-u82-vcs   worker         Talos (v1.14.5)   ["10.0.30.22"]
10.0.30.21   cluster     Member   talos-wn4-y6u   2         talos-wn4-y6u   controlplane   Talos (v1.14.5)   ["10.0.30.20","10.0.30.21"]
```

There should be one member per node. The control plane node lists the VIP `10.0.30.20` next to its own IP. If a
node is missing, check that the config was applied to it and that it can reach the control plane.

Then fetch the kubeconfig, which points at the VIP. Without any arguments it
is merged into `~/.kube/config` and set as the current context.

```sh
talosctl kubeconfig
```

!!! tip "Optionally, keep the kubeconfig local"

    Instead of merging, give `talosctl kubeconfig` a directory to write a `kubeconfig` file there, and point
    `kubectl` at it with the `KUBECONFIG` environment variable. Just like with `TALOSCONFIG`, the variable only lives
    in the current shell and the path is relative to the cluster directory.

    ```sh
    talosctl kubeconfig .
    export KUBECONFIG=./kubeconfig
    ```

Get the nodes.

```sh
kubectl get nodes
```

All three nodes show up as `NotReady`. That is expected, since there is no CNI yet. Don’t wait for
`talosctl health` to pass either, it won’t until Cilium is installed.

## Installing Cilium

Cilium is installed with its official Helm chart. All the settings go into a single values file, which makes it
easy to keep in Git. The Cilium CLI can also install Cilium, but it uses the same Helm chart under the hood, so going with Helm
directly keeps things transparent.

### The Helm Values

Create `cilium-values.yaml`. It is split into four parts, the settings Talos requires, the datapath, BGP and the
Gateway API.

```yaml
# --- Talos specifics ---

# Use the per-node pod CIDRs from Talos' pod subnet (10.244.0.0/16).
# Cilium's default cluster-pool uses 10.0.0.0/8, which overlaps the networks.
ipam:
  mode: kubernetes

# kube-proxy is disabled in Talos, Cilium implements Services in eBPF instead.
kubeProxyReplacement: true

# Without kube-proxy, Cilium can't reach the API through 10.96.0.1, since Cilium
# is what makes that ClusterIP work. KubePrism on localhost:7445 solves this.
k8sServiceHost: localhost
k8sServicePort: 7445

# Talos already mounts cgroup v2 at /sys/fs/cgroup.
cgroup:
  autoMount:
    enabled: false
  hostRoot: /sys/fs/cgroup

# Default capabilities minus SYS_MODULE, since Talos doesn't allow loading kernel modules.
securityContext:
  capabilities:
    ciliumAgent: [CHOWN, KILL, NET_ADMIN, NET_RAW, IPC_LOCK, SYS_ADMIN, SYS_RESOURCE, DAC_OVERRIDE, FOWNER, SETGID, SETUID]
    cleanCiliumState: [NET_ADMIN, SYS_ADMIN, SYS_RESOURCE]

# --- Datapath ---

# No VXLAN or Geneve tunnel, so no encapsulation overhead and full MTU.
routingMode: native

# Pod-to-pod traffic is routed directly. Must match the Talos pod subnet.
ipv4NativeRoutingCIDR: 10.244.0.0/16

# Each node routes the other nodes' pod CIDRs through their node IP. Requires a shared L2 network.
autoDirectNodeRoutes: true

# Pod traffic leaving the cluster is SNAT'ed to the node IP, since nothing outside knows 10.244.0.0/16.
enableIPv4Masquerade: true

# --- BGP ---

# The BGP speaker and the controller for the CiliumBGP* resources. LB-IPAM is on by default.
bgpControlPlane:
  enabled: true

# --- Gateway API ---

gatewayAPI:
  enabled: true           # Gateway API controller and the embedded Envoy proxy
  enableAlpn: true        # HTTP/2 over TLS, required for gRPC over TLS
  enableAppProtocol: true # Honour appProtocol (e.g. kubernetes.io/h2c) on backend Services

operator:
  replicas: 1
```

A few of these deserve a bit more explanation.

- **`ipam.mode: kubernetes`**

    Cilium’s default IPAM mode hands out pod IPs from `10.0.0.0/8`, which overlaps every network in this post. In
    `kubernetes` mode, Cilium uses the pod CIDRs that Talos assigns to each node instead.

- **`k8sServiceHost: localhost` and `k8sServicePort: 7445`**

    Pods normally reach the Kubernetes API through the `kubernetes` Service at `10.96.0.1`. Without kube-proxy, it is
    Cilium that makes that Service work, so Cilium can’t use it to reach the API itself. Instead it uses KubePrism, a
    small load balancer that Talos runs on every node on `localhost:7445`.

- **`routingMode: native`**

    Pod traffic is routed directly between the nodes, without tunneling. This works because all nodes share VLAN 30.
    If the nodes were spread across routed networks, you would need the default tunnel mode instead.

- **`gatewayAPI.enabled`**

    Requires `kubeProxyReplacement: true`, which is already set.

!!! info "Why not `bpf.masquerade`"

    Many Cilium guides enable `bpf.masquerade: true`, which does the masquerading in eBPF instead of iptables. It is
    left off on purpose here. With the Talos default `hostDNS.forwardKubeDNSToHost: true`, CoreDNS forwards its
    queries to the DNS resolver on the node, and together with `bpf.masquerade` that breaks DNS in the cluster. The
    iptables masquerading is perfectly fine at this scale. See the known issues in the
    [Talos Cilium guide](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium#known-issues).

### The Gateway API CRDs

The Gateway API resources are not part of Kubernetes itself, so their CRDs have to be installed separately. They
must exist before Cilium starts. Cilium checks for them on startup, and if they are missing, it silently disables
its Gateway API support.

```sh
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.7.0/standard-install.yaml
```

The `--server-side` flag is needed, since some of the CRDs are too large for the annotation that a client-side
apply stores on them. The API server works fine without a CNI, so this can be done while the nodes are still
`NotReady`.

### Installing

You need `helm` and the [Cilium CLI](https://github.com/cilium/cilium-cli/releases) on your workstation.

```sh
helm repo add cilium https://helm.cilium.io
helm repo update
helm install cilium cilium/cilium -n kube-system --version 1.20.4 -f cilium-values.yaml
```

Wait for Cilium to come up.

```sh
cilium status --wait
```

Then check the nodes and the GatewayClass.

```sh
kubectl get nodes
kubectl get gatewayclass
```

Once Cilium is up, all nodes turn `Ready`, and `talosctl health` passes. There should also be a GatewayClass called
`cilium` with `ACCEPTED` set to `True`. If it is missing, the CRDs were not in place when Cilium started. Install
them and restart Cilium with `kubectl -n kube-system rollout restart deployment/cilium-operator daemonset/cilium`.

## Configuring BGP

The BGP setup in Cilium is spread across four resources, which link together like this.

```
CiliumLoadBalancerIPPool   -> which IPs LoadBalancer Services get
CiliumBGPClusterConfig     -> which nodes run BGP, their AS and who the peer is
  └─ peerConfigRef ──► CiliumBGPPeerConfig     -> session settings
                         └─ matchLabels ──► CiliumBGPAdvertisement -> what to announce
```

Create a file called `cilium-bgp.yaml` and add the four resources below to it.

### The IP Pool

Every Service of type LoadBalancer gets an IP from this pool. It must match the `talos-in` filter on the router.

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: lb-pool
spec:
  blocks:
    - cidr: 10.0.100.0/24
```

### The Cluster Config

This decides which nodes run a BGP speaker and who they peer with. Only nodes with the `bgp: enabled` label from the
Talos worker patch are selected, so the control plane stays out of it. The AS numbers must match the router.

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPClusterConfig
metadata:
  name: mikrotik
spec:
  nodeSelector:
    matchLabels:
      bgp: enabled
  bgpInstances:
    - name: cluster
      localASN: 64513 # The cluster's AS
      peers:
        - name: mikrotik
          peerASN: 64512 # The router's AS
          peerAddress: 10.0.30.1
          peerConfigRef:
            name: mikrotik
```

The router ID is not set, so Cilium uses the IP of each node.

### The Peer Config

The session settings for the router. The hold and keepalive timers match the ones set on it. The connect retry timer is
lowered from the default 120 seconds, so the sessions come back quickly after a router reboot.

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPPeerConfig
metadata:
  name: mikrotik
spec:
  timers:
    connectRetryTimeSeconds: 5
    holdTimeSeconds: 9
    keepAliveTimeSeconds: 3
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: lb-pool
```

### The Advertisement

What to announce. Every LoadBalancer IP is announced as a `/32`, with the worker as the next hop.

```yaml
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: lb-pool
  labels:
    advertise: lb-pool
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses:
          - LoadBalancerIP
      # A selector is required. This one matches every Service, since nothing
      # has this label. To only announce some Services, select on a real label.
      selector:
        matchExpressions:
          - key: somekey
            operator: NotIn
            values:
              - never-used-value
```

The selector looks odd, but Cilium requires one, and an expression that matches a label nobody has is apparently the common way
to select everything.

Apply the file.

```sh
kubectl apply -f cilium-bgp.yaml
```

### Verifying the Sessions

On the Kubernetes side, the Cilium CLI shows the state of every session.

```sh
cilium bgp peers
```

Both workers should show the router as a peer, with the session state `established`. On the router, the same
thing from the other side.

```
/routing bgp session print
```

There are no routes yet, since there are no LoadBalancer Services yet.

## Testing with a Service

Deploy a small test app with a LoadBalancer Service. The `lbipam.cilium.io/ips` annotation pins the Service to a
specific IP from the pool. Without it, LB-IPAM picks the next free one.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: whoami
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  namespace: whoami
spec:
  replicas: 2
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      # One pod per worker, so both workers announce the IP. See Cluster or Local below.
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: whoami
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: whoami
          image: traefik/whoami:v1.10.3
          args: ["--port", "8080"]
          ports:
            - containerPort: 8080
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
---
apiVersion: v1
kind: Service
metadata:
  name: whoami
  namespace: whoami
  annotations:
    lbipam.cilium.io/ips: 10.0.100.10
spec:
  type: LoadBalancer
  # Only workers with a whoami pod announce the IP. See Cluster or Local below.
  externalTrafficPolicy: Local
  selector:
    app: whoami
  ports:
    - port: 80
      targetPort: 8080
```

The deployment is hardened to pass the `restricted` Pod Security profile. Talos enforces `baseline` and warns on
anything that doesn’t meet `restricted`. Since a non-root container without capabilities can’t bind port 80, whoami
listens on port 8080 instead.

```sh
kubectl apply -f whoami.yaml
kubectl -n whoami get svc whoami
```

```
NAME     TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
whoami   LoadBalancer   10.104.12.200   10.0.100.10   80:31234/TCP   10s
```

The Service has its IP. On the router, there should now be two BGP routes for it, one through each worker. Both
are active and marked with `+`, which means the router uses them together as an ECMP route.

```
/routing route print where dst-address=10.0.100.10/32
/ip route print where dst-address=10.0.100.10/32
```

```
Flags: D - DYNAMIC; A - ACTIVE; b - BGP; + - ECMP
Columns: DST-ADDRESS, GATEWAY, DISTANCE
     DST-ADDRESS     GATEWAY     DISTANCE
DAb+ 10.0.100.10/32  10.0.30.22        20
DAb+ 10.0.100.10/32  10.0.30.23        20
```

If `/routing route print` shows the routes with an `F` flag, they were received but rejected by the `talos-in`
filter, and they won’t show up in `/ip route print` at all. Check that the filter range matches the IP pool.

!!! info "`/routing route` or `/ip route`"

    `/routing route print` shows every route the router has received, including the ones a filter rejected, while
    `/ip route print` only shows the routes the router actually uses to forward traffic. In short, the first is what
    the router heard, and the second is what it uses.

Finally, from a client on your normal network.

```sh
curl http://10.0.100.10
```

Run it a few times and watch the `Hostname` in the output. With the `l4` hash policy, every `curl` opens a new
connection from a new source port, so the router may pick the other worker each time, and the `Hostname` changes
between the two pods. With the default `l3`, the same client always lands on the same worker, so the `Hostname`
stays the same, and a client with a different IP may land on the other one. The `RemoteAddr` is the IP of your
client, since the Service uses `externalTrafficPolicy: Local`.

### Cluster or Local

The `externalTrafficPolicy` of a Service decides which workers announce its IP, and where a worker may send the
traffic it receives. This post uses `Local` for the whoami Service, but it is worth knowing both.

**`Cluster`** is the default. Every worker announces the IP, whether it runs a pod of the Service or not. A worker
that receives a connection picks a pod anywhere in the cluster, and if that pod runs on another worker, the traffic
takes an extra hop to get there. To make sure the reply comes back the same way, the worker replaces the client IP
with its own node IP, so the pod never sees who the client really is.

**`Local`** only lets a worker announce the IP if it runs a pod of the Service, and a worker only sends traffic to
its own pods. There is no extra hop and no source NAT, so the pod sees the real client IP. That matters for access
logs, rate limiting and IP allow lists. If the last pod on a worker goes away, the worker withdraws its route, and
the router stops sending traffic there.

The catch is that the load is balanced in two steps, and they don’t know about each other. The router spreads
connections evenly across the workers that announce the IP, and each worker then spreads its share across only its
own pods. If the pods are unevenly placed, so are the connections. Take four pods, with three on one worker and one
on the other.

| Policy    | Worker 1, 3 pods        | Worker 2, 1 pod  |
|-----------|-------------------------|------------------|
| `Cluster` | 25% per pod             | 25%              |
| `Local`   | 50% split, ~17% per pod | 50% on one pod   |

With `Local`, the single pod on worker 2 handles three times as much traffic as each of the others. That is why the
whoami Deployment has a topology spread constraint. It keeps one pod per worker, so the router’s even split across
the workers is also an even split across the pods. Without it, the scheduler could place both pods on the same
worker, and only that worker would announce the IP.

A rule of thumb: use `Local` when the application needs the client IP, or when you want to avoid the extra hop,
and spread the pods across the workers. Use `Cluster` when the pods can’t be spread evenly, or when there are fewer
pods than workers and you want every worker to take traffic.

## Configuring the Cilium Gateway

A LoadBalancer Service per application works, but it means one IP per application, and no way to route on host
names or paths. That is the job of an ingress layer, and Cilium has a Gateway API implementation built in.

The Gateway API splits the job in two. A **Gateway** is the entry point. It owns the IP and the listeners, like
HTTP on port 80. An **HTTPRoute** belongs to an application, and attaches to a Gateway to say which host names and
paths should go to which Service. One Gateway can serve any number of applications.

The nice part is how it fits with everything above. For every Gateway, Cilium creates a LoadBalancer Service. That
Service gets an IP from the pool and is announced over BGP, exactly like the whoami Service. The traffic is then
handled by the Envoy proxy that runs inside the Cilium agent on every node, so there are no extra ingress pods to
run.

### The Gateway

Create a file called `cilium-gateway.yaml`.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cilium-gateway
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main
  namespace: cilium-gateway
spec:
  gatewayClassName: cilium
  # Optional. Without it, LB-IPAM assigns the next free IP from the pool.
  # Pinned, so DNS records stay valid if the Gateway is ever recreated.
  addresses:
    - type: IPAddress
      value: 10.0.100.20
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

The Gateway lives in its own namespace, since it is shared infrastructure rather than part of an application.
`allowedRoutes` lets HTTPRoutes from every namespace attach to the listener.

```sh
kubectl apply -f cilium-gateway.yaml
kubectl -n cilium-gateway get gateway main
kubectl -n cilium-gateway get svc
```

The Gateway should show the address `10.0.100.20` with `PROGRAMMED` set to `True`, and next to it there is now a
LoadBalancer Service called `cilium-gateway-main` with the same IP. On the router, `10.0.100.20/32` shows up through
both workers, just like before.

```
/ip route print where dst-address=10.0.100.20/32
```

### The HTTPRoute

Now route a host name to the whoami Service. There is no need to create a DNS record for it, since we’ll set the
host name by hand when testing. Create a file called `whoami-route.yaml`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: whoami
  namespace: whoami
spec:
  parentRefs:
    - name: main
      namespace: cilium-gateway
      sectionName: http
  hostnames:
    - whoami.example.com
  rules:
    - backendRefs:
        - name: whoami
          port: 80
```

The route lives in the application’s namespace, next to the Service it points at. `parentRefs` attaches it to the
`http` listener of the `main` Gateway.

```sh
kubectl apply -f whoami-route.yaml
kubectl -n whoami get httproute whoami
```

Since there is no DNS record for `whoami.example.com`, set the `Host` header by hand to test it from a client.

```sh
curl -H 'Host: whoami.example.com' http://10.0.100.20
```

Once the route works, the whoami Service doesn’t need to be a LoadBalancer anymore. Change it to a regular
`ClusterIP` Service, and the Gateway is the only way in. Remove `externalTrafficPolicy` and the
`lbipam.cilium.io/ips` annotation at the same time, since the traffic policy is only allowed on externally reachable
Services. For real use, point a DNS record, or a wildcard record for
a whole subdomain, at `10.0.100.20`.

## Wrapping Up

That is the whole chain. Cilium hands out an IP from the pool, the workers running the Service’s pods announce it
over BGP, and the router spreads the connections across them. New LoadBalancer Services get an IP and a route on
their own, and with `externalTrafficPolicy: Local` the pods see the real client IP. If a worker goes away, the router
drops it from the ECMP group within 9 seconds. On top of that, the Cilium Gateway gives every application a host name
behind a single IP.

From here, the natural next step is TLS. With cert-manager and a wildcard certificate, the Gateway can get an HTTPS
listener that terminates TLS for every application behind it.

---
