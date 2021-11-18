---
title: Confluence Updater
date: 2021-11-16 22:12:14
author: Patrick Kerwood
excerpt: If you like to keep your documentation in Git, love writing in markdown but are somehow required to deliver documentation in Confluence, look no further. With Confluence Updater you can build a CI/CD pipeline to render a markdown page to html on change and upload it to Confluence Cloud.
blog: true
tags: [tool]
meta:
  - name: description
    content: How to updated a Confluence page from a mardown page in Git.
---

{{ $frontmatter.excerpt }}

Confluence Updater is a tool I created in Rust because I had a requirement to deliver documentation in Confluence Cloud. I love writing in markdown, even this blog I do in markdown, and I'm a big fan of GitOps and the idea of using Git as a single source of truth.

In this blog post I will show the few easy steps to do exacly that. I will be using Azure DevOps (_God forbid_), but any CI/CD pipeline will do.

The first step is to create the actual pages in Confluence, in the location you want. Confluence Updater can only update an existing page. Write down the page ID, you will find it in the URL of the page.

In your repository, create a file named `confluence-config.yaml` with below content. Confluence Updater will read this file and .... well it's pretty self explanatory, have a look at it.

You will need to add an entry for each file you want to update.

```yml
content:
  - filePath: './README.md'
    title: My fancy documentation
    pageId: '<page-id>'
    contentType: page
    labels:
      - ci/cd
  - filePath: './docs/some-documentation.md'
    title: My fancy documentation
    pageId: '<page-id>'
    contentType: page
    labels:
      - ci/cd
```

Next create a file named `azure-pipelines.yml` and add below yaml code to it. The logic is very simple, when ever a change is commited to `README.md` or any file in the `docs` folder, the pipeline will run.

Change the version number in the `curl` command to fit the newest version.

```yml{17,19}
name: Confluence Updater

trigger:
  branches:
    include:
      - master
  paths:
    include:
      - README.md
      - docs/*

pool:
  vmImage: ubuntu-latest

steps:
  - bash: |
      curl -L https://github.com/Kerwood/confluence-updater/releases/download/v1.0.0/confluence-updater-x86_64-unknown-linux-musl -o confluence-updater
      chmod +x confluence-updater
      ./confluence-updater update -u $(CU_USER) -s $(CU_SECRET) --fqdn $(CU_FQDN)
    displayName: 'Update Confluence Page'
´´´
```

Commit the changes and push it to the repository. In Azure DevOps, press the `Set up build` button to create the new pipeline.

Confluence Updater needs some parameters to run. Add below variables to the pipeline by pressing the `Variables` button, remember to set `CU_SECRET` as a secret variable.

- `CU_USER` - Your confluence user.
- `CU_SECRET` - Your API token which you can generate [here.](https://id.atlassian.com/manage-profile/security/api-tokens)
- `CU_FQDN` - The FQDN to your Confluence Cloud instance eg. `your-domain.atlassian.net`

Save your pipeline and run it.

## References

- [https://github.com/Kerwood/confluence-updater](https://github.com/Kerwood/confluence-updater)

---
