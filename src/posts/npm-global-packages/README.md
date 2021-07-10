---
title: Install global NPM packages locally
date: 2021-07-03 11:20:56
author: Patrick Kerwood
excerpt: Here's a quick how-to on installing NPM global packages locally without sudo.
type: post
blog: true
tags: [nodejs, npm]
meta:
- name: description
  content: How to install global NPM packages without sudo/root privileges.
---
{{ $frontmatter.excerpt }}

There are a few different ways of achieving the same end result, but I found this way the most simple.

First, run below command to configure NPM to use the `~/.local/` directory. This will modify `~/.npmrc` to include `prefix=~/.local/`.
```sh
npm config set prefix '~/.local/'
```

If your `$PATH` does not already include `~/.local/bin` you must add it. Replace `.zshrc` with what ever shell you would use other than `zsh`.
```sh
echo 'export PATH=$PATH:~/.local/bin' >> ~/.zshrc
```

That is it. Now, when ever you install a global package, it will be installed to `~/.local/bin` and you will be able to run it.

```sh
npm install -g ngrok
```
