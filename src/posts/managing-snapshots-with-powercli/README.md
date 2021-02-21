---
title: Managing Snapshots with PowerCLI
date: 2021-02-20 12:50:57
author: Patrick Kerwood
excerpt: PowerCLI is a great tool to manage resources in VMware vCenter. It would be even better if it was a "real" CLI tool, instead of a Powershell module. I often use it for creating, restoring or deleting snapshots on multiple machines, usually when dealing with a cluster of some sort.
blog: true
tags: [powershell, vmware]
---
PowerCLI is a great tool to manage resources in VMware vCenter. It would be even better if it was a "real" CLI tool, instead of a Powershell module. I often use it for creating, restoring or deleting snapshots on multiple machines, usually when dealing with a cluster of some sort.

## Spinning up  PowerCLI
First things first, let's get a Powershell environment. We all know that you can install Powershell on Linux by now, but I'm definitely not soiling my Fedora with Powershell. Luckly the PowerCLI team has made an official PowerCLI container with all included. 

Below are the commands for running the contianer with Docker or Podman, for which ever you are using. It will create the volume `powercli` which will store all files in the containers `/root` directory. That way you keep your shell history adn scripts you save to the root directory. 
```sh
docker run --rm -v powercli:/root -it vmware/powerclicore
```

```sh
podman run --rm -v powercli:/root:Z -it vmware/powerclicore
```
## Connecting to vCenter

Connect to the vCenter.
```
Connect-VIServer -Server vcenter.example.org 
```

::: tip
If you are using a selfsigned certificate, you need to run below command to be able to connect.
```sh
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
```
:::

## Creating Snapshots
Create an array with the VM objects you want to work with.
```sh
$VMs = Get-VM -Name vm-name-01,vm-name-02,vm-name-03
```

Create a snapshot of the VMs with the name `before-upgrade`.
```sh
$VMs | New-Snapshot -Name "before-upgrade"
```

## Listing Snapshots

List snapshots.
```sh
$VMs | Get-Snapshot
```

List only the latests snapshots created. 
```sh
$VMs | Get-Snapshot | where {$_.IsCurrent -eq $true} 
```

## Restoring Snapshots

Below command will restore the snaphot `before-upgrade` on each VM in the `$VMs` array. 
```sh
ForEach($vm in $VMs) {Get-Snapshot -VM $vm | where {$_.name -eq "before-upgrade"} | Foreach-Object { Set-VM -VM $vm -SnapShot $_ }}
```

Restore det latest snapshot created.
```sh
ForEach($vm in $VMs) {Get-Snapshot -VM $vm | where {$_.IsCurrent -eq $true} | Foreach-Object { Set-VM -VM $vm -SnapShot $_ -Confirm:$false}}
```
Start the VMs.
```sh
$VMs | Start-VM
```

## Deleting Snapshots

Below command will delete the snapshot `before-upgrade` on all VMs in the `$VMs` array. 
```sh
$VMs | Get-Snapshot | where {$_.name -eq "before-upgrade"} | Remove-Snapshot   
```

Or delete the latest one.
```sh
$VMs | Get-Snapshot | where {$_.IsCurrent -eq $true} | Remove-Snapshot   
```
---