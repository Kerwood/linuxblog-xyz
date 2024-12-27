---
title: Using multiple SSH keys for Github
date: 2024-12-26 12:43:23
author: Patrick Kerwood
excerpt: If you use GitHub, you likely rely on an SSH key to clone repositories and sign commits. However, when working with a GitHub Enterprise-managed account, you must set up a separate SSH key because the same key cannot be shared across different accounts. This guide will show you how to create and configure a new SSH key for a second account. Additionally, you'll learn how to configure Git to automatically apply specific settings for repositories that match certain URL patterns.
type: post
blog: true
tags: [git]
meta:
- name: description
  content: How to setup multiple SSH keys and configure Git for different GitHub accounts
---
{{ $frontmatter.excerpt }}

In this example, I have already set up my personal GitHub account with an SSH key. The `~/.gitconfig` file below is configured to use this key for authentication and signing my commits.
```ini
[user]
  email = patrick@kerwood.dk
  name = Patrick Kerwood
  signingkey = /home/kerwood/.ssh/id_rsa.pub
 
[gpg]
  format = ssh
 
[gpg "ssh"]
  allowedSignersFile = /home/kerwood/.allowed_signers
 
[commit]
  gpgsign = true
```

Generate a new separate SSH key for the GitHub Enterprise-managed account, in this example, for the Blue Corp organization.

Use the following command to create the new SSH key with no password:
```sh
ssh-keygen -t rsa -b 4096 -C "patrick@bluecorp.com" -N "" -f ~/.ssh/id_rsa_bluecorp
```

The `ssh-keygen` command will generate a private and public key pair.  

::: tip
To add the keys to your GitHub account, go to your GitHub profile 🠪 Settings 🠪 SSH and GPG keys, and add the **public** key to "Authentication keys" and "Signing keys".
::: 

Add an `includeIf` section to the `.gitconfig` file.

The `path` property in the `includeIf` section takes a path to another Git config file that will be merged and overwrite the existing config.
It's important to add the section *below* the `user` section, this ensures that the default user information can be overridden when the `includeIf` condition is met.



In my case, my company has multiple GitHub organizations, all of which have names starting with `bluecorp-`. You can adjust `bluecorp-*/**` to match your own structure. The `**` at the end indicates all repositories within that organization.
Whenever Git encounters a repository with a remote URL matching the specified pattern, it will automatically include the referenced configuration file.
```ini
[user]
  email = patrick@kerwood.dk
  name = Patrick Kerwood
  signingkey = /home/kerwood/.ssh/id_rsa.pub
 
[includeIf "hasconfig:remote.*.url:git@github.com:bluecorp-*/**"]
  path = .gitconfig-bluecorp

...
```

Create the `.gitconfig-bluecorp` file in your home directory with the following content, customized to your specific needs.

```ini
[user]
  name = "Patrick Kerwood"
  email = "patrick@bluecorp.com"
  signingkey = /home/kerwood/.ssh/id_rsa_bluecorp.pub
 
[url "git@github.com-bluecorp"]
  insteadOf = git@github.com
```
The `url` section instructs Git to rewrite URLs. Whenever it encounters `git@github.com`, it will substitute the URL with `git@github.com-bluecorp`. This URL substitution will only happen whenever the `includeIf` condition is met.

The substituted URL is not an actual valid URL, but it doesn't have to be. Our SSH configuration will handle the mapping to `github.com`.

Set up the SSH config to support the URL substitution and use a different key depending on the URL.

Create the file `~/.ssh/config` with the content below.
```
Host github.com
  HostName github.com
  IdentityFile ~/.ssh/id_rsa

Host github.com-bluecorp
  HostName github.com
  IdentityFile ~/.ssh/id_rsa_bluecorp
```

Now, whenever you push or pull from any repository starting with `git@github.com:bluecorp-` using SSH, the new SSH key will automatically be used.

The last step is to add the public key to the `.allowed_signers` file, referenced in the first `.gitconfig` example. It's not mandatory, but it will eliminate the `gpg.ssh.allowedSignersFile needs to be configured and exist for ssh signature verification` error whenever you look at Git logs.

Add the following content to the `.allowed_signers` file, customized to your specific needs.  
The email address at the end of your SSH public key file should be the first entry in the `.allowed_signers` file.
```
patrick@bluecorp.com ssh-rsa AAAAB3NzaC1yc2E...<the rest of your ssh public key>
```
