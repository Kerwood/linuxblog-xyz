---
title: Traefik v3 Configuration with Let's Encrypt
date: 2025-03-05 11:13:48
author: Patrick Kerwood
excerpt: In this post, we’ll walk through setting up Traefik as an application proxy with Docker Compose, including automatic provisioning of Let's Encrypt TLS certificates via HTTP and DNS validation.
type: post
blog: true
tags: [traefik, docker-compose]
meta:
- name: description
  content: How to setup Traefik and Let's Encrypt with Docker Compose.
---
{{ $frontmatter.excerpt }}

Start by creating an `acme.json` file for Traefik to store the certificates and set the proper permissions.
```sh
touch acme.json && chmod 600 acme.json
```

In both examples below, replace `<your-email@goes-here.com>` with you own email address.

## With Let's Encrypt HTTP validation
The example below enables the ACME HTTP Challenge and automatically redirects HTTP traffic to HTTPS.
```yaml{19}
networks:
  default:
    name: traefik-proxy

services:
  traefik:
    image: traefik:v3
    container_name: traefik
    restart: unless-stopped
    command:
      - --api=true
      - --api.dashboard=false
      - --log.level=info
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.websecure.address=:443
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --certificatesresolvers.le.acme.email=<your-email@goes-here.com>
      - --certificatesresolvers.le.acme.storage=/acme.json
      - --certificatesresolvers.le.acme.tlschallenge=true
    ports:
      - 80:80
      - 443:443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./acme.json:/acme.json
```

## With Let's Encrypt DNS validation
Below is a Docker Compose example using Let's Encrypt DNS validation. To use this method, your domain must be hosted by a supported DNS provider. You can find the full list of supported providers [here.](https://docs.traefik.io/https/acme/#providers)
In this example, we’re using DigitalOcean as the DNS provider. According to the linked list, DigitalOcean requires a `DO_AUTH_TOKEN` environment variable, which must contain a valid API token or key.
```yaml{20,21,24}
networks:
  default:
    name: traefik-proxy

services:
  traefik:
    image: traefik:v3
    container_name: traefik
    restart: unless-stopped
    command:
      - --api=true
      - --api.dashboard=false
      - --log.level=info
      - --entrypoints.web.address=:80
      - --entrypoints.web.http.redirections.entryPoint.to=websecure
      - --entrypoints.websecure.address=:443
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --certificatesresolvers.le.acme.dnschallenge=true
      - --certificatesresolvers.le.acme.dnschallenge.provider=digitalocean
      - --certificatesresolvers.le.acme.email=<your-email@goes-here.com>
      - --certificatesresolvers.le.acme.storage=/acme.json
    environment:
      - DO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxx
    ports:
      - 80:80
      - 443:443
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./acme.json:/acme.json
```

## Label your containers
Add labels to your containers to enable Traefik to route traffic to them. Additionally, ensure they are part of the `traefik-proxy` network. The `hello-world` part of the label can be customized to match your specific application or requirements.

```yaml
labels:
  - traefik.enable=true
  - traefik.http.services.hello-world.loadbalancer.server.port=3000  # Container port
  - traefik.http.routers.hello-world.rule=Host(`hello.example.com`)  # URL
  - traefik.http.routers.hello-world.tls.certresolver=le             # Cert resolver declared as traefik flag
  - traefik.http.routers.hello-world.entrypoints=websecure           # Incoming entrypoint
```

Below is a simple "Hello World" example. Here, port `3000` is exposed, not because it serves a specific function, but because it clearly shows which ports the container is listening on.

```yaml
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
      - traefik.http.services.hello-world.loadbalancer.server.port=3000
      - traefik.http.routers.hello-world.rule=Host(`hello.example.com`)
      - traefik.http.routers.hello-world.tls.certresolver=le
      - traefik.http.routers.hello-world.entrypoints=websecure
```
---
