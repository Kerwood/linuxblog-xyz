---
title: "Moving the Talos Kubernetes API to a Virtual IP"
description: "Change the Kubernetes API endpoint of a running Talos cluster from a node IP to a control plane VIP, using Layer2VIPConfig."
date:
  created: 2026-11-02 21:00:00
authors:
  - kerwood
slug: talos-control-plane-vip
categories:
  - "Kubernetes"
  - "Self-hosting"
tags:
  - "kubernetes"
  - "proxmox"
---

In this post, I’ll take the Talos cluster from the previous post and move its Kubernetes API endpoint from the IP of the control plane node to a virtual IP, using the built-in Layer 2 VIP in Talos. The cluster keeps running during the change.

<!-- more -->




In [A Simple Talos Kubernetes Cluster on Proxmox](../talos-cluster-on-proxmox/talos-cluster-on-proxmox.md), the
cluster was generated with the IP of the control plane node as its Kubernetes API endpoint.

```sh
talosctl gen config homelab https://10.0.0.21:6443 ...
```

That works fine, but the endpoint ends up everywhere. It is in the machine config of every node, in your kubeconfig
and in the kubeconfig of every tool you have handed it to. As long as it points at a single node, that node can never
be replaced, and adding more control plane nodes doesn’t help, since everything still talks to the first one.

A virtual IP fixes this. The endpoint points at the VIP, and the VIP follows whichever control plane node is alive.

!!! info "Easier on a new cluster"

    This post applies the VIP to the existing cluster from the previous post. It can just as well be set up when the
    cluster is first created, and that is the easier way to do it. Generate the config with the VIP as the endpoint
    and the `vip.yaml` patch from below, before applying it to the nodes for the first time. That way there is no
    issuer to keep, no configs to apply again and no kubeconfigs to update.

## How the Talos VIP Works

Talos has the VIP built in. All control plane nodes get the same VIP in their config and hold an election through
etcd. The winner adds the VIP to its network interface and announces it with gratuitous ARP, so the rest of the
network knows which MAC address to send the traffic to.

If the node holding the VIP is shut down, rebooted or upgraded, it gives up the VIP and another control plane node
takes over almost immediately. If the node crashes or loses power, the others have to wait for its etcd lease to
expire first, which can take up to a minute.

There are a few things worth knowing about it.

- **It is not load balancing.** All traffic to the VIP lands on one control plane node at a time.
- **It needs a shared layer 2 network.** All control plane nodes must sit in the same subnet, since it relies on ARP.
- **It depends on etcd.** The VIP only exists while etcd is running. That is why `talosctl` should keep talking to the
  node IPs directly, since `talosctl` is the tool you need when etcd is broken.
- **It is not used by the nodes themselves.** Inside the cluster, KubePrism on `localhost:7445` spreads the traffic
  from kubelet and pods across all API servers. The VIP is mostly for clients outside the cluster, like `kubectl`.

With a single control plane node, the VIP doesn’t give us high availability yet. What it does give us is an endpoint
that never has to change again, so adding two more control plane nodes later is just a matter of applying
`controlplane.yaml` to them.

## Picking the IP

The VIP is not handed out by the DHCP server, so pick a free address in the same subnet as the nodes and make sure it
is outside the DHCP pool. In this post it is `10.0.0.20`.

| Node       | Role          | IP        |
|------------|---------------|-----------|
| VIP        | Kubernetes API| 10.0.0.20 |
| talos-cp-1 | Control plane | 10.0.0.21 |
| talos-w-1  | Worker        | 10.0.0.22 |
| talos-w-2  | Worker        | 10.0.0.23 |

## The Patches

### The VIP

The VIP is assigned to a network interface, so we need its name. Check it on the control plane node.

```sh
talosctl get links -n 10.0.0.21
```

Look for the physical interface with the MAC address of the node. On Proxmox with a VirtIO network card, it is
usually called `ens18`. Create a patch file called `vip.yaml`.

```yaml
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: 10.0.0.20 # The virtual IP
link: ens18     # The interface to announce it on
```

The VIP is only meant for control plane nodes, so this patch is only applied to them.

### The Service Account Issuer

!!! warning "Only needed on existing clusters"

    This patch is only needed when you change the endpoint of a cluster that is already running. If you are
    following this post to create a new cluster with the VIP from the start, there are no tokens with an old issuer
    yet. Skip `issuer.yaml` and leave out the `--config-patch-control-plane @issuer.yaml` line in the next section.

There is a catch when changing the endpoint of a running cluster. By default, Talos also uses the endpoint as the
issuer URL for service account tokens. Every pod that talks to the Kubernetes API, like CoreDNS and Flannel, carries
a token with the old issuer in it. If the issuer changes, the API server rejects those tokens until the kubelet
refreshes them, and that can take a while.

The issuer URL is just an identifier, it doesn’t have to point at anything reachable. So the easy way out is to
keep the old one. Create a patch file called `issuer.yaml`.

```yaml
apiVersion: v1alpha1
kind: KubeServiceAccountConfig
issuer:
  issuerURL: https://10.0.0.21:6443 # Keep the original issuer
```

## Regenerating the Configuration

Since the endpoint is in every config file, regenerate them with the new endpoint. Use the same `secrets.yaml` as
before, otherwise you get a brand new set of certificates that don't match the running cluster.

```sh
SCHEMATIC=ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
TALOS=v1.14.5

talosctl gen config homelab https://10.0.0.20:6443 \
  --with-secrets secrets.yaml \
  --install-image factory.talos.dev/nocloud-installer/$SCHEMATIC:$TALOS \
  --config-patch-control-plane @vip.yaml \
  --config-patch-control-plane @issuer.yaml \
  --output-types controlplane,worker \
  --force
```

The `--output-types` flag makes sure only the machine configs are written. The `talosconfig` is left alone, since it
doesn’t contain the endpoint and is already merged into `~/.talos/config`.

The control plane config should only differ in the endpoint and the new `Layer2VIPConfig` document, and the worker
config only in the endpoint. If you see anything else, like a different Kubernetes version, stop and figure out why
before going further.

## Applying the Control Plane

Start with the control plane. A dry run shows what Talos is going to change, and whether it needs a reboot to do it.

```sh
talosctl apply-config -n 10.0.0.21 -f controlplane.yaml --dry-run
talosctl apply-config -n 10.0.0.21 -f controlplane.yaml
```

Once applied, the control plane node claims the VIP. You can see it as an extra address on the interface.

```sh
talosctl get addresses -n 10.0.0.21
```

```
NODE        NAMESPACE   TYPE            ID                   VERSION   ADDRESS        LINK
10.0.0.21   network     AddressStatus   ens18/10.0.0.20/32   1         10.0.0.20/32   ens18
10.0.0.21   network     AddressStatus   ens18/10.0.0.21/24   1         10.0.0.21/24   ens18
...
```

Talos also regenerates the API server certificate to include the new endpoint, so there is no need to add the VIP
to the certificate SANs yourself. You can check both the VIP and the certificate in one go, by pointing your
existing kubeconfig at the VIP.

```sh
kubectl --server https://10.0.0.20:6443 get nodes
```

If that lists the nodes without a certificate error, the API answers on the VIP with a valid certificate.

## Applying the Workers

The workers only need the new endpoint.

```sh
talosctl apply-config -n 10.0.0.22,10.0.0.23 -f worker.yaml --dry-run
talosctl apply-config -n 10.0.0.22,10.0.0.23 -f worker.yaml
```

Check that all nodes are still `Ready`, and that the cluster is healthy.

```sh
kubectl --server https://10.0.0.20:6443 get nodes
talosctl health
```

## Updating the Kubeconfig

Your kubeconfig still points at `10.0.0.21`. Fetch a new one, and use `--force` to overwrite the existing context
instead of getting a second one next to it.

```sh
talosctl kubeconfig --force
kubectl config view --minify | grep server
kubectl get nodes
```

```
    server: https://10.0.0.20:6443
```

!!! tip "Optionally, keep the kubeconfig local"

    If you keep the kubeconfig in the cluster directory, overwrite that file instead.

    ```sh
    talosctl kubeconfig . --force
    export KUBECONFIG=./kubeconfig
    kubectl get nodes
    ```

## What About talosctl?

Nothing changes for `talosctl`. Its endpoint stays at the IP of the control plane node, for the reasons above.

```sh
talosctl config info
```

When you add more control plane nodes, add them to the `talosctl` endpoints, so `talosctl` can reach the cluster
through any of them.

```sh
talosctl config endpoint 10.0.0.21 10.0.0.24 10.0.0.25
```

## Adding More Control Plane Nodes

This is where the VIP pays off. Create the VMs as in the previous post, wait for maintenance mode and apply
`controlplane.yaml` to them. They join etcd and the VIP election on their own, and the endpoint stays the same.

```sh
talosctl apply-config --insecure -n 10.0.0.24 -f controlplane.yaml
talosctl apply-config --insecure -n 10.0.0.25 -f controlplane.yaml
```

Use an odd number of control plane nodes. Etcd needs a majority to keep working, so three nodes survive losing one,
while two nodes survive losing none. With three control plane nodes, you can shut any one of them down and watch the
VIP move to another.

---
