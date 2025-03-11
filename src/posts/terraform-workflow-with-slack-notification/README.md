---
title: Running a Terraform Workflow in GitHub with Slack Notifications
date: 2025-03-11 18:15:03
author: Patrick Kerwood
excerpt: Automating infrastructure deployments using Terraform and GitHub Actions is a common practice. In this post, we’ll walk through setting up a Terraform workflow in GitHub that runs a Terraform Plan and sends a Slack notification with the diff whenever there are changes detected. 
type: post
blog: true
tags: [github, terraform, slack]
meta:
- name: description
  content: How to setup a Github workflow running Terraform with Slack notifications.
---
{{ $frontmatter.excerpt }}

## Setting Up Slack Integration for GitHub Workflows
Before setting up the GitHub workflow, you need to create a Slack application that will be used to post messages. Start by visiting the [Slack API](https://api.slack.com/apps) page and create a new application from scratch. Once created, go to **OAuth & Permissions**, navigate to **Scopes**, and add the `chat:write` OAuth scope to the application.

Next, install the application by clicking the "**Install to (organization)**" button at the top of the same page.

---
![install-app](./install-app.png)

---

After installation, you will see a **Bot User OAuth Token** above the install button, which will look something like `xoxb-xxxxxxxxxxxxxxx`.
This token will be required later.

Even though the application is installed, you still need to invite the bot into your Slack channel.
To do this, mention it in the channel using `@MyBotName`.
To find the Channel ID, open the channel’s menu and view the channel details, the ID will be displayed at the bottom of the popup.

Finally, go to your GitHub repository’s **Settings**, navigate to **Secrets and variables** → **Actions**, and create two repository secrets,
one named `SLACK_BOT_TOKEN` with the **Bot User OAuth Token**, and another named `SLACK_CHANNEL_ID` with the Channel ID.

Your Slack application is now set up and ready to use in your GitHub workflow.

## Triggering the workflow

The YAML below defines the GitHub workflow triggers. The workflow runs in three scenarios:

- **Manual execution**: Triggered via GitHub Actions (`workflow_dispatch`).
- **Scheduled runs**: Executes daily at 9 AM UTC (`cron: "0 9 * * *"`).
- **Code changes**: Runs whenever any Terraform (`.tf`) files in the main branch have been modified.

```yaml
name: Terraform
 
on:
  workflow_dispatch:
  schedule:
    - cron: "0 9 * * *" 
  push:
    branches:
      - main
    paths:
      - "**/*.tf"

permissions:
  contents: read    # This is required for actions/checkout

jobs:
  <insert steps here>
```

In the next few steps we will add jobs to the workflow file.

The workflow consists of two primary jobs:
- `terraform-plan`: Runs the Terraform plan step and determines if there are changes. If changes are detected, it sends a notification to Slack.
- `terraform-apply`: Applies changes upon approval if any changes are detected in the previous job.

## Terraform Plan Job

Add the YAML below to the end of the workflow from the previous step. I've included comments in the YAML to explain
each step, but I'll briefly walk through them here as well.

This example does not include authentication for whatever Terraform is working with, you’ll need to handle that yourself.

The job starts with its usual repository checkout and `terraform init` steps, as expected. However, in the "plan" step,
we introduce an extra enhancement, we use the `-detailed-exitcode` flag.
This makes Terraform exit with different codes depending on whether changes are detected:

- **Exit code 0** means no changes, and the workflow will terminate.
- **Exit code 1** indicates an error occurred. The next step will check for this error code and terminate the workflow if detected.
- **Exit code 2** indicates that changes were detected, triggering both the Slack notification and the `terraform-apply` job.

The `continue-on-error: true` property ensures that the workflow does not terminate when a non-zero exit code is returned.

Additionally, the plan step includes the `-out` parameter to save the planned changes to a file. If changes are found, we serialize the diff output and store it in an environment variable.

In the Slack step, a message is sent to the specified channel. A thread is then created under that message, where the Terraform diff is posted.

```yaml
jobs:
  terraform-plan:
    runs-on: ubuntu-latest

    # This will capture the exit code in the Terrafrom plan step as an output.
    # The next will only run depending on this exit code.
    outputs:
      planExitcode: ${{ steps.plan.outputs.exitcode }}
    steps:
      - name: Git clone the repository
        uses: actions/checkout@v4
 
      # Implement authentication for what ever you are using
      # Terraform for.
 
      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
 
      - run: terraform init
 
        # Run the Terraform plan step and output the diff into a file
        # The -detailed-exitcode argument will make Terraform exit with a
        # dependeing on the outcome.
        #   - 0: Succeeded, diff is empty (no changes)
        #   - 1: Errored
        #   - 2: Succeeded, there is a diff
        # We also need the "continue-on-error: true" parameter becase if
        # there are changes that needs to be applied it will exit with code 2
        # and the workflow should continue instead of terminating.
      - id: plan
        continue-on-error: true
        run: terraform plan -no-color -detailed-exitcode -out=tfplan
 
        # If the plan step above exits with error code 1, it means something went
        # wrong and the we will terminate the workflow.
      - name: Check for Plan Failure
        if: steps.plan.outputs.exitcode == 1
        run: exit 1

      # The rest of the stop in this Job will only run if the Terraform plan
      # step exits with the error code 2.
 
 
        # Get the plan output from the tfplan file, save it to a text file,
        # remove the linebreak at the very first line, serialize the data
        # using jq and add it to an environment variable.
      - name: Get Terraform diff
        if: steps.plan.outputs.exitcode == 2
        id: tf-diff
        run: |
          terraform show -no-color tfplan > terraform_plan.txt
          sed -i '1{/^$/d}' terraform_plan.txt  # Remove first empty line of file
          echo "terraform_plan=$(jq --raw-input --slurp '.' < terraform_plan.txt)" >> $GITHUB_ENV
           

        # Send af message to a Slack channel with a link to the pending workflow.
      - name: Notify in Slack channel
        uses: slackapi/slack-github-action@v2
        if: steps.plan.outputs.exitcode == 2
        id: notify-channel
        with:
          method: chat.postMessage
          token: ${{ secrets.SLACK_BOT_TOKEN }}
          payload: |
            channel: ${{ secrets.SLACK_CHANNEL_ID }}
            text: "*Terraform Action Approval Pending*\n*Workflow URL:* https://github.com/${{ github.repository }}/actions/runs/${{ github.run_id }}"
 
        # Start a thread on the Slack messaged posted in the previous step and post
        # a message with the Terraform plan output.
      - name: Add Terraform plan to notification
        uses: slackapi/slack-github-action@v2
        if: steps.plan.outputs.exitcode == 2
        with:
          method: chat.postMessage
          token: ${{ secrets.SLACK_BOT_TOKEN }}
          payload: |
            channel: ${{ secrets.SLACK_CHANNEL_ID }}
            thread_ts: "${{ steps.notify-channel.outputs.ts }}"
            text: "Terraform plan output"
            blocks:
              - type: rich_text
                elements:
                  - type: rich_text_section
                    elements:
                      - type: text
                        text: Terraform Plan Output
                        style:
                          bold: true
                  - type: rich_text_preformatted
                    elements:
                      - type: text
                        text: ${{ env.terraform_plan }}
 
```

## Terraform Apply Job

The last job is straightforward. The `if:` property ensures that the job runs only if the `planExitcode` output from the previous step is 2.
The `environment: production` property enforces deployment protection rules before execution.
If any required reviewers are configured, the job will pause and wait for approval before proceeding.

You can setup an environment in your repository's **Settings** under **Environments**.

```yaml
jobs:
  # The Job will only run if the exit code of the Terraform plan step in the previous Job was 2.
  # The "environment: production" parameter tells Github that this Job is running
  # in the production environment which is setup to be approved before it is
  # allowed to run.
  terraform-apply:
    needs: terraform-plan
    if: needs.terraform-plan.outputs.planExitcode == 2
    environment: production
    runs-on: ubuntu-latest
    steps:
      - name: Git clone the repository
        uses: actions/checkout@v4
 
      # Implement authentication for what ever you are using
      # Terraform for.
 
      - uses: hashicorp/setup-terraform@v3
 
      - run: terraform init
 
      - id: apply
        run: terraform apply -auto-approve

```
---
