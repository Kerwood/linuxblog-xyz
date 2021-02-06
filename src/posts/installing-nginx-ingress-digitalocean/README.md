---
title: Installing NGINX Ingress with Helm on Digital Ocean
date: 2021-02-06 16:06:15
author: Patrick Kerwood
excerpt: This is a guide on installing a NGINX Ingress controller on a managed Digital Ocean Kubernetes cluster.
blog: true
tags: [nginx-ingress, 'digital ocean']
---
This is a guide on installing a NGINX Ingress controller on a managed Digital Ocean Kubernetes cluster.

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

Below is the install command for deploying the NGINX ingress controller. You can choose the size of the load balancer in the `do-loadbalancer-size-slug` annotation, the different options are `lb-small`, `lb-medium` and `lb-large`.

The last line gives the option to name your load balancer.

```sh{7,8}
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --set controller.service.type=LoadBalancer \
  --set controller.service.externalTrafficPolicy=Local \
  --set controller.config.use-proxy-protocol="true" \
  --set-string controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-enable-proxy-protocol"="true" \
  --set-string controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-size-slug"="lb-small" \
  --set-string controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-name"="my-load-balancer-name"
```

::: warning
As of February 2021, there's an issue with pod to pod communication, through the load balancer public IP. This is an issue for Cert Manager, that checks if an ACME challenge is actually reachable before sending a request to Let's Encrypt. The workaround is to give the load balancer a hostname with the `do-loadbalancer-hostname` annotation. It does not have to be a domain name in use, it can be any domain name, it doesn't matter.

Add below line to your Helm install command.
```
--set-string controller.service.annotations."service\.beta\.kubernetes\.io/do-loadbalancer-hostname"="workaround-examle.org"
```
:::


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
- [DigitalOcean - Configure Load Balancers.](https://www.digitalocean.com/docs/kubernetes/how-to/configure-load-balancers/)
---

