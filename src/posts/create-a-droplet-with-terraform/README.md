---
title: Creating a Droplet with Terraform
date: 2020-04-22 09:04:25
author: Patrick Kerwood
excerpt: This is a quick how-to on creating a virtual machine in Digital Ocean also known as a Droplet, with Terraform
type: post
blog: true
tags: [terraform, 'digital ocean']
meta:
- name: description
  content: How to create a Digital Ocean droplet with Terraform.
---
{{ $frontmatter.excerpt }}

First,
- Go to the [Terraform download site](https://www.terraform.io/downloads.html) and grab the terraform binary for your operating system.
- Create a [Personal access token](https://cloud.digitalocean.com/account/api/tokens) on your Digital Ocean account.
- Create a new file called `do.tf`.

To work with Digital Ocean you must use [Terraform Digital Ocean Provider](https://www.terraform.io/docs/providers/do/index.html)

## Collecting intel
There are a few ways to work with this DO access token. One way is to export the token as an environmental variable and the Provider will pick it up by its self.

Run the `export`command with your token.
```sh
export DIGITALOCEAN_TOKEN=5015ae648ed7550611abe7a569...
```

Copy paste the below code into the `do.tf` file.
```
provider "digitalocean" {
}

resource "digitalocean_droplet" "<resource-name>" {
  image  = "<image>"
  name   = "<name>"
  region = "<region>"
  size   = "<size>"
  ssh_keys = [
      "<sshkey-fingerprint>"
  ]
}

output "vm1_ipv4" {
  value = "${digitalocean_droplet.<resource-name>.ipv4_address}"
}
```

There are a few values that we need to replace.
- `resource-name`
- `name`
- `sshkey-fingerprint`
- `image`
- `region`
- `size`

For the `resource-name` we will use `vm1`. This name is used to reference the Terraform resource, as you can see in the last `output` statement.

The `name` is the name of the virtual machine in DO. Here we will use `dockerhost01`.

The `sshkey-fingerprint` is the fingerprint of the SSH key that you have added to your [Digetal Ocean account](https://cloud.digitalocean.com/account/security).

For finding the last placeholders, we will use the official DO CLI tool `doctl`.
Download the binary from [Github](https://github.com/digitalocean/doctl/releases), run `doctl auth init` and paste in the access token you created before.

Next run below command to get a list of images. We will use `centos-7-x64`.
```sh
$ doctl compute image list-distribution

31354013    6.9 x32              snapshot    CentOS          centos-6-x32          true      20
34902021    6.9 x64              snapshot    CentOS          centos-6-x64          true      20
47384041    30 x64               snapshot    Fedora          fedora-30-x64         true      20
50903182    7.6 x64              snapshot    CentOS          centos-7-x64          true      20
53871280    19.10 x64            snapshot    Ubuntu          ubuntu-19-10-x64      true      20
53893572    18.04.3 (LTS) x64    snapshot    Ubuntu          ubuntu-18-04-x64      true      20
54203610    16.04.6 (LTS) x32    snapshot    Ubuntu          ubuntu-16-04-x32      true      20
55022766    16.04.6 (LTS) x64    snapshot    Ubuntu          ubuntu-16-04-x64      true      20
56521921    31 x64               snapshot    Fedora          fedora-31-x64         true      20
58134745    8.1 x64              snapshot    CentOS          centos-8-x64          true      20
58230630    v1.5.5               snapshot    RancherOS       rancheros             true      20
59416024    12.1 x64 ufs         snapshot    FreeBSD         freebsd-12-x64        true      20
59417005    12.1 x64 zfs         snapshot    FreeBSD         freebsd-12-x64-zfs    true      20
59418769    11.3 x64 ufs         snapshot    FreeBSD         freebsd-11-x64-ufs    true      20
59418853    11.3 x64 zfs         snapshot    FreeBSD         freebsd-11-x64-zfs    true      20
59917914    2430.0.0 (alpha)     snapshot    CoreOS          coreos-alpha          true      20
59918930    2411.1.0 (beta)      snapshot    CoreOS          coreos-beta           true      20
60030597    2345.3.0 (stable)    snapshot    CoreOS          coreos-stable         true      20
60461760    10.3 x64             snapshot    Debian          debian-10-x64         true      20
60463541    9.12 x64             snapshot    Debian          debian-9-x64          true      20
```

Same goes for region. Here we choose `ams3`.
```sh
$ doctl compute region list

Slug    Name               Available
nyc1    New York 1         true
sgp1    Singapore 1        true
lon1    London 1           true
nyc3    New York 3         true
ams3    Amsterdam 3        true
fra1    Frankfurt 1        true
tor1    Toronto 1          true
sfo2    San Francisco 2    true
blr1    Bangalore 1        true
```

And last, the size. We choose `s-1vcpu-1gb`.
```sh
$ doctl compute size list

Slug               Memory    VCPUs    Disk    Price Monthly    Price Hourly
s-1vcpu-1gb        1024      1        25      5.00             0.007440
512mb              512       1        20      5.00             0.007440
s-1vcpu-2gb        2048      1        50      10.00            0.014880
1gb                1024      1        30      10.00            0.014880
s-3vcpu-1gb        1024      3        60      15.00            0.022320
s-2vcpu-2gb        2048      2        60      15.00            0.022320
s-1vcpu-3gb        3072      1        60      15.00            0.022320
...
```

## Deploying the machine
The config now looks like below code and is ready to run.

```
provider "digitalocean" {
}

resource "digitalocean_droplet" "vm1" {
  image  = "centos-7-x64"
  name   = "dockerhost01"
  region = "ams3"
  size   = "s-1vcpu-1gb"
  ssh_keys = [
      "12:f8:7e:78:61:b4:bf:e2:de:24:15:96:4e:d4:72:53"
  ]
}

output "vm1_ipv4" {
  value = "${digitalocean_droplet.vm1.ipv4_address}"
}
```

To deploy the server, you first have to initialize Terraform.
```sh
$ tf terraform init

Initializing the backend...

Initializing provider plugins...
- Checking for available provider plugins...
- Downloading plugin for provider "digitalocean" (terraform-providers/digitalocean) 1.16.0...
...
```

Run `terraform apply` to deploy the server.
```sh
$ terraform apply
...
digitalocean_droplet.vm1: Creating...
digitalocean_droplet.vm1: Still creating... [10s elapsed]
digitalocean_droplet.vm1: Still creating... [20s elapsed]
digitalocean_droplet.vm1: Still creating... [30s elapsed]
digitalocean_droplet.vm1: Still creating... [40s elapsed]
digitalocean_droplet.vm1: Still creating... [50s elapsed]
digitalocean_droplet.vm1: Still creating... [1m0s elapsed]
digitalocean_droplet.vm1: Creation complete after 1m8s [id=189739678]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

vm1_ipv4 = 165.22.207.61
```

After a minute or so, your VM should be deployed. As you can see on the bottom line, the IP address is `165.22.207.61`. Which you also can get with the following command.
```sh
$ terraform output vm1_ipv4
165.22.207.61
```
---