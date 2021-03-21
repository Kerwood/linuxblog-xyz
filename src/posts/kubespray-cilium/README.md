---
title: Bare Metal Kubernetes install with Kubespray and Cilium
date: 2021-03-20 20:01:22
author: Patrick Kerwood
excerpt: In this post I will setup a bare metal Kubernetes cluster using Kubespray. At the same time I'll get rid of that pesky Kube Proxy and replace it with the eBPF based Cilium CNI. Since Docker is deprecated in Kubernetes v1.20 I will be installling containerd instead. This setup is tested on CentOS 8 Stream and Redhat Enterprise Linux 8.3.
type: post
blog: true
tags: [kubernetes]
---
In this post I will setup a bare metal Kubernetes cluster using Kubespray. At the same time I'll get rid of that pesky Kube Proxy and replace it with the eBPF based Cilium CNI. Since Docker is deprecated in Kubernetes v1.20 I will be installling containerd instead. This setup is tested on CentOS 8 Stream and Redhat Enterprise Linux 8.3.

The steps are as follows.
[[toc]]

Besides installing Cilium as the Kubernetes CNI, we will also install a little bonus project called [Hubble](https://github.com/cilium/hubble). It's a networking and security observability UI that is tight integrated with Cilium.

Hubble gives you a nice map of your services and how they are connected. It can also show you the packages flying around in your cluster and which are dropped because of network policies and why. 

![](./hubble-servicemap.png)

## Building an Ansible container for Kubespray
Ansible requires a lot of Python and as I have mentioned before, I don't like to soil my laptop in Python. So building on my earlier post, [Ansible Container](https://linuxblog.xyz/posts/ansible-container/), lets create a container image that contains all of Kubespray's requirements.

First go grap the `requirements.txt` file from the [Kubespray repo.](https://github.com/kubernetes-sigs/kubespray/blob/master/requirements.txt)

Create the Dockerfile like in the post but add the `COPY` command above the `RUN` command and change the `pip install ansible` line with `pip install -r requirements.txt` as shown in the example below.

```{1,5}
COPY requirements.txt requirements.txt
RUN set -x && \
...
    echo "==> Installing ansible..."  && \
    pip install -r requirements.txt && \
...
```

Build the image and add the alias' like in the post.

Or, you cloud install Ansible and the Kubespray dependencies locally: [https://github.com/kubernetes-sigs/kubespray#ansible](https://github.com/kubernetes-sigs/kubespray#ansible) 

## Configuring Kubespray

Clone the kubespray repository. You can go ahead and clone the master branch if you want, personally I like to use a specific version. At the time of writing the newest version of Kubespray is `v2.15.0` which is the one I will be using.

Kubespray `v2.15.0` will give you the following.

 - Kubernetes `v1.19.7`
 - Etcd `3.4.13`
 - Containerd `1.3.9`
 - CoreDNS `1.7.0`
 - Nodelocaldns `1.16.0`
 - Kubernetes Dashboard `v2.1.0`


```sh
git clone --branch v2.15.0 https://github.com/kubernetes-sigs/kubespray
cd kubespray
```

I will be using the `inventory/sample` folder for the configuration, you can copy the folder and give it different name if you want.

Now lets make a few changes to it.
 - Change the `kube_network_plugin` to `cni` in the `k8s-cluster.yml` file.
 - Set the `container_manager` to `containerd` in the `k8s-cluster.yml` file.
 - Set `etcd_deployment_type` to `host` in the `etcd.yml` file. This is a dependency by contaierd.
 - Add the `kube_proxy_remove: true` variable to `k8s-cluster.yml` file to disable Kube Proxy.

Below commands will do exactly that in the `inventory/sample` folder.
```sh
sed -i -r 's/^(kube_network_plugin:).*/\1 cni/g' inventory/sample/group_vars/k8s-cluster/k8s-cluster.yml
sed -i -r 's/^(container_manager:).*/\1 containerd/g' inventory/sample/group_vars/k8s-cluster/k8s-cluster.yml
sed -i -r 's/^(etcd_deployment_type:).*/\1 host/g' inventory/sample/group_vars/etcd.yml
echo "kube_proxy_remove: true" >> inventory/sample/group_vars/k8s-cluster/k8s-cluster.yml
```

### Building your inventory
You need to create an inventory file. That is where you define which nodes to use, what their roles are etc. There's an `inventory.py` script that generates the inventory for you, which you can find some documentation on [here.](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/getting-started.md#building-your-own-inventory)

Or you can just edit the yaml below to fit your needs.

Below you'll see 3 hosts, `node1-master`, `node2-worker` and `node3-worker`. You can call them what ever you want. The `ip` and `access_ip` properties are the internal IP on which they can reach each other and the `ansible_host` are the IP which the Kubespray Ansible scripts can reach the hosts. My nodes are running in the cloud so the `ansible_host` property will be their public IP.

 - The `kube-master.hosts` are a list of masters.
 - The `kube-node.hosts` are a list of all nodes.
 - The `etcd.hosts` are a list of etcd nodes.

```sh
cat << EOF > ./inventory/sample/hosts.yml
all:
  hosts:
    node1-master:
      ansible_host: 92.104.249.162
      ip: 10.0.0.10
      access_ip: 10.0.0.10
    node2-worker:
      ansible_host: 92.105.95.132
      ip: 10.0.0.11
      access_ip: 10.0.0.11
    node3-worker:
      ansible_host: 92.105.86.187
      ip: 10.0.0.12
      access_ip: 10.0.0.12
  children:
    kube-master:
      hosts:
        node1-master:
    kube-node:
      hosts:
        node1-master:
        node2-worker:
        node3-worker:
    etcd:
      hosts:
        node1-master:
    k8s-cluster:
      children:
        kube-master:
        kube-node:
EOF
```

### Configure the nodes
Kubespray will use the root account for setting up the nodes. Copy your SSH key to the nodes if not already present.
```sh
ssh-copy-id root@92.104.249.162
ssh-copy-id root@92.105.95.132
ssh-copy-id root@92.105.86.187
```

We need to stop and disable firewalld on all the nodes. Since we have our inventory file ready, we can just use Ansible for that. 
```sh
ansible all -i inventory/sample/hosts.yml -a "systemctl stop firewalld" -b -v 
ansible all -i inventory/sample/hosts.yml -a "systemctl disable firewalld" -b -v 
```

::: warning CentOS 8 Stream
For some reason `tar` was not installed on my CentOS 8 Stream servers from Linode, so it had to be installed manually.
```sh
ansible all -i inventory/sample/hosts.yml -a "dnf install tar -y" -b -v
```
:::

## Install Kubernetes
Run below command to start the installation.
```sh
ansible-playbook -i inventory/sample/hosts.yml cluster.yml -b -v
```

## Installing Cilium with Helm
For the next step, you can either work from a master node (kubectl is installed and ready to go), or you can grab the kubeconfig file from `/etc/kubernetes/admin.conf` on a master and use it on your local machine.

What ever you do, you'll need to install Helm for the next step.

Add the Cilium repository and update.
```sh
helm repo add cilium https://helm.cilium.io/
helm repo update
```

Run below command to install Cilium and Hubble.
```sh
helm install cilium cilium/cilium --version 1.9.4 \
  --namespace kube-system \
  --set kubeProxyReplacement=strict \
  --set k8sServiceHost=127.0.0.1 \
  --set k8sServicePort=6443 \
  --set hubble.listenAddress=":4244" \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.metrics.enabled="{dns,drop,tcp,flow,port-distribution,icmp,http}"
```

### Testing Cilium
Cilium has a testing manifest that deploys various resources to test different scenarios. At the time of writing two of the network policies will fail due to the test not being updated with `nodelocaldns`. If you are interested in how the network policies work, you can try and fix them.
```sh
kubectl create ns cilium-test
kubectl apply -n cilium-test -f https://raw.githubusercontent.com/cilium/cilium/v1.9.4/examples/kubernetes/connectivity-check/connectivity-check.yaml
```

Have a look at the pods and see which ones are failing.
```sh
kubectl -n cilium-test get pods
```

## Portforward Hubble UI
To get access to that sweat Hubble UI you can either deploy an ingress or port forward the service to your localhost.
```sh
kubectl port-forward -n kube-system svc/hubble-ui --address 0.0.0.0 8080:80
```

If you are on the master node, that port forward did not really do you any good. Create an SSH tunnel to the node and map it to your localhost. 
```sh
ssh -L 8080:localhost:8080 root@92.104.249.162
```
You can now reach it on `http://localhost:8080`.

## References
 - [https://github.com/kubernetes-sigs/kubespray](https://github.com/kubernetes-sigs/kubespray)
 - [https://github.com/cilium/cilium](https://github.com/cilium/cilium)
 - [https://github.com/cilium/hubble](https://github.com/cilium/hubble)
 - [https://helm.sh/](https://helm.sh/)
---