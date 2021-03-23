---
title: Creating a Kubernetes service account
date: 2021-01-08 15:06:08
author: Patrick Kerwood
excerpt: This is an example on how to create a service account in Kubernetes, with a couple of role bindings. I'll also show how to create a kubeconfig file to use the service account with kubectl.
type: post
blog: true
tags: [kubernetes]
---
{{ $frontmatter.excerpt }}


Kubernetes comes with a set of built-in cluster roles, which you can limit to a specific namespace if you want. Use `kubectl get clusterroles` to get a list of roles and `kubectl describe clusterrole admin` to get the list of permissions for that role. You can also create your own custom roles, check out [Kubernetes RBAC documentation.](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#role-and-clusterrole)

## Create the Service Account
Below is the manifest for creating a service account, pretty simple. This will create a service account named `my-service-account`.
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-service-account
  namespace: default
```

Here's the CLI equivalent of the manifest.
```sh
kubectl create serviceaccount my-service-account --namespace default
```

## Create the role bindings 
Now that the service account is created, we need to bind some roles to it. Below manifest will bind the `admin` role on the `default` namespace and the `viewer` role on cluster level.
```yaml{2,5,8,11,15,20,24}
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: RoleBinding          # Namespace specific
metadata:
  name: my-service-account-binding
  namespace: default       # Apply for namespace: default
subjects:
- kind: ServiceAccount
  name: my-service-account # Service account name
roleRef:
  kind: ClusterRole
  name: admin              # Role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding   # Cluster specific
metadata:
  name: default-view-cluster-binding
subjects:
- kind: ServiceAccount
  name: my-service-account # Service account name
  namespace: default
roleRef:
  kind: ClusterRole
  name: view               # Role
  apiGroup: rbac.authorization.k8s.io
```

Here's the CLI equivalents of the manifest.
```sh
kubectl create rolebinding my-service-account-admin-binding --clusterrole=admin --serviceaccount=default:my-service-account --namespace default
```
```sh
kubectl create clusterrolebinding my-service-account-view-cluster-binding --clusterrole=viewer --serviceaccount=default:my-service-account
```
## Create a kubeconfig file
A Kubernetes service account is technically only meant for services, inside the cluster, to be able to interact with the Kubernetes API. But you can, even though its not recommended, use the account from outside the cluster.

Run below command. From the information outputted, you'll need the `certificate-authority-data`, `server` and `cluster.name` properties.
```sh
kubectl config view --flatten --minify
```

Get the service account token.
```sh
kubectl --namespace default get secret $(kubectl -n default get secret | grep my-service-account | awk '{print $1}') -o json | jq -r '.data.token' | base64 -d
```

Replace the gathered information with the placeholders in below example and your're good to go. 
```yaml{6,9,10,11,14}
apiVersion: v1
kind: Config
users:
- name: my-service-account
  user:
    token: <replace this with the secret token>
clusters:
- cluster:
    certificate-authority-data: <replace this with certificate-authority-data info>
    server: <replace this with server url>
  name: <replace this with cluster name>
contexts:
- context:
    cluster: <replace this with cluster name>
    user: my-service-account
  name: my-service-account
current-context: my-service-account
```

Below is some bash commands to store the values in variables and generate the kubeconfig. Just change the `NAMESPACE` and `SA_NAME` variables in the top and paste all the lines into your terminal. This will create a `sa-kubeconfig`file, `kubectl` and `jq` are required.
```sh
NAMESPACE="default" # Change me
SA_NAME="my-service-account" # Change me

SA_TOKEN=$(kubectl --namespace $NAMESPACE get secret $(kubectl --namespace $NAMESPACE get secret | grep $SA_NAME | awk '{print $1}') -o json | jq -r '.data.token' | base64 -d)
CONFIG=$(kubectl config view --flatten --minify -o json | jq '.clusters[0]')
CLUSTER_NAME=$(echo $CONFIG | jq '.name')
SERVER_URL=$(echo $CONFIG | jq '.cluster.server')
CA_DATA=$(echo $CONFIG | jq '.cluster."certificate-authority-data"')

cat << EOF > sa-kubeconfig
apiVersion: v1
kind: Config
users:
- name: $SA_NAME
  user:
    token: $SA_TOKEN
clusters:
- cluster:
    certificate-authority-data: $CA_DATA
    server: $SERVER_URL
  name: $CLUSTER_NAME
contexts:
- context:
    cluster: $CLUSTER_NAME
    user: $SA_NAME
  name: $SA_NAME
current-context: $SA_NAME
EOF
```

---