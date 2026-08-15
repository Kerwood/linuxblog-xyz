---
title: Graceful Shutdown on Power Loss with NUT and Proxmox
date: 2026-08-14 21:10:00
author: Patrick Kerwood
excerpt: |
  In this post, I’ll walk through configuring Network UPS Tools on a Proxmox host, from getting the UPS
  recognized over USB to triggering a clean shutdown after a set amount of time on battery, instead of
  waiting until the battery is nearly empty.
blog: true
tags: [proxmox]
meta:
  - name: description
    content: Configure Network UPS Tools on Proxmox VE to monitor a USB-connected UPS and shut the host down gracefully during a power outage.
---

{{ $frontmatter.excerpt }}

A UPS that nobody is listening to is just a battery that delays the crash. If the power is out longer than the
battery lasts, the host still loses power mid-write, and on a hypervisor that means every running guest goes down hard.

Network UPS Tools solves this by monitoring the UPS and shutting the host down while there is still battery left.
It is packaged in Debian, so it is available directly on Proxmox VE. The setup below uses an Eaton Ellipse ECO 1600
connected over USB, but the same steps apply to any UPS with a supported USB HID interface.

## How NUT Fits Together

NUT splits the work across three processes, which is why a single UPS ends up with five configuration files.
Understanding the split makes the rest of this post much easier to follow.

- **The driver**, `usbhid-ups` in our case, is the only component that talks to the hardware.
- **The server**, `upsd`, takes the data from the driver and serves it over TCP port 3493.
- **The client**, `upsmon`, connects to the server, watches the status and runs the shutdown when needed.

Data flows in one direction: UPS → driver → `upsd` → `upsmon` → shutdown.

The important consequence is that `upsmon` is a network client even when it runs on the same machine as the UPS.
It connects to `upsd` over localhost, which means it needs a username and password just like any remote client would.
That credential pair is the piece most people trip over, so it is worth keeping in mind.

Each process has its own configuration file, all of them in `/etc/nut`.

- `nut.conf` decides which processes run at all.
- `ups.conf` configures the driver.
- `upsd.conf` configures the server.
- `upsd.users` holds the server’s accounts.
- `upsmon.conf` configures the client.

## Installation

```sh
apt install nut nut-server nut-client
```

The Debian package ships with everything disabled by default, so nothing will run until the configuration is in place.

## Finding the UPS

Before touching any configuration, confirm the host actually sees the UPS.

```sh
lsusb
```

You are looking for a line identifying the UPS vendor. Eaton and MGE devices use vendor ID `0463`.

```
Bus 002 Device 003: ID 0463:ffff MGE UPS Systems UPS
```

If nothing shows up, this is a hardware problem rather than a configuration problem. Watch `dmesg -w` while unplugging
and replugging the cable.

On a Dell PowerEdge, also check **System BIOS → Integrated Devices → User Accessible USB Ports**,
since setting it to *Only Back Ports On* will silently disable the front ports. Cheap or long USB cables are another
common culprit, as UPS interfaces tend to be picky about them.

Once the device appears, `nut-scanner` will generate a ready-made driver configuration.

```sh
nut-scanner -U
```

```
[nutdev1]
	driver = "usbhid-ups"
	port = "auto"
	vendorid = "0463"
	productid = "FFFF"
	product = "Ellipse ECO"
	serial = "000000000"
	vendor = "EATON"
```

Note the serial number consisting entirely of zeros. That is a placeholder rather than a real serial, and matching on
it can break after a reconnect, so leave it out of the configuration.

## Configuration

### /etc/nut/nut.conf

This file decides which NUT processes are allowed to start. Out of the box it is set to `none`, which is why both
services will start and immediately exit with a message about adjusting the configuration.

```ini
MODE=standalone
```

Use `standalone` when the UPS is attached to this machine and only this machine monitors it. Use `netserver` if other
hosts on the network should monitor the same UPS.

### /etc/nut/ups.conf

This configures the driver and gives the UPS an internal name, in this case `eaton`. That name is referenced later.

```ini
[eaton]
    driver = usbhid-ups
    port = auto
    vendorid = 0463
    productid = FFFF
    desc = "Eaton Ellipse ECO 1600"
    pollinterval = 5
```

You can verify the driver in the foreground before handing it over to systemd.

```sh
upsdrvctl -D start eaton
```

Look for a line naming the subdriver, for example `Using subdriver: MGE HID 1.46`. That confirms the device was properly
recognized rather than falling back to a generic HID path. Stop it again afterwards with `upsdrvctl stop`, since systemd
will manage the driver from here as `nut-driver@eaton.service`.

### /etc/nut/upsd.conf

With no `LISTEN` directive at all, `upsd` binds to localhost only, which is what you want for a standalone setup.
If you plan to expose the UPS to something like Home Assistant, add the following instead.

```ini
LISTEN 0.0.0.0 3493
```

### /etc/nut/upsd.users

This is where the accounts live. The `upsmon master` line is a shorthand that grants exactly the permissions `upsmon`
needs on the machine physically connected to the UPS. A second read-only account is useful if you want Home Assistant
or a metrics exporter polling the UPS.

```ini
[upsmon]
    password = a-long-random-password
    upsmon master

[monuser]
    password = another-password
    upsmon slave
```

The distinction between master and slave only matters with multiple machines. The master is the host holding the USB
cable, it shuts down last and cuts UPS power. Slaves just watch the status and shut themselves down.

### /etc/nut/upsmon.conf

Finally, tell the client which UPS to watch and which account to use. The password here must match `upsd.users` exactly.

```ini
MONITOR eaton@localhost 1 upsmon a-long-random-password master
MINSUPPLIES 1
SHUTDOWNCMD "/sbin/shutdown -h +0"
POWERDOWNFLAG /etc/killpower
```

### Permissions

The configuration files contain plaintext passwords, so lock them down before starting anything.

```sh
chown root:nut /etc/nut/*.conf /etc/nut/upsd.users
chmod 640 /etc/nut/*.conf /etc/nut/upsd.users
```

## Starting and Verifying

```sh
systemctl restart nut-server nut-monitor
upsc eaton
```

You should get a list of variables back.

```
battery.charge: 100
battery.charge.low: 20
battery.runtime: 1668
ups.load: 18
ups.status: OL
```

If `upsc` returns a connection error, `journalctl -u nut-server -u nut-monitor -u 'nut-driver@*' -n 30` will usually
name the problem directly. A missing `MODE` in `nut.conf` and a mismatched password between `upsd.users` and
`upsmon.conf` are the two most likely candidates.

Some log lines during startup look alarming but are harmless. A missing `upsmon.pid` on first start simply means no
previous instance was running, and the `upsnotify` messages about systemd watchdog integration are cosmetic. NUT logs
them once and moves on.

## Deciding When to Shut Down

Out of the box, `upsmon` waits for the UPS to report low battery before doing anything. On the setup above that means
waiting until `battery.charge.low` of 20 percent.

To find out what that actually buys you, I pulled the mains plug and let the UPS run down. My server draws 18 percent
of the Ellipse ECO 1600, which works out to roughly 180 watts, and at that load it lasted about 20 minutes before
cutting power. That means the default policy leaves me somewhere around four minutes to stop every guest and halt the
host once the low battery threshold is hit.

That may be enough. It may also not be, and the way to find out is to measure rather than guess.

```sh
time systemctl stop pve-guests
```

Run that, note the number, then start the guests again. A single VM that ignores ACPI shutdown requests can stretch
this out considerably, and per-VM shutdown timeouts in the guest **Options** tab are worth setting for that reason.

If the margin looks thin, a better policy is to shut down after a fixed period on battery. Short outages and flickers
are ignored entirely, and anything longer triggers a clean shutdown with most of the battery still in reserve.
This is what `upssched` is for.

### /etc/nut/upsmon.conf

Add the notification hooks. `upsmon` already detects the on-battery and back-on-line events, these lines tell it to
run a command in addition to logging them.

```ini
NOTIFYFLAG ONBATT	SYSLOG+EXEC
NOTIFYFLAG ONLINE	SYSLOG+EXEC
NOTIFYCMD /usr/sbin/upssched
```

### /etc/nut/upssched.conf

`upssched` is essentially a stopwatch. It starts a named countdown when the power fails and cancels it if the power
comes back first.

```ini
CMDSCRIPT /usr/local/bin/upssched-cmd
PIPEFN /run/nut/upssched/upssched.pipe
LOCKFN /run/nut/upssched/upssched.lock

AT ONBATT * START-TIMER onbatt 600
AT ONLINE * CANCEL-TIMER onbatt
```

The pipe and lock paths are worth getting right. On Debian, `/usr/lib/tmpfiles.d/nut-common-tmpfiles.conf` creates
`/run/nut/upssched` owned by `nut:nut` specifically for these files, so use that directory rather than `/run/nut` directly.

### /usr/local/bin/upssched-cmd

When a timer expires, `upssched` runs this script with the timer name as the first argument. The package ships an
example at `/usr/bin/upssched-cmd`, but placing your own version under `/usr/local/bin` keeps it safe from being
overwritten during a package upgrade.

```sh
#!/bin/sh
case $1 in
	onbatt)
		logger -t upssched-cmd "Timer expired: on battery too long, initiating shutdown"
		/sbin/upsmon -c fsd
		;;
	*)
		logger -t upssched-cmd "Unrecognized command: $1"
		;;
esac
```

```sh
chmod 750 /usr/local/bin/upssched-cmd
chown root:nut /usr/local/bin/upssched-cmd
systemctl restart nut-monitor
```

Note the use of `upsmon -c fsd` rather than calling `shutdown` directly. The `fsd` command runs `SHUTDOWNCMD` and also
drops the `killpower` flag file, which tells the UPS to cut its output late in the shutdown sequence. That is what
makes the UPS notice when mains power returns and cycle its outlets. Calling `shutdown` on its own halts the machine
correctly but leaves it dark after the outage ends, which rather defeats the purpose.

## Testing

None of this is worth anything untested. Set the timer to something short while you verify the chain.

```ini
AT ONBATT * START-TIMER onbatt 30
```

```sh
systemctl restart nut-monitor
journalctl -f -t upssched-cmd -u nut-monitor
```

Now pull the mains plug. Within a few seconds you should see the on-battery notification, and 30 seconds later the log
line from the script followed by the shutdown starting. If you would rather not shut the host down on the first attempt,
comment out the `upsmon -c fsd` line so the script only logs, which proves the timer and script fire correctly.

Do a full end-to-end test eventually though. The part most likely to surprise you is whether the host actually powers
back on once mains returns, and that only shows up in a complete run. Set the timer back to its real value afterwards.

---
