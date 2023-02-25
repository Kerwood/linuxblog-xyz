---
title: Setup Google Cloud Workload Identity in GKE
date: 2022-06-06 19:43:09
author: Patrick Kerwood
excerpt: |
  Using a Google service account in your GKE cluster is easy, just create the credential file, apply it as a secret and it's ready for use.
  But now you have a long lived credential that, if compromised, can be used from anywhere any time. Instead you can use a Kubernetes service account
  and Google Workload Identity to authenticate to Google Cloud. No need for credential files anymore.
type: post
blog: true
tags: [kubernetes, google]
meta:
- name: description
  content: How to use a Kubernetes service account for authentication using Google Cloud Workload Identity.
---
{{ $frontmatter.excerpt }}


In this example we're creating a Google Service Account (GSA) and giving it the `Viewer` role on a project.
We then create a Kubernetes Service Account (KSA), link them both together and deploy a Pod which is able to view resources in the given Google Project.

First of all, you will need to have a Workload Identity enabled GKE cluster. It is nothing more than a checkbox under the "Security" tab when creating a new cluster.
Have a look at the [docs](https://cloud.google.com/config-connector/docs/how-to/install-upgrade-uninstall#google-cloud-console) for more details.

## Create a Google Service Account
Create a GSA in an existing Google Project. It does not have to be the same project as where your GKE is located.
It can be any project in your organization.
```
gcloud iam service-accounts create <gsa-name> --project=<project-id>
```

Grant the `Viewer` role to the GSA to enable it to view resources in the Google Project.
```
gcloud projects add-iam-policy-binding <project-id> \
    --member "serviceAccount:<gsa-name>@<project-id>.iam.gserviceaccount.com" \
    --role "roles/viewer"
```

The GSA also needs a Workload Identity User role that points to a KSA in a Kubernetes Namespace.

Replace the `<kubernetes-namespace>` and `<ksa-name>` placeholders. The KSA does not need to exist
beforehand, we will create that in the next step.
```
gcloud iam service-accounts add-iam-policy-binding <gsa-name>@<project-id>.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:<project-id>.svc.id.goog[<kubernetes-namespace>/<ksa-name>]"
```

## Create a Kubernetes Service Account
Create the KSA in the namespace defined in the previous step.
```
kubectl create serviceaccount <ksa-name>
```

Give the KSA an annotation that points to the created GSA.
```
kubectl annotate serviceaccount <ksa-name> \
    iam.gke.io/gcp-service-account=<gsa-name>@<project-id>.iam.gserviceaccount.com
```

## Test the setup
To test the setup, we need to spin up a pod in the GKE cluster with the `serviceAccount` field specified.
Then we should be able to get an authorization token from the Google Metadata server and use that token to call a Google API endpoint.

To spin up a Pod save below manifest to a YAML file, specify your KSA and apply it with `kubectl`.
```
apiVersion: v1
kind: Pod
metadata:
  name: workload-identity-test
spec:
  containers:
    - name: bash
      image: bash:latest
      command: ["bash"]
      args: ["-c", "sleep infinity"]
  serviceAccount: <ksa-name>
```

After deploying the pod, exec into the container.
```
kubectl exec -it workload-identity-test -- bash
```

Install `curl` and `yq` which we will need. 
```
apk add curl yq
```

To get a valid authorization token from the Google Metadata server, run below command which stores it in the `$TOKEN` variable.
```
TOKEN=$(curl -sSL -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -r '.access_token')
```

Send a request to a Google API endpoint using the provided token. In the example below we are calling the IAM API to list all services account in the given Google Project.
```
curl -sSL -H "Authorization: Bearer $TOKEN" https://iam.googleapis.com/v1/projects/<project-id>/serviceAccounts
```

The result will look something like this.
```
{
  "accounts": [
    {
      "name": "projects/<project-id>/serviceAccounts/<gsa-name>@<project-id>.iam.gserviceaccount.com",
      "projectId": "<project-id>",
      "uniqueId": "104617829837452795642",
      "email": "<gsa-name>@<project-id>.iam.gserviceaccount.com",
      "displayName": "Google Service Account Name",
      "etag": "MDE3NDgzOTIK",
      "description": "Description of Service Account",
      "oauth2ClientId": "104617829837452795642"
    },
    ...
  ]
}
```

You can now use Application Default Credentials authentication with prefered client library. See below reference for more information.

## References
- [Client Library Authentication Docs](https://cloud.google.com/docs/authentication/client-libraries)
- [Installing Config Connector](https://cloud.google.com/config-connector/docs/how-to/install-upgrade-uninstall)
---


