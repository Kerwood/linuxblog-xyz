---
title: Setting up i3 on Fedora
date: 2022-02-12 13:23:47
author: Patrick Kerwood
excerpt: I finally decided to give the i3wm a go after postponing it for years. This post is my i3 setup with Polybar and other supporting applications.
type: post
blog: true
tags: [fedora]
meta:
- name: description
  content: How to setup i3 on Fedora.
---
{{ $frontmatter.excerpt }}

First things first, i use Fedora as my Desktop and luckily there an [Fedora i3 Spin](https://spins.fedoraproject.org/en/i3/).

## Installing i3-gaps

I like to have gaps in between my windows, so instead of using i3 I will replace it with i3-gaps.
```sh
sudo dnf install --allowerasing i3-gaps
```

## Install RPM Fusion

```sh
sudo dnf -y install https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
sudo dnf update
```

## Install Packages
Below command will install all tools, I use on Fedora. The list below is the i3 specific packages.

- [j4-dmenu-desktop](https://github.com/enkore/j4-dmenu-desktop) :: For displaying `.desktop`files in the `dmenu`.
- [lxappearance](https://github.com/lxde/lxappearance) :: For changing the icon theme, nm-applet icon will change. 
- [light](https://github.com/haikarainen/light) :: Used for controlling the keyboard brightness. 
- [picom](https://github.com/yshui/picom) :: A lightweight compositor for X11, like making windows transparent.
- [alacritty](https://github.com/alacritty/alacritty) :: A terminal emulator made in Rust.
- [polybar](https://github.com/polybar/polybar) :: Status bar
- [autorandr](https://github.com/phillipberndt/autorandr) :: For display settings based on display fingerprints.
- [playerctl](https://github.com/altdesktop/playerctl) :: For displaying Spotify status in Polybar.
- [feh](https://github.com/derf/feh) :: For setting the background.

```sh
sudo dnf install \
  git \
  j4-dmenu-desktop \
  lxappearance \
  light \
  picom \
  alacritty \
  polybar \
  autorandr \
  playerctl \
  feh \
  bat \
  httpie \
  vim \
  exa \
  the_silver_searcher \
  papirus-icon-theme \
  flameshot \
  zsh
```
## Dot files

Get the configuration files for the various applications.
```sh
cd ~/.config
git clone https://github.com/Kerwood/i3-dot-files.git
cd ./i3-dot-files
./create-symlinks.sh
```

## Install Nerd Fonts
FiraCode for Polybar and Hack for Alacritty.
```sh
# Download the fonts
http -d https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip
http -d https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.zip

# Unzip the files
mkdir Nerd\ Fonts
unzip FiraCode.zip -d Nerd\ Fonts
unzip Hack.zip -d Nerd\ Fonts

# Move the fonts
sudo mv Nerd\ Fonts /usr/share/fonts

# Remove
rm FiraCode.zip
rm Hack.zip
```

## Install Oh My Zsh

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
```

## Natural Scrolling.
In the `/usr/share/X11/xorg.conf.d/40-libinput.conf` file and add the `NaturalScrolling` line.
```{6}
Section "InputClass"
        Identifier "libinput touchpad catchall"
        MatchIsTouchpad "on"
        MatchDevicePath "/dev/input/event*"
        Driver "libinput"
        Option "NaturalScrolling" "true"
EndSection
```

## Install Betterlockscreen

<https://github.com/betterlockscreen/betterlockscreen>

Download this fork of i3lock. Betterlockscreen is dependent on it. Just dont uninstall the original i3lock. I had issues unlocking with the correct password after removeing it.
```sh
http -d https://github.com/Raymo111/i3lock-color/releases/latest/download/i3lock
chmod +x i3lock
sudo mv i3lock /usr/local/bin
```

Download Betterlockscreen.
```sh
http -d -o betterlockscreen https://raw.githubusercontent.com/betterlockscreen/betterlockscreen/next/betterlockscreen
chmod +x betterlockscreen
sudo mv betterlockscreen /usr/local/bin
```

Install som dependencies for Betterlockscreen.
```sh
sudo dnf copr enable aflyhorse/libjpeg
sudo dnf install libjpeg8 xrdb xset xdpyinfo
```

Update lock screen image.
```sh
betterlockscreen -u ~/Pictures/background.jpg
```

## Install TPL 
<https://linrunner.de/tlp/>
```sh
sudo dnf install https://repo.linrunner.de/fedora/tlp/repos/releases/tlp-release.fc$(rpm -E %fedora).noarch.rpm
sudo dnf install tlp acpi_call
```

## Install Slick Greeter
<https://github.com/linuxmint/slick-greeter>

Change the background path to fit your needs.

```sh
sudo dnf install slick-greeter

cat << EOF >>  /etc/lightdm/slick-greeter.conf
background=/usr/share/backgrounds/default.png
show-a11y=false
show-keyboard=false
EOF
```

## Setup Flatpak

<https://flatpak.org/setup/Fedora/>

```sh
sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

Install Flatpaks

```sh
flatpak install -y discord spotify
```


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