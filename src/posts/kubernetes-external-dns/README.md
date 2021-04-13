---
title: Automate public DNS entries with External DNS for Kubernetes
date: 2021-04-13 16:22:03
author: Patrick Kerwood
excerpt: With External DNS for Kubernetes you can automate the creation of DNS records based on an ingress resource. This is a great feature to have, especially in a dynamic development environment. You could have pipelines deploy feature branches which create ingress hostnames based on the branch name and let External DNS create DNS entries for them.
type: post
blog: true
tags: [dns, kubenetes]
meta:
- name: description
  content: How to setup External DNS for Kubernetes to handle public DNS entries. 
---

{{ $frontmatter.excerpt }}

![](./external-dns.png)

Actually External DNS does not only create DNS entries, it will also remove them again once the ingress resource is deleted. It would be appropriate to say that External DNS synchronizes ingresses resource hostnames with DNS records. ExternalDNS will keep track of which records it has control over, and will never modify any records which it doesn't have control over. It uses TXT records to label owned records.

External DNS supports a long list of DNS providers, you can find the complete list at the  official [Github page.](https://github.com/kubernetes-sigs/external-dns)

Under the [docs/tutorials](https://github.com/kubernetes-sigs/external-dns/tree/master/docs/tutorials) folder you can find how-to's on different providers. In this example I will be using Digital Ocean is my DNS provider.

## Installing External DNS

Create a namespace.
```sh
kubectl create namespace external-dns
```


External DNS needs a service account to operate. Below manifest will create the service account, a cluster role and a role binding. This step is the same regardless of which ever provider you choose.


```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
  namespace: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services","endpoints","pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions","networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: external-dns
``` 

Create the secrets necessary for your provider.
```sh
kubectl create secret generic digital-ocean-token --from-literal=token=<digital-ocean-token> -n external-dns
```

The next step is where we configure and deploy External DNS. Below is a deployment resource, which you can configure to fit your needs. 

 - `--source` is what External DNS is "monitoring" for hostnames, can be `service` or `ingress`.
 - `--provider` is your supported DNS provider.
 - `--registry=txt` is needed for External DNS to gain ownership of the created records.
 - `--txt-owner-id` is a unique ID set for the cluster. If you have multiple clusters, each cluster should have their own ID.
 - `--txt-prefix` will prefix the txt record. Some DNS providers like Digital Ocean will not allow `A` and `TXT` records with identical names.
 - `--domain-filter` is optional and will limit External DNS to that domain name.

Add your provider specific environment variables from the secrets created.

```yaml{23-28,30-34}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: external-dns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: external-dns
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: k8s.gcr.io/external-dns/external-dns:v0.7.6
        args:
        - --source=ingress
        - --provider=digitalocean
        - --registry=txt
        - --txt-owner-id=6b32e37c
        - --txt-prefix=xdns-
        - --domain-filter=example.org
        env:
        - name: DO_TOKEN
          valueFrom:
            secretKeyRef:
              name: digital-ocean-token
              key: token
```

## Example Ingress

Annotate your ingress resource with `external-dns.alpha.kubernetes.io/hostname`.

```yaml{7}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin
  annotations:
    kubernetes.io/ingress.class: nginx
    external-dns.alpha.kubernetes.io/hostname: hello-world.example.org
spec:
  rules:
  - host: hello-world.example.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: httpbin
            port:
              number: 80
```

External DNS will create the following records.

**A Record**
 - Name: `hello-world.example.org`
 - Value: `<ingress-ip>`

**TXT Record**
 - Name: `xdns-hello-world.example.org`
 - Value: `"heritage=external-dns,external-dns/owner=6b32e37c,external-dns/resource=ingress/default/hello-world"` 
  