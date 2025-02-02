---
title: Confluence Updater
date: 2025-02-02 19:12:14
author: Patrick Kerwood
excerpt: If you prefer keeping your documentation in Git, love writing in Markdown, but need to publish it in Confluence, Confluence Updater is the perfect solution. This tool allows you to set up a CI/CD pipeline that automatically converts Markdown to HTML and uploads it to Confluence Cloud whenever changes are made.
blog: true
tags: [tool, git]
meta:
  - name: description
    content: How to updated a Confluence page from a Markdown file in Git.
---

{{ $frontmatter.excerpt }}


I created [Confluence Updater](https://github.com/Kerwood/confluence-updater) to meet a requirement
for delivering documentation in Confluence Cloud. As someone who enjoys writing in Markdown, including this very blog,
and values GitOps as a single source of truth, I wanted a streamlined way to bridge the gap.

In this post, I’ll walk you through a few simple steps to achieve exactly that.

## confluence-updater.yaml
The first step is to create the required pages in Confluence at your desired location.
**Confluence Updater can only update existing pages**, so you’ll need to set them up manually.
Be sure to note the page ID, which you can find in the page's URL.

Next, in your repository, create a file named `confluence-updater.yaml` with the configuration tailored to your needs.
Confluence Updater will read this file and update each Confluence page with its corresponding Markdown file.

If your Markdown file starts with an `h1` header, Confluence Updater will automatically remove it and use it as the page title.
Alternatively, you can override the title using the `overrideTitle` property, regardless, the `h1` header will still be removed from the page.

```yml{3}
pages:
  - filePath: ./README.md
    overrideTitle: My fancy documentation
    pageId: <page-id>
    labels:
      - ci/cd

  - filePath: ./docs/some-documentation.md
    pageId: <page-id>
    labels:
      - ci/cd
```

## Github Actions
If you're using GitHub Workflows, there's a GitHub Action available.
Simply add the following action to your workflow file to use it.

```yaml
- name: Confluence Updater
  uses: kerwood/confluence-updater-action@v1
  with:
    fqdn: your-domain.atlassian.net
    user: ${{ secrets.USER }}
    api_token: ${{ secrets.API_TOKEN }}
```

Add your Atlassian username and API token as secrets on the repository.

See [kerwood/confluence-updater-action](https://github.com/Kerwood/confluence-updater-action) for more details.

## Other CI/CD tools
If you're not using Github, just add a step in your pipeline that downloads the latest or a specific version of
`confluence-updater` and run it. Below example is for a Azure DevOps pipeline.

```yaml{19}
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
      curl -L https://github.com/Kerwood/confluence-updater/releases/latest/download/confluence-updater-x86_64-unknown-linux-musl -o confluence-updater
      chmod +x confluence-updater
      ./confluence-updater -u $(CU_USER) -s $(CU_SECRET) --fqdn your-domain.atlassian.net
    displayName: 'Update Confluence Page'
```


Add below variables to the pipeline, remember to set `CU_SECRET` as a secret variable.

- `CU_USER` - Your confluence user.
- `CU_SECRET` - Your API token which you can generate [here.](https://id.atlassian.com/manage-profile/security/api-tokens)

## References

- [https://github.com/Kerwood/confluence-updater](https://github.com/Kerwood/confluence-updater)
- [https://github.com/Kerwood/confluence-updater-action](https://github.com/Kerwood/confluence-updater-action)

---
