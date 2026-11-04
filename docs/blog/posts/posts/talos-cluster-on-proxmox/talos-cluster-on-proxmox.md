---
title: "A Simple Talos Kubernetes Cluster on Proxmox"
description: "Create a small Talos Linux Kubernetes cluster on Proxmox VE with one control plane and two workers, using the default Flannel CNI and plain talosctl."
date:
  created: 2026-11-02 20:00:00
authors:
  - kerwood
slug: talos-cluster-on-proxmox
categories:
  - "Kubernetes"
  - "Self-hosting"
links:
  - blog/posts/posts/talos-control-plane-vip/talos-control-plane-vip.md
tags:
  - "kubernetes"
  - "proxmox"
---

In this post, I’ll walk through creating a small Talos Linux Kubernetes cluster on Proxmox VE, with one control plane and two workers. No Cilium, no Cluster API, just three VMs, `talosctl` and the defaults Talos ships with.

<!-- more -->




Talos Linux is an operating system built for one job, running Kubernetes. There is no SSH, no shell and no package
manager. Everything is managed through an API with `talosctl`, and the whole node is described by a single machine
configuration file. That sounds restrictive at first, but it means a node is either configured exactly like its
config file says, or it is not running.

It also makes Talos a very good fit, not only for the enterprise but for homelabs as well. Creating a cluster is a handful of commands, and tearing it down
and starting over costs you a few minutes.

The cluster in this post looks like this.

| Node       | Role          | IP           | MAC                 | Size                   |
|------------|---------------|--------------|---------------------|------------------------|
| talos-cp-1 | Control plane | 10.0.0.21 | `BC:24:11:00:00:21` | 2 vCPU / 2 GB / 10 GB  |
| talos-w-1  | Worker        | 10.0.0.22 | `BC:24:11:00:00:22` | 2 vCPU / 2 GB / 10 GB  |
| talos-w-2  | Worker        | 10.0.0.23 | `BC:24:11:00:00:23` | 2 vCPU / 2 GB / 10 GB  |

Each VM gets a static MAC address, so the DHCP server can hand out a static lease for it. The nodes
need fixed IPs because the Kubernetes API endpoint and the `talosctl` configuration both point at them. Talos can
be configured with static IPs in its machine config, but then the addresses are spread across config files. With
static leases, the DHCP server stays the single source of truth for addressing, and you can see every node and its IP in
one place, next to the rest of your network.

Replace the IPs with something from your own network. The versions used are Talos v1.14.5 and whatever Kubernetes
version that Talos release ships as default.

## Prerequisites

You need `talosctl` and `kubectl` on your workstation. The `talosctl` version should match the Talos version you
are installing.

```sh
curl -sL https://talos.dev/install | sh
talosctl version --client
```

On the network side, create a static lease on your DHCP server for each MAC address in the table above.

## Building the Talos Image

Talos images are built by the [Image Factory](https://factory.talos.dev). The factory lets you add system extensions
to the image, and on Proxmox the one you want is the QEMU guest agent. Without it, Proxmox can't see the IP of the VM
and a shutdown from the Proxmox UI will not be passed on to Talos gracefully.

An image is identified by a schematic ID, which is a hash of the customization. Since it is a hash, the same
customization always gives the same ID. You can get it through the web UI or the API, and both end up with the
exact same ID.

### Using the Web UI

Go to [factory.talos.dev](https://factory.talos.dev) and click through the wizard.

1. **Hardware Type:** Cloud Server.
2. **Talos Linux Version:** 1.14.5.
3. **Cloud:** Nocloud.
4. **Machine Architecture:** amd64, with SecureBoot left off.
5. **System Extensions:** search for and select `siderolabs/qemu-guest-agent`.
6. **Customization:** leave the extra kernel arguments empty.

The last page shows the schematic ID along with download links for the ISO and the installer image to use when
generating the configuration. Copy the schematic ID, you’ll need it twice.

### Using the API

If you would rather script it, describe the customization in a file called `schematic.yaml`.

```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/qemu-guest-agent
```

Post it to the factory to get the ID back.

```sh
curl -X POST --data-binary @schematic.yaml https://factory.talos.dev/schematics
```

```json
{"id":"ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"}
```

### Downloading the ISO

Download the ISO directly on the Proxmox host, into the ISO storage.

```sh
SCHEMATIC=ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
TALOS=v1.14.5

curl -Lo /var/lib/vz/template/iso/talos-$TALOS-nocloud-amd64.iso \
  https://factory.talos.dev/image/$SCHEMATIC/$TALOS/nocloud-amd64.iso
```

## Creating the VMs

Create the three VMs in the Proxmox UI with the sizes from the table, and boot them from the Talos ISO. There are
two settings you need to remember.

- **QEMU Guest Agent:** enable it under **System** in the create wizard, or later under **Options**. This adds the
  device that the guest agent extension in our image talks to.
- **MAC address:** set the static MAC address from the table under **Network**, so the VM gets its static lease from
  the DHCP server.

Also set the CPU type to `host`. Talos requires the x86-64-v2 instruction set, and with the old `kvm64` type the VM
hangs during boot at 100% CPU without any useful error.

Start the VMs. Each VM boots into **maintenance mode**. Talos is running from the ISO, has an IP address from DHCP and waits for a
machine configuration. Open the console of one of the VMs and you’ll see the Talos dashboard with the IP in the top
section. Check that it matches the DHCP lease you created.

## Generating the Configuration

Back on your workstation, start with the cluster secrets. This file holds the certificate authorities, keys and
tokens for the cluster, and every config file is generated from it.

```sh
talosctl gen secrets -o secrets.yaml
```

Before generating the configs, check which disk Talos sees on the nodes. While a node is in maintenance mode, there
is no client certificate yet, which is why `--insecure` is needed.

```sh
talosctl get disks --insecure -n 10.0.0.21
```

With VirtIO SCSI the disk shows up as `/dev/sda`, which is also what Talos installs to by default. If yours is
different, add `--install-disk` to the command below.

Now generate the configuration. The first argument is the cluster name, the second is the Kubernetes API endpoint.
With a single control plane, that is simply the IP of the control plane node.

```sh
SCHEMATIC=ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515
TALOS=v1.14.5

talosctl gen config homelab https://10.0.0.21:6443 \
  --with-secrets secrets.yaml \
  --install-image factory.talos.dev/nocloud-installer/$SCHEMATIC:$TALOS
```

!!! info "Pointing the endpoint at a virtual IP"

    Using the node IP as the endpoint ties the Kubernetes API to a single machine. Talos can also share a virtual IP
    between the control plane nodes, which is needed if you want more than one control plane. That is covered in
    [Moving the Talos Kubernetes API to a Virtual IP](../talos-control-plane-vip/talos-control-plane-vip.md), the
    follow-up to this post.

The `--install-image` flag is easy to miss but important. The ISO only decides what runs in maintenance mode. The
installer image is what actually ends up on the disk, and if you leave it out, you get the plain Talos image without
the guest agent extension.

You now have three new files.

| File                | Purpose                                             |
|---------------------|-----------------------------------------------------|
| `controlplane.yaml` | Machine configuration for control plane nodes       |
| `worker.yaml`       | Machine configuration for worker nodes              |
| `talosconfig`       | Client configuration for `talosctl`, with admin cert |

Together with `secrets.yaml`, these files are the keys to the cluster. Keep them somewhere safe and out of public
Git repositories. If you need to regenerate the configs later, always use `--with-secrets secrets.yaml`, otherwise you
get a brand new set of certificates that don't match the running cluster.

Notice that we don't need any config patches. Out of the box Talos runs Flannel as the CNI and kube-proxy for
services, which is exactly what we want for a plain cluster.

## Applying the Configuration

Push the configs to the nodes. The control plane gets `controlplane.yaml` and both workers get the same `worker.yaml`.

```sh
talosctl apply-config --insecure -n 10.0.0.21 -f controlplane.yaml
talosctl apply-config --insecure -n 10.0.0.22 -f worker.yaml
talosctl apply-config --insecure -n 10.0.0.23 -f worker.yaml
```

Each node now installs Talos to its disk and reboots, coming back up from disk with its configuration applied. If a
VM boots into the ISO again, move the disk before the CD-ROM in the boot order under **Options**, or remove the ISO
from the VM.

## Bootstrapping the Cluster

Next, set up `talosctl` to talk to the cluster. Merge the generated `talosconfig` into your default talosconfig file
at `~/.talos/config`. The cluster is added as a new context and becomes the current one, so `talosctl` works from
any directory.

Then set the endpoint and the default node. The endpoint is where `talosctl` connects, and the node is the default
target for commands when you don't give `-n`.

```sh
talosctl config merge ./talosconfig
talosctl config endpoint 10.0.0.21
talosctl config node 10.0.0.21
```

!!! tip "Optionally, keep the talosconfig local"

    Instead of merging, you can point `talosctl` at the file in the current directory with the `TALOSCONFIG`
    environment variable. This keeps the cluster’s credentials together with the rest of its files, and the endpoint
    and node are then written to `./talosconfig`. The variable only lives in the current shell, and since the path is
    relative, run `talosctl` from the cluster directory and export it again in a new terminal.

    ```sh
    export TALOSCONFIG=./talosconfig
    talosctl config endpoint 10.0.0.21
    talosctl config node 10.0.0.21
    ```

Setting the default node to the control plane only is on purpose. Commands like `reboot` and `upgrade` would
otherwise hit every node at once, and the next command must only run against a single node.

Bootstrap etcd on the control plane. This is done exactly once, for the lifetime of the cluster.

```sh
talosctl bootstrap
```

It takes a few minutes for etcd and the Kubernetes control plane components to come up. You can follow along with
the dashboard, or wait for the health check to pass.

```sh
talosctl dashboard
talosctl health
```

## Accessing the Cluster

When the health check is green, fetch the kubeconfig. Without any arguments it is merged into `~/.kube/config` and
set as the current context.

```sh
talosctl kubeconfig
kubectl get nodes -o wide
```

!!! tip "Optionally, keep the kubeconfig local"

    Instead of merging, give `talosctl kubeconfig` a directory to write a `kubeconfig` file there, and point
    `kubectl` at it with the `KUBECONFIG` environment variable. Just like with `TALOSCONFIG`, the variable only lives
    in the current shell and the path is relative to the cluster directory.

    ```sh
    talosctl kubeconfig .
    export KUBECONFIG=./kubeconfig
    kubectl get nodes -o wide
    ```

```
NAME            STATUS   ROLES           AGE   VERSION   INTERNAL-IP    ...
talos-xyz-abc   Ready    control-plane   4m    v1.37.x   10.0.0.21   ...
talos-def-ghi   Ready    <none>          3m    v1.37.x   10.0.0.22   ...
talos-jkl-mno   Ready    <none>          3m    v1.37.x   10.0.0.23   ...
```

All three nodes should be `Ready`. Since Flannel is installed by Talos as part of the bootstrap, there is no extra
CNI step. The node names are random unless your DHCP server hands out hostnames, which is another good reason for the
static leases.

A quick test that pods can actually be scheduled and reached.

```sh
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --port=80 --type=NodePort
kubectl get pods -o wide
kubectl get svc nginx
```

Point a browser at any node IP on the NodePort, and you should be greeted by the nginx welcome page. Clean up again
afterwards.

```sh
kubectl delete svc,deployment nginx
```

## Day Two

A few commands that are useful once the cluster is running.

```sh
talosctl -n 10.0.0.22 dashboard   # live view of a node
talosctl -n 10.0.0.22 logs kubelet
talosctl -n 10.0.0.22 reboot
talosctl -n 10.0.0.22 shutdown    # cordon, drain and power off
```

To change the configuration of a running node, edit the config file and apply it again. This time without
`--insecure`, since `talosctl` now has a client certificate.

```sh
talosctl apply-config -n 10.0.0.22,10.0.0.23 -f worker.yaml
```

Adding another worker is the same procedure as before. Create a VM, wait for maintenance mode and apply `worker.yaml`
to it. It joins the cluster on its own.

And if you want to start over, delete the VMs and recreate them. That is the nice thing about Talos, the cluster is
nothing more than a few files on your workstation and some empty VMs.

---
