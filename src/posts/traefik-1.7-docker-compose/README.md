---
title: Traefik v1.7 Configuration with Let's Encrypt
date: 2020-04-24 11:13:48
author: Patrick Kerwood
excerpt: A Docker Compose configuration example with Traefik v1.7 including Let's Encrypt HTTP/DNS validation.
type: post
blog: true
tags: [traefik, docker-compose, config]
---
This is just a basic Docker Compose file with configuration for Traefik v1.7.

At time of writing, Traefik v2 is out and introduces a number of breaking changes, so dont use this config for v2. Version 1.7 though is supported until end of 2021.


This configuration redirects `http` to `https` and requests certificates from Let's Encrypt. Just change `<your-email@goes-here.com>` to your mail address, create the `acme.json` file and change the path to the `acme.json` file.

```bash
mkdir /home/traefik
touch /home/traefik/acme.json
chmod 600 /home/traefik/acme.json
```

## With Let's Encrypt HTTP validation
```yaml{21,31}
version: "3.7"
networks:
  default:
    name: traefik-proxy

services:
  traefik:
    image: traefik:v1.7
    container_name: traefik
    restart: unless-stopped
    command: --api \
             --loglevel=info \
             --defaultentrypoints=http,https
             --entrypoints="Name:http Address::80 Redirect.EntryPoint:https" \
             --entrypoints="Name:https Address::443 TLS" \
             --docker \
             --docker.endpoint="unix:///var/run/docker.sock" \
             --docker.watch=true \
             --docker.exposedbydefault=false \
             --acme=true \
             --acme.email=<your-email@goes-here.com> \
             --acme.entrypoint=https
             --acme.storage=/acme.json \
             --acme.onhostrule=true \
             --acme.httpChallenge.entryPoint=http
    ports:
      - 80:80
      - 443:443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /home/traefik/acme.json:/acme.json
```

## With Let's Encrypt DNS validation
Below is the a Docker Compose example with Let's Encrypt DNS validation. Your domain name needs to be hosted by a supported DNS provider. You can get a list of supported providers [here.](https://docs.traefik.io/v1.7/configuration/acme/#provider)

In the example below, I'm using Digital Ocean as DNS provider and in the list linked above, I can see that I need a `DO_AUTH_TOKEN` environment variable with a valid API token/key.
```yaml{21,26,29}
version: "3.7"
networks:
  default:
    name: traefik-proxy

services:
  traefik:
    image: traefik:v1.7
    container_name: traefik
    restart: unless-stopped
    command: --api \
             --loglevel=info \
             --defaultentrypoints=http,https
             --entrypoints="Name:http Address::80 Redirect.EntryPoint:https" \
             --entrypoints="Name:https Address::443 TLS" \
             --docker \
             --docker.endpoint="unix:///var/run/docker.sock" \
             --docker.watch=true \
             --docker.exposedbydefault=false \
             --acme=true \
             --acme.email=<your-email@goes-here.com> \
             --acme.entrypoint=https
             --acme.storage=/acme.json \
             --acme.onhostrule=true \
             --acme.dnschallenge=true \
             --acme.dnschallenge.provider=digitalocean \
             --acme.dnschallenge.delaybeforecheck=10
    environment:
      - DO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxx
    ports:
      - 80:80
      - 443:443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /home/traefik/acme.json:/acme.json
```

## Label your containers
Add labels to your containers to make Traefik proxy traffic to them. Also they need to be in the `traefik-proxy` network.

```yaml
    labels:
      - traefik.enable=true
      - traefik.frontend.rule=Host:webapp.example.com
      - traefik.port=3000
```

Below is a Hello World example. As you can see, I expose port 3000. It dosen't really do anything, but I like that you can see the ports this container is listing on.
```yaml
version: '3.7'

networks:
  default:
    name: traefik-proxy

services:
  hello-world:
    image: kerwood/hello-world
    container_name: hello-world
    expose:
      - 3000
    labels:
      - traefik.enable=true
      - traefik.frontend.rule=Host:webapp.example.com
      - traefik.port=3000
```
---