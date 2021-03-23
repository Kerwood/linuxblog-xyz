---
title: Fedora Workstation Setup
date: 2020-11-15 12:23:58
author: Patrick Kerwood
excerpt: A couple of years ago I installed Fedora on my laptop. And honestly I haven't looked back since, I absolutely love my Fedora desktop. This post is just a list of commands I use to install my applications after a fresh Fedora install, for my own deteriorating memory.
type: post
blog: true
tags: [fedora]
---
{{ $frontmatter.excerpt }}

## Install RPM fusion

```sh
sudo dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf update
```

## DNF Install

Note: bind `flameshot gui` to what ever keybind in Gnome settings. Config command is `flameshot config`

Note: Peek requires "GNOME on Xorg", at time of writing, to work.

```sh
sudo dnf -y install httpie bat git jq zsh vim filezilla flameshot gnome-tweaks papirus-icon-theme arc-theme remmina tilix celluloid peek ffmpeg podman buildah skopeo
```

## Install Sublime text

```sh
sudo dnf config-manager --add-repo https://download.sublimetext.com/rpm/stable/x86_64/sublime-text.repo
sudo dnf -y install sublime-text
```

## Install Brave

```sh
sudo dnf config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/x86_64/
sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
sudo dnf -y install brave-browser
```

## Install Oh My Zsh

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
```

For Tilix add below to ~/.bashrc or ~/.zshrc

> At time of writing, Tilix has a [minor bug](https://github.com/gnunn1/tilix/issues/1954) in Fedora 33. 

```sh
if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
    source /etc/profile.d/vte.sh
fi
```

## Setup Flatpak

<https://flatpak.org/setup/Fedora/>

```sh
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

## Install Flatpaks

```sh
flatpak install -y discord spotify slack bitwarden
```

## Ulauncher

<https://ulauncher.io/#Download>

```sh
http -d https://github.com/Ulauncher/Ulauncher/releases/download/5.8.1/ulauncher_5.8.1_fedora32.rpm
sudo dnf install ulauncher_5.8.1_fedora32.rpm
```
**Fix blank properties bug.**

Find simlar line below in `/usr/share/applications/ulauncher.desktop` and replace it.
```sh
Exec=env WEBKIT_DISABLE_COMPOSITING_MODE=1 GDK_BACKEND=x11 /usr/bin/ulauncher --hide-window
```

**Fix Wayland keybind.**

[https://github.com/Ulauncher/Ulauncher/wiki/Hotkey-In-Wayland](https://github.com/Ulauncher/Ulauncher/wiki/Hotkey-In-Wayland)


> Install package wmctrl (needed to activate app focus)
> Open Ulauncher Preferences and set hotkey to something you'll never use
> Open OS Settings > Devices > Keyboard > Add Hotkey > Scroll all the way down > Click +
> In Command enter ulauncher-toggle, set name and shortcut, then click Add


## Install VSCode

```sh
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
```

```sh
cat << EOF | sudo tee /etc/yum.repos.d/vscode.repo
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
```

```sh
sudo dnf install code
```

## Install kubectl

```sh
curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl
chmod +x kubectl
mv kubectl ~/.local/bin
```
---