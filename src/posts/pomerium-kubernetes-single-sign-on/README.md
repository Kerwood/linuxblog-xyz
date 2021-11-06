---
title: Pomerium, Kubernetes Single Sign-on with OpenID Connect
date: 2021-04-04 11:06:15
author: Patrick Kerwood
excerpt: In this tutorial I will setup Pomerium as an authentication proxy, with OpenID Connect, for the Kubernetes API. Since Pomerium will be functioning as a proxy for the KubeAPI, you can do this on a managed as well as an unmanaged cluster.
blog: true
tags: [pomerium, oidc, kubernetes]
meta:
  - name: description
    content: How to setup Pomerium as OIDC auth proxy for Kubernetes.
---

{{ $frontmatter.excerpt }}

This tutorial is almost a replica of the official documentation found [here.](https://www.pomerium.com/guides/kubernetes.html) I did run into some issue though and that is why I decided to write my own version of it.

::: tip Info
At the time of writing, Pomerium will send all the groups a user is member of, in one comma seperated string which Kubernetes will treat as a single groupname. Therefore you are not able to create a role binding based on groups if a user is a member of more than one group.

Pomerium is based on Envoy and Envoy currently does not support sending group names in multiple identical headers. An isse has been raised here -> [envoyproxy/envoy/issues/13053](https://github.com/envoyproxy/envoy/issues/13053).

I guess a work around could be to make sure the id token only contains a single group, but I haven't tested this.
:::

## Prerequisites

For this tutorial you will need the following.

- A working Kubernetes cluster with:
  - An ingress controller installed.
  - Cert Manager installed or a trusted certificate.
- A Pomerium supported OIDC Provider - [check them out here.](https://www.pomerium.com/docs/identity-providers/)
- A domain name for Pomerium. In this tutorial I will be using `kubeapi.example.org`. Point the domain name to your ingress controller IP.

## Identity provider details

I will be using Google as my identity provider and therefore I've followed [these steps.](https://www.pomerium.com/docs/identity-providers/google.html)

When creating your client you will need to add a callback URL. Use `https://<your-domain>/oauth2/callback`, eg. `https://kubeapi.example.org/oauth2/callback`.

Which ever provider you choose, you should end up with a client ID and secret.

## Setting up the Pomerium Service Account

Pomerium uses user impersonation to proxy your kubectl commands, therefore it will need a service account. The below manifest will create the service account, a cluster role and a role binding for Pomerium.

Save it to a file and apply it to the cluster.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: default
  name: pomerium
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pomerium-impersonation
rules:
  - apiGroups:
      - ''
    resources:
      - users
      - groups
      - serviceaccounts
    verbs:
      - impersonate
  - apiGroups:
      - 'authorization.k8s.io'
    resources:
      - selfsubjectaccessreviews
    verbs:
      - create
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: pomerium
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pomerium-impersonation
subjects:
  - kind: ServiceAccount
    name: pomerium
    namespace: default
```

Next create the role binding that binds the role `cluster-admin` to your OIDC username/email.

::: tip Tip
The username/email is case-sensitive. You can go to `https://kubeapi.example.org/.pomerium`, when you've reached the end of this tutorial, to see all the user claims you get from your IDP if you need to troubleshoot.
:::

```yaml{12}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admin-crb
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: my-email@example.org
```

## Create a Pomerium route

Get the Pomerium service account secret, which will be used in the Pomerium route.

```sh
SECRET_NAME=$(kubectl get serviceaccount/pomerium -o jsonpath="{.secrets[0].name}")
kubectl get secret $SECRET_NAME -o jsonpath={.data.token} | base64 -d
```

Save below route to a file and change it to fit your needs.

- The first line `- from:` is the URL to you want to use for the KubeAPI/kubectl.
- Set the `kubernetes_service_account_token` to token you extracted above.
- The `policy` defines who gets access. In this case the user with the email `user@example.com` or any user with an email in the `example.org` domain. You can find more examples [here.](https://www.pomerium.io/reference/#routes)

```yaml{5}
- from: https://kubeapi.example.org
  to: https://kubernetes.default.svc
  tls_skip_verify: true
  allow_spdy: true
  kubernetes_service_account_token: eyJhbGciOiJSUzI1NiIsImtpZCI6I.....
  policy:
    - allow:
        or:
          - email:
              is: user@example.com
          - domain:
              is: example.org
```

Save the route and create a base64 encoded string from it. We will use that in the next step.

```sh
base64 -w 0 routes.yml
```

## Deploying Pomerium

Below is a `Deployment`, `Service` and `Ingress` manifest. I have split them up, but you can of course bundle them together in one file.

There's a few environment variables in the deployment spec we need to set.

- Set the `AUTHENTICATE_SERVICE_URL` to your KubeAPI/kubectl URL
- Create a base64 encoded string for the `COOKIE_SECRET` with `head -c32 /dev/urandom | base64 -w 0`.
- Set the `IDP_PROVIDER` and `IDP_PROVIDER_URL`.
- Set `IDP_CLIENT_ID` and `IDP_CLIENT_SECRET`.
- Paste in the encoded route string you created in the `ROUTES` variable.

```yaml{26-39}
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: default
  name: pomerium
  labels:
    app: pomerium
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pomerium
  template:
    metadata:
      labels:
        app: pomerium
    spec:
      containers:
        - name: pomerium
          image: pomerium/pomerium:master
          env:
            - name: INSECURE_SERVER
              value: "true"
            - name: ADDRESS
              value: :80
            - name: AUTHENTICATE_SERVICE_URL
              value: https://kubeapi.example.org
            - name: COOKIE_SECRET
              value: <random-base64-encoded-string>
            - name: IDP_PROVIDER
              value: google
            - name: IDP_PROVIDER_URL
              value: https://accounts.google.com
            - name: IDP_CLIENT_ID
              value: <client-id-here>
            - name: IDP_CLIENT_SECRET
              value: <client-secret-here>
            - name: ROUTES
              value: LSBmcm9tOiBodHRwczovL2xpbm9k...
```

The service is pretty standard, nothing to change here.

```yaml
apiVersion: v1
kind: Service
metadata:
  namespace: default
  name: pomerium
spec:
  selector:
    app: pomerium
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

Change below `Ingress` manifest to fit your needs. This `Ingress` manifest uses NGINX as ingress controller and Cert Manager to supply a certificate. The endpoint has to have TLS or your identity provider will not redirect you to it.

```yaml{7,8,12,15}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pomerium
  namespace: default
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: le-http01
spec:
  tls:
  - hosts:
    - kubeapi.example.org
    secretName: pomerium-kubeapi-certtificate
  rules:
  - host: kubeapi.example.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pomerium
            port:
              number: 80
```

Bundle above manifests and deploy them to the cluster.

## Creating the kubeconfig file

Download the `pomerium-cli` from the Github [release page](https://github.com/pomerium/pomerium/releases) and move it to a folder in your `$PATH`, `kubectl` will use this binary in the `kubeconfig`.

If you want to add the cluster configuration to an existing `kubeconfig` file, follow the steps in the [original tutorial.](https://www.pomerium.com/guides/kubernetes.html#kubectl) Else just add below configuration to a `kubeconfig` file and run some `kubectl` commands.

Your browser will open a tab with the login window of your chosen identity provider. Once you've logged in, a token will be saved on your laptop that gives you access to the cluster. Once you have the token, you are able to run `kubectl` against the cluster.

```yaml{7,25}
apiVersion: v1
kind: Config
preferences: {}

clusters:
- cluster:
    server: https://kubeapi.example.org
  name: via-pomerium

contexts:
- context:
    cluster: via-pomerium
    user: via-pomerium
  name: via-pomerium
current-context: "via-pomerium"

users:
- name: via-pomerium
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - k8s
      - exec-credential
      - https://kubeapi.example.org
      command: pomerium-cli
      env: null
      provideClusterInfo: false
```

## References

- [https://www.pomerium.com/guides/kubernetes.html](https://www.pomerium.com/guides/kubernetes.html)
- [https://www.pomerium.io/docs/identity-providers/](https://www.pomerium.io/docs/identity-providers/)

---
