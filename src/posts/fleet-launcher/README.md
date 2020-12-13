---
title: OS Query Launcher
date: 2020-12-8 19:22:34
author: Patrick Kerwood
excerpt: This is a follow up on the "Kolide Fleet + OS Query" post. In the previous post we installed Fleet and enrolled a server manually, by installing OS Query and setting it up. In this post, we are going to create a package that includes everything. The package will be using gRPC instead of the REST.
type: post
blog: true
tags: [kolide, fleet, launcher]
---

This is a follow up on the [Kolide Fleet + OS Query](https://linuxblog.xyz/posts/kolide-fleet/) post. In the previous post we installed Fleet and enrolled a server manually, by installing OS Query and setting it up. In this post, we are going to create a package that includes everything. The package will be using gRPC instead of the REST.

## Setting up Traefik

Because the Launcher is utilizing gRPC instead of REST, we need to setup Traefik a bit different than my [default Traefik setup](https://linuxblog.xyz/posts/traefik-2-docker-compose/).

Fleet needs be setup to use TLS, because of gRPC. It does not have to be a valid certificate, since it's just between Fleet and Traefik. So we're going to create a selfsigned certificate.

We need to configure Traefik to skip verification on insecure certificates. If you configure Traefik with command line parameters, like I do, add below parameter to the `command` property of the Traefik service.
```yml
command:
  ...
  - --serverstransport.insecureskipverify=true
  ...
```

Create the selfsigned certificate and key.
```sh
openssl req -x509 -sha256 -nodes -days 1460 -newkey rsa:2048 -keyout kolide.key -out kolide.crt
```

Then we'll have to make a few changes to the [original](https://linuxblog.xyz/posts/kolide-fleet/)`fleet` service.
 - Comment out the `KOLIDE_SERVER_TLS` variable.
 - Add the `KOLIDE_SERVER_CERT` and `KOLIDE_SERVER_KEY` variables.
 - Add volume mounts that points to the selfsigned certificate and key.
 - Add the `traefik.http.services.fleet.loadbalancer.server.scheme=https` label.

```yml{14-16,18-20,27}
...
  fleet:
    image: kolide/fleet:2.6.0
    container_name: fleet
    restart: unless-stopped
    command: sh -c "/usr/bin/fleet prepare db && /usr/bin/fleet serve"
    environment:
      - KOLIDE_MYSQL_ADDRESS=mysql:3306
      - KOLIDE_MYSQL_DATABASE=kolide
      - KOLIDE_MYSQL_USERNAME=kolide
      - KOLIDE_MYSQL_PASSWORD=kolide
      - KOLIDE_REDIS_ADDRESS=redis:6379
      - KOLIDE_LOGGING_JSON=true
#      - KOLIDE_SERVER_TLS=false
      - KOLIDE_SERVER_CERT=/kolide.crt
      - KOLIDE_SERVER_KEY=/kolide.key
      - KOLIDE_AUTH_JWT_KEY=changeme
    volumes:
      - ./kolide.crt:/kolide.crt
      - ./kolide.key:/kolide.key
    networks:
      - traefik-proxy
      - fleet
    labels:
      - traefik.enable=true
      - traefik.http.services.fleet.loadbalancer.server.port=8080
      - traefik.http.services.fleet.loadbalancer.server.scheme=https
      - traefik.http.routers.fleet.rule=Host(`fleet.example.org`)
      - traefik.http.routers.fleet.tls.certresolver=le
      - traefik.http.routers.fleet.entrypoints=websecure
      - traefik.docker.network=traefik-proxy
...
```
Fleet and Traefik is ready to accept gRPC connections.

## Creating the Launcher package
The tool to create the package is called `package-builder`, its written in Go and we have to compile it from source.

Since Docker is a dependency of the `package-builder` binary and Docker is no longer supported on newer Fedora versions, I'm going to compile and run `package-builder` on a CentOS 7 server.

Install Docker, [https://docs.docker.com/engine/install](https://docs.docker.com/engine/install). The legacy version in the repositories (v. 1.13.1) will not work.

Install EPEL Release.
```sh
sudo yum install epel-release
```

Install the Go packages needed, for your distro.
```sh
sudo yum install golang go-bindata
```

Clone the launcher repo and build `package-builder`.
```sh
git clone https://github.com/kolide/launcher.git
cd launcher
make deps
make package-builder
```

Build the launcher package. Replace the `hostname` and `enroll_secret` with your own. You can find the enrollment secret in the Fleet WebUI after hitting the "Add New Host" button.
```sh
./build/package-builder make \
  --hostname=fleet.example.org:443 \
  --enroll_secret="8un7XC7MYXobVbXv7a1mATlz9v3c+uKa"
```

The package builder will output something simular.
```
Built packages in /tmp/launcher-package217092028
```

In that directory you will find a deb and a rpm package. When installing this package on a client it will install all necessary dependencies and will connect to Kolide Fleet.
```
/tmp/launcher-package217092028 
# ls -lh
total 44M
-rw-r--r--. 1 kerwood kerwood 22M Jul 15 22:35 launcher.linux-systemd-deb.deb
-rw-r--r--. 1 kerwood kerwood 22M Jul 15 22:35 launcher.linux-systemd-rpm.rpm
```

Copy the launcher `deb` or `rpm` file to the host you want to inroll into Fleet and install it.
```
yum install ./launcher.linux-systemd-rpm.rpm
```

Verify.
```
systemctl status launcher.launcher
```

## References
 - [https://github.com/kolide/launcher/blob/master/docs/launcher.md](https://github.com/kolide/launcher/blob/master/docs/launcher.md)
 - [https://github.com/kolide/launcher/blob/master/docs/package-builder.md](https://github.com/kolide/launcher/blob/master/docs/package-builder.md)
 ---