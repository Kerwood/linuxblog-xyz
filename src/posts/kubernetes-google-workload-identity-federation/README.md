---
title: Setting up Workload Identity Federation between Kubernetes and Google Cloud.
date: 2025-11-11 20:21:43
author: Patrick Kerwood
excerpt: |
  In this blog post, I’ll show how to set up Workload Identity Federation between Kubernetes and Google Cloud Platform. This setup allows an application running in Kubernetes to use its Kubernetes service account to impersonate a Google service account and access cloud resources.
type: post
blog: true
tags: [kubernetes, google, oidc]
meta:
  - name: description
    content: Setting up Workload Identity Federation between Kubernetes and Google Cloud.
---

{{ $frontmatter.excerpt }}

If a workload running in a non-GKE Kubernetes cluster needs to access Google Cloud resources,
it must authenticate in some way. One common approach is to create and use static service account credential files.
However, this method introduces security and maintenance challenges, these credentials become secrets that must be securely stored,
periodically rotated, and are vulnerable if leaked.

A better alternative is to use Workload Identity Federation.
This approach allows your Kubernetes application to authenticate to Google Cloud using dynamically issued Kubernetes
service account tokens, eliminating the need for static credentials.
It not only removes the burden of credential rotation but also simplifies and strengthens the authentication process.

In this tutorial, we’ll create a JavaScript application that lists objects in a Google Cloud Storage bucket. The application will use the Google SDK to obtain a Google access token by exchanging its Kubernetes service account token.

To follow along, you’ll need the following tools installed.
- `docker` - [https://www.docker.com/](https://www.docker.com/)
- `kind` - [https://kind.sigs.k8s.io/](https://kind.sigs.k8s.io/)
- `jq` - [https://jqlang.org/](https://jqlang.org/)
- `kubectl` - [https://kubernetes.io/docs/tasks/tools/#kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl)

## Creating the Kubernetes Cluster

You can, of course, use any existing Kubernetes cluster you have access to.
However, for this tutorial, we’ll create a local cluster using Kind.

First, you’ll need to configure the `issuer` and `jwks-uri` settings by creating a Kind configuration file.  

The URL doesn’t need to be reachable, since we’ll statically configure the JSON Web Keys in the Google Cloud provider. This means you can use any issuer URL you like.

Create a file named `kind-config.yaml` with the following content.
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            service-account-issuer: "https://cluster-1.example.org"
            service-account-jwks-uri: "https://cluster-1.example.org/openid/v1/jwks"
```

Create the cluster.
```sh
kind create cluster --name cluster-1 --config kind-config.yaml
```

### Export JSON Web Keys
When the cluster has been create, export the JSON Web Keys to a file.
```sh
kubectl get --raw /openid/v1/jwks > jwks.json
```

If you’re using an existing cluster and aren’t sure what your current issuer URL is, you can retrieve it with the following command.
```sh
kubectl get --raw /.well-known/openid-configuration  | jq
```

## Creating the Workload Identity Pool

Set your active Google Cloud project.
```sh
gcloud config set project <your-project-id>
```

Next, create the Workload Identity Pool. In this tutorial, we’ll name it `kubernetes`.
```sh
gcloud iam workload-identity-pools create kubernetes --location global
```

## Creating the Identity Pool Provider
Next, create a provider in the newly created identity pool. In this example, the provider will be named `cluster-1`.

Be sure to replace the `--issuer-uri` value with your own. For this provider, we’ll set the allowed audience to `<pool-name>/<provider-name>`.

The `--jwk-json-path` argument specifies the location of the exported JSON Web Keys.

By explicitly providing the JWKS file, Google Cloud will use those keys directly instead of attempting to fetch them from the issuer URL dynamically.
This is useful in setups where the issuer URL is not publicly accessible.

```sh
gcloud iam workload-identity-pools providers create-oidc cluster-1 \
    --location global \
    --workload-identity-pool kubernetes \
    --issuer-uri "https://cluster-1.example.org" \
    --attribute-mapping "google.subject=assertion.sub" \
    --allowed-audiences="kubernetes/cluster-1" \
    --jwk-json-path="./jwks.json"
```

## Creating the Storage Bucket
Next, let’s create a Cloud Storage bucket that our application will list objects from.

You’ll need to choose a globally unique name for your bucket, as bucket names in Google Cloud must be unique across all projects worldwide.

```sh
gcloud storage buckets create gs://<bucket-name>
```
Optionally, you can go to the Google Cloud Console and upload some files to the bucket.
This will give your application objects to list during testing.

## Creating the Google Service Account

Now we’re going to create a Google service account and allow the Kubernetes service account to impersonate it.

Create a service account named `object-lister`.

```sh
gcloud iam service-accounts create object-lister
```

Next, grant the **Storage Object Viewer** role to the service account so it can list the objects in the bucket.

This role provides read-only access to the objects, allowing your application to view or list them without modifying or deleting any data.
```sh
gcloud storage buckets add-iam-policy-binding gs://<bucketname> \
  --member "serviceAccount:object-lister@<project-id>.iam.gserviceaccount.com" \
  --role="roles/storage.objectViewer"
```

The role we’re assigning below is the `workloadIdentityUser` role.
This role allows external entities to impersonate the service account, in this case, the Kubernetes service account.

In the `--member` argument, `default:object-lister` refers to `<k8s-namespace>:<k8s-service-account>`.

```sh
POOL_NAME=$(gcloud iam workload-identity-pools describe kubernetes --location global --format='get(name)')

gcloud iam service-accounts add-iam-policy-binding object-lister@<project-id>.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member principal://iam.googleapis.com/$POOL_NAME/subject/system:serviceaccount:default:object-lister
```

The final step is to enable the **IAM Service Account Credentials API**, which is required to impersonate the service account.
```sh
gcloud services enable iamcredentials.googleapis.com
```

## Creating the Credentials Configuration

Now that the federation is set up, we need to create a credentials configuration file using the `gcloud` CLI.

The following command will generate a `credential-config.json` file, which provides instructions to the Google SDK on how to obtain credentials.
The SDK will look for a token at `/var/run/secrets/tokens/sa-token` in the final container running in Kubernetes.

Kubernetes ensures this token exists and automatically rotates it as needed.
The SDK then uses this token to exchange it for a Google access token, which can impersonate the service account specified in the `--service-account` argument.
```sh
POOL_NAME=$(gcloud iam workload-identity-pools describe kubernetes --location global --format='get(name)')

gcloud iam workload-identity-pools create-cred-config \
    $POOL_NAME/providers/cluster-1 \
    --service-account="object-lister@<project-id>.iam.gserviceaccount.com" \
    --credential-source-file=/var/run/secrets/tokens/sa-token \
    --output-file="credential-config.json"
```

## Creating the JS App

To create the application, we’ll need three files. Save the contents provided below into separate files, one for each.

**package.json**
```js
{
  "name": "object-lister",
  "version": "1.0.0",
  "main": "server.js",
  "author": "",
  "license": "ISC",
  "description": "",
  "dependencies": {
    "@google-cloud/storage": "^7.17.3",
    "express": "^5.1.0"
  }
}
```

**server.js**

```js
const express = require("express");
const { Storage } = require("@google-cloud/storage");
const app = express();

//---[ Storage Client ]----------------
// This is where the authentication happens.
const storage = new Storage();

//---[ Name of your bucket ]-----------
const BUCKET_NAME = process.env.BUCKET_NAME;

if (!BUCKET_NAME) {
  throw new Error("Environment variable BUCKET_NAME is not set.");
}

app.get("/", (_req, res) => {
  storage.bucket(BUCKET_NAME).getFiles()
    .then(([files]) => {
      const fileNames = files.map((file) => file.name);
      res.json({ bucket: BUCKET_NAME, files: fileNames });
    })
    .catch((err) => {
      console.error("Error listing objects:", err);
      res.status(500).json({ error: err.message });
    });
});

app.listen(3000, () => {
  console.log(`Server is running on http://localhost:3000`);
});
```

**Dockerfile**
```dockerfile
FROM node:22-alpine

WORKDIR /app
COPY package.json server.js ./
RUN npm install
EXPOSE 3000

CMD ["server.js"]
```

Next, build and push the Docker image to an image registry.

For this tutorial, you can use [ttl.sh](https://ttl.sh/), which provides an anonymous and ephemeral image registry,
perfect for temporary testing without needing an account.

```sh
docker build --push -t ttl.sh/object-lister:24h .
```

## Deploying the Application

To deploy the application, we need to create three Kubernetes resources.

- A Service Account for the application to use.
- A ConfigMap containing the credentials configuration.
- The Deployment itself.

Add all three resources to a file called `deployment.yaml` and deploy them together.

First, add a Service Account named `object-lister.`
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: object-lister
  namespace: default
---
```

Take the content from your own `credentials-config.json` file and replace the placeholder data below with your own.

Since the file does not contain sensitive information, it does not need to be stored as a secret and can safely be included in a ConfigMap.
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: application-default-credentials
  namespace: default 
data:
  credentials-config.json: |
    {
      "universe_domain": "googleapis.com",
      "type": "external_account",
      "audience": "//iam.googleapis.com/projects/914229223449/locations/global/workloadIdentityPools/kubernetes/providers/cluster-1",
      "subject_token_type": "urn:ietf:params:oauth:token-type:jwt",
      "token_url": "https://sts.googleapis.com/v1/token",
      "credential_source": {
        "file": "/var/run/secrets/tokens/sa-token"
      },
      "service_account_impersonation_url": "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/object-lister@project-id.iam.gserviceaccount.com:generateAccessToken"
    }
---
```

Add the following Kubernetes Deployment.

Comments have been included above the key properties that are relevant to this tutorial.
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: object-lister
  namespace: default 
spec:
  selector:
    matchLabels:
      app: object-lister
  template:
    metadata:
      labels:
        app: object-lister
    spec:
      # Set the Kubernetes service account.
      serviceAccountName: object-lister
      volumes:
      # Adding the service account token as a projected volume.
      - name: service-account-token
        projected:
          sources:
          - serviceAccountToken:
              # Set the audience, which must match the --allowed-audiences
              # when the Google provider was created.
              audience: kubernetes/cluster-1
              expirationSeconds: 3600
              path: sa-token
      # Adding the application-default-credentials ConfigMap as a volume. 
      - name: adc
        configMap:
          name: application-default-credentials
      containers:
      # Set the name of you built image.
      - image: ttl.sh/object-lister:24h
        name: express
        env:
        # Set the name of your bucket.
        - name: BUCKET_NAME
          value: "<my-bucket-name>" # <----------------------- CHANGE THIS
        # This environment variable tells the Google SDK where to look for
        # for the credentials-config.json file.
        - name: GOOGLE_APPLICATION_CREDENTIALS
          value: "/adc/credentials-config.json"
        ports:
        - containerPort: 3000
          protocol: TCP
        volumeMounts:
        # Mounts the service account token into the container.
        - name: service-account-token
          mountPath: /var/run/secrets/tokens
          readOnly: true
        # Mounts the credentials-config.json file into the container.
        - name: adc   
          mountPath: /adc
          readOnly: true
---
```

Deploy the resources.
```sh
kubectl apply -f deployment.yaml
```

The application should now be successfully deployed an functional.
To test it out, port forward port 3000 to your local machine and test it out.

```sh
kubectl port-forward pod/<pod-name> 3000:3000
```

Make a curl request to `localhost:3000` and see the magic happen.

```sh
$  curl -s localhost:3000 | jq
{
  "bucket": "bambam101",
  "files": [
    "Atuin_Desktop-0.1.10-1.x86_64.rpm",
    "doctl-1.141.0-linux-amd64.tar.gz"
  ]
}
```

## Dynamically adding the JSON Web Keys

Typically, when setting up federation, you’d ideally want the identity provider to read the JSON Web Keys from a public endpoint.
This allows the keys to be rotated automatically without needing to update them anywhere manually.

For security reasons, your Kubernetes control plane should not allow anonymous access, and in most managed Kubernetes solutions, this is disabled by default.

However, you can create a service within your cluster that exposes the `/jwks` and `/openid-configuration` endpoints publicly.
Just make sure that the issuer URL matches the public URL where this service is accessible.

Fortunately, there’s already a project available that does exactly this.
If you’re interested in implementing such a setup, check out the GitHub project at [https://github.com/gawsoftpl/k8s-apiserver-oidc-reverse-proxy ](https://github.com/gawsoftpl/k8s-apiserver-oidc-reverse-proxy).

## References

- [Google Docs: Configure Workload Identity Federation with other identity providers](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-other-providers)
- [Google Docs: Attribute Mapping](https://cloud.google.com/iam/docs/workload-identity-federation#mapping)
- [Google Docs: Attribute Conditions](https://cloud.google.com/iam/docs/workload-identity-federation#conditions)
- [Google Docs: Principal Types](https://cloud.google.com/iam/docs/workload-identity-federation#principal-types)
- [Google Docs: Create a credential configuration](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-other-providers#create-credential-config)

---
