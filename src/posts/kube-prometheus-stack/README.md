---
title: Setting up the Kube Prometheus Stack
date: 2020-11-14 08:54:22
author: Patrick Kerwood
excerpt: In this post I will show you how to install the Kube Prometheus Stack in your Kubernetes cluster, which will give you 20+ Grafana dashboards to let you know everything about whats going on in your cluster. This installation process is extremely simple with Helm 3. I will also add some Grafana configuration to enable OAuth2 logins.
type: post
blog: true
tags: [kubernetes, prometheus, grafana, oauth2]
---

In this post I will show you how to install the Kube Prometheus Stack in your Kubernetes cluster, which will give you 20+ Grafana dashboards to let you know everything about whats going on in your cluster. This installation process is extremely simple with Helm 3. I will also add some Grafana configuration to enable OAuth2 logins.

## Prerequisites
All you need for this is the Helm 3 CLI and kubectl of course. 

You can download the Helm binary from the Github page [https://github.com/helm/helm/releases](https://github.com/helm/helm/releases), or follow some install instructions on [https://helm.sh/docs/intro/install/](https://helm.sh/docs/intro/install/)

## Installing using Helm

Create the Prometheus namespace.
```sh
kubectl create namespace prometheus
```

Add prometheus-community repo to Helm and update.
```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

Install the `kube-prometheus-stack` chart.
```sh
helm install prometheus prometheus-community/kube-prometheus-stack --namespace prometheus
```
Installation is now complete. Easy as pie.

## Grafana Tunnel
The stack is now installed, but it does not install an Ingress definition, you need to do that your self. A quick way of testing the installation is creating a tunnel to the Grafana service.

Get the `prometheus-grafana-*` pod name.
```sh
POD=$(kubectl get pod -n prometheus -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
echo $POD
```

Create a tunnel proxy to your own machine.
```sh
kubectl port-forward -n prometheus $POD 3000
```

Go to `http://localhost:3000` in your browser and you should see the Grafana login page.

The default username and password is `admin`/`prom-operator`.

## Grafana Ingress definition

To reach the service from outside the cluster, you need to have an ingress controller and an ingress definition. Below is an example of an ingress definition with cert-manager configuration. The key parts here is that the definition needs to be in the same namespace as Prometheus and that the `serviceName` is `prometheus-grafana`.

```yaml{5,19}
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: prometheus-grafana
  namespace: prometheus
  annotations:
    cert-manager.io/cluster-issuer: le-dns01
spec:
  tls:
  - hosts:
    - grafana.example.org
    secretName: grafana-le-secret
  rules:
  - host: grafana.example.org
    http:
      paths:
      - path: /
        backend:
          serviceName: prometheus-grafana
          servicePort: 3000
```

## Grafana OAuth2 Login

Now that Grafana is up and running, we just need to append a little magic to the `prometheus-grafana` configmap.

First you need to go to [https://grafana.com/docs/grafana/latest/auth/](https://grafana.com/docs/grafana/latest/auth/) and pick an OAuth2 provider. Follow the instructions for your chosen provider. In my example I have chosen Gitlab.

Get the existing Grafana configuration from the configmap and store it in `grafana.ini`.
```sh
kubectl -n prometheus get configmaps  prometheus-grafana -o jsonpath='{.data.grafana\.ini}' > grafana.ini
```

Append your OAuth2 configuration to the `grafana.ini` file.
```sh{8,9,14}
cat << EOF >> grafana.ini
[server]
root_url = https://grafana.example.org

[auth.gitlab]
enabled = true
allow_sign_up = true
client_id = <gitlab-appid-here>
client_secret = <gitlab-secret-here>
scopes = read_api
auth_url = https://gitlab.com/oauth/authorize
token_url = https://gitlab.com/oauth/token
api_url = https://gitlab.com/api/v4
allowed_groups = <gitlab-group-here>

[auth]
disable_login_form = true

[users]
allow_sign_up = false
auto_assign_org = true
auto_assign_org_role = Admin
EOF
```

The `[auth]` and `[users]` section is a little extra I added. It disables the normal login box and gives an authenticated user the Admin role. Change it to fit your needs.

Apply the new configuration.
```sh
kubectl -n prometheus create configmap prometheus-grafana --from-file=grafana.ini --dry-run=client -o yaml | kubectl replace -f -
```

The configmap is now updated with the new configuration. Last thing to do is to delete the running Grafana pod so a new pod spins up with the new configmap.

Get the Grafana pod name.
```sh
POD=$(kubectl get pod -n prometheus -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')
echo $POD
```

Delete the pod.
```sh
kubectl -n prometheus delete pod $POD
```
## Reference
- [https://grafana.com/docs/grafana/latest/auth/](https://grafana.com/docs/grafana/latest/auth/)
---