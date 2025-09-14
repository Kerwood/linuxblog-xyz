---
title: Setting up Workload Identity Federation in Google Cloud for Github pipelines
date: 2024-06-06 23:21:43
author: Patrick Kerwood
excerpt: Setting up authentication for pushing images to Google Artifact Registry from a Github pipeline is usually done by creating a static, forever valid, credential file for at service account, which will probably never be rotated. An alternative to that is to use Workload Identity Federation to exchange a Github issued JWT token with a Google token and use that for authentication.
type: post
blog: true
tags: [github, oidc, google]
meta:
  - name: description
    content: Setting up Workload Identity Federation between Github and Google Cloud.
---

{{ $frontmatter.excerpt }}

## Prerequisites

You will need the `gcloud` cli tool for creating Google Cloud resources.

Let's start by setting some variables we can reuse.

```sh
SA_NAME=github-action     # The name of the Google Service Account used by the pipeline.
G_PROJECT_ID=<project-id> # Your Google Project ID
```

Set the given project ID as the working project for the `gcloud` CLI.

```sh
gcloud config set project $G_PROJECT_ID
```

## Google service account

Create a service account that will be used to push images to the registry.

```sh
gcloud iam service-accounts create $SA_NAME \
  --description "Used for Github Pipeline Actions"
```

Give the service account the `artifactregistry.writer` role.  
Replace the `<artifact-registry-name>` and `<artifact-registry-location>` with your own values.

```sh
gcloud artifacts repositories add-iam-policy-binding <artifact-registry-name> \
  --location <artifact-registry-location> \
  --role roles/artifactregistry.writer \
  --member serviceAccount:$SA_NAME@$G_PROJECT_ID.iam.gserviceaccount.com
```

## Identity Pool

Create an identity pool named `github`.

```sh
gcloud iam workload-identity-pools create github --location global
```

This step was pretty simple, but we will come back this identity pool again.

## OIDC Provider

Create an OIDC provider in the newly created identity pool.

This is where we decide what claims/attributes gets transfered, or mapped, from the Github token to the Google token that we want.
First we need to know what claims are actually available on the Github token.  
For that we can look here: [github/understanding-the-oidc-token](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token)

Below is a table with some claims that I have chosen to use. The `google.subject` is required and should be unique.
The rest of the claims you can mix and match as you like.

| Google                     | Github                     |                                                                                     |
| :------------------------- | :------------------------- | ----------------------------------------------------------------------------------- |
| google.subject             | assertion.sub              | Required. A unique and immutable identifier for the user.                           |
| attribute.actor            | assertion.actor            | The personal account that initiated the workflow run.                               |
| attribute.aud              | assertion.aud              | The URL of the repository owner, such as the organization that owns the repository. |
| attribute.repository       | assertion.repository       | The repository from where the workflow is running.                                  |
| attribute.repository_owner | assertion.repository_owner | The name of the organization in which the repository is stored.                     |

The above mappings goes into the `--attribute-mapping` argument, in the example below.

```sh
gcloud iam workload-identity-pools providers create-oidc github-actions \
    --location global \
    --workload-identity-pool github \
    --attribute-mapping "google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.aud=assertion.aud,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
    --issuer-uri "https://token.actions.githubusercontent.com"
```

You can read more about attribute mappings [here.](https://cloud.google.com/iam/docs/workload-identity-federation#mapping)

## Attribute Conditions

::: warning
GitHub uses a single issuer URL across all organizations and some of the claims embedded in OIDC tokens might not be unique to your organization.
To help protect against spoofing threats, you must use an attribute condition that restricts access to tokens issued by your GitHub organization.
:::

Getting back to that Identity Pool.

> Attribute conditions are CEL expressions that can check assertion attributes and target attributes. If the
> attribute condition evaluates to true for a given credential, the credential is accepted. Otherwise, the
> credential is rejected. You must have an attribute mapping for all attribute condition fields.

Now that we've figured out which attributes to use, we can now create an attribute condition.  
This is optional but definitely recommended.

```sh
gcloud iam workload-identity-pools providers update-oidc github-actions \
  --location global \
  --workload-identity-pool github \
  --attribute-condition "assertion.repository_owner == '<your-user-or-org-name>'"
```

You can read more about attribute conditions [here.](https://cloud.google.com/iam/docs/workload-identity-federation#conditions)

## Setting the IAM Policy Binding

Last step is creating a policy binding that gives the Google service account the `iam.workloadIdentityUser` role and
bind it to a principal or principalSet.

Get the name of the created identity pool and store it in a variable.

```sh
POOL_NAME=$(gcloud iam workload-identity-pools describe github --location global --format='get(name)')
# output: projects/<project-number>/locations/global/workloadIdentityPools/github
```

You have a couple of options for the `--member` argument.  
If you want to bind the policy to the required, unique and immutable `google.subject` attribute you mapped, you will
have to use the `principal://` like en below example.

```sh
principal://iam.googleapis.com/$POOL_NAME/subject/<your-subject-value>
```

Or if you want to use any of the optional attributes you've mapped, you should use `principalSet://`.  
This option gives a bit more flexibility and enables you to have multiple pipelines in different repositories, to use the
same Google service account if you want.

Below command creates the needed policy binding and binds it to whatever JWT token from the "github" identity pool that
has the `repository` attribute set with a value of `<repo-owner>/<repo-name>`.

```sh
gcloud iam service-accounts add-iam-policy-binding $SA_NAME@$G_PROJECT_ID.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member principalSet://iam.googleapis.com/$POOL_NAME/attribute.repository/<repo-owner>/<repo-name>
```

That's it.

## Setting up the pipeline

The below workflow example will use the `auth` action from the [github/google-github-actions](https://github.com/google-github-actions)
repository to do the authentication. The second `docker-auth` step then uses the exchanged access token from Google to login to
the image registry.

It should now by possible to push images to Artifact Registry using the normal `docker push` command.

```yaml
name: example-pipeline
jobs:
  build:
    name: Build Image
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - name: Google Auth
        id: auth
        uses: "google-github-actions/auth@v2"
        with:
          token_format: "access_token"
          service_account: <service-account-name>@<google-project-id>.iam.gserviceaccount.com
          workload_identity_provider: projects/<google-project-number>/locations/global/workloadIdentityPools/github/providers/github-actions

      - name: Docker Auth
        id: docker-auth
        uses: "docker/login-action@v3"
        with:
          username: "oauth2accesstoken"
          password: "${{ steps.auth.outputs.access_token }}"
          registry: "europe-docker.pkg.dev"
```

## References

- [Github Docs: Understanding the OIDC Token](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token)
- [Google Docs: Attribute Mapping](https://cloud.google.com/iam/docs/workload-identity-federation#mapping)
- [Google Docs: Attribute Conditions](https://cloud.google.com/iam/docs/workload-identity-federation#conditions)
- [Google Docs: Configure Workload Identity Federation with deployment pipelines](https://cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines)
- [Google Github Actions](https://github.com/google-github-actions)

---
