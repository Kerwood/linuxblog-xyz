---
title: Installing NGINX Ingress with Helm on AKS
date: 2021-02-06 15:06:15
author: Patrick Kerwood
excerpt: This is a guide on installing a NGINX Ingress controller on Azure Kubernetes Service.
blog: true
tags: [nginx-ingress, aks]
---

This is a guide on installing a NGINX Ingress controller on Azure Kubernetes Service.

## Prerequisites
A prerequisite for installing NGINX Ingress with Helm is of course Helm. Go to the [Helm install docs](https://helm.sh/docs/intro/install/) and get a piece of that cake.

Efter installing Helm, add the `ingress-nginx` repo and update your Helm repositories.
```sh
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

## Installing NGINX Ingress

Create a namespace in your cluster.
```sh
kubectl create namespace ingress-nginx
```

Run below command to install. This will create a load balancer resource with a public IP, in the AKS shadow resource group.

```sh
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux \
  --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local
```
If you want to use a specific public IP resource in a resource group, append below lines to your install command. The first line is the actual IPv4 address you want to use and the second line is the name of the resource group where the public ip resource is located.

```sh
  ...
  --set controller.service.loadBalancerIP=<ip-address> \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-resource-group"=<resource-group-name>
```

You also have the option to only make the load balancer available in your internal Vnet, by creating an internal load balancer. The load balancer will get an IP address from the Vnet.

```sh
  ...
  --set-string controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-internal"="true"
```


## Verify
After deploying the ingress controller, you can verify that the load balancer is ensured. It might take some time depending on your provider.

```sh
$ kubectl describe service ingress-nginx-controller --namespace ingress-nginx
...
Normal   EnsuredLoadBalancer     2m32s           service-controller  Ensured load balancer
```

## References
- [NGINX-Ingress install documentation.](https://kubernetes.github.io/ingress-nginx/deploy/#using-helm)
- [NGINX configration with Helm parameters.](https://docs.nginx.com/nginx-ingress-controller/installation/installation-with-helm/#configuration)
- [AKS Ingress basic documentation.](https://docs.microsoft.com/en-us/azure/aks/ingress-basic)
- [AKS load balancer configuration with annotations.](https://docs.microsoft.com/en-us/azure/aks/load-balancer-standard#additional-customizations-via-kubernetes-annotations)
---

