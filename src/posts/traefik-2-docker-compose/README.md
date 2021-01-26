---
title: Traefik v2 Configuration with Let's Encrypt [TLS, DNS]
date: 2020-07-20 11:13:48
author: Patrick Kerwood
excerpt: This is a Docker Compose configuration example with Traefik v2 including Let's Encrypt TLS/DNS validation.
type: post
blog: true
tags: [traefik, docker-compose, config]
---
This is a a Docker Compose configuration example with Traefik v2 including Let's Encrypt TLS/DNS validation.

This configuration redirects `http` to `https` and requests certificates from Let's Encrypt. Just change `<your-email@goes-here.com>` to your mail address, create the `acme.json` file and change the path to the `acme.json` file.

```sh
mkdir /home/traefik
touch /home/traefik/acme.json
chmod 600 /home/traefik/acme.json
```

## With Let's Encrypt HTTP validation
```yaml{20,28}
version: "3.7"
networks:
  default:
    name: traefik-proxy

services:
  traefik:
    image: traefik:v2.3
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
      - /home/traefik/acme.json:/acme.json
```

## With Let's Encrypt DNS validation
Below is the a Docker Compose example with Let's Encrypt DNS validation. Your domain name needs to be hosted by a supported DNS provider. You can get a list of supported providers [here.](https://docs.traefik.io/https/acme/#providers)

In the example below, I'm using Digital Ocean as DNS provider and in the list linked above, I can see that I need a `DO_AUTH_TOKEN` environment variable with a valid API token/key.
```yaml{21,22,25,31}
version: "3.7"
networks:
  default:
    name: traefik-proxy

services:
  traefik:
    image: traefik:v2.3
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
      - /home/traefik/acme.json:/acme.json
```

## Label your containers
Add labels to your containers to make Traefik proxy traffic to them. Also they need to be in the `traefik-proxy` network. The `hello-world` part of the label, you change to what ever fits your needs/application. 

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.services.hello-world.loadbalancer.server.port=3000 # Container port
      - traefik.http.routers.hello-world.rule=Host(`hello.example.com`) # URL
      - traefik.http.routers.hello-world.tls.certresolver=le # Cert resolver declared as traefik flag
      - traefik.http.routers.hello-world.entrypoints=websecure # Incoming entrypoint
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
      - traefik.http.services.hello-world.loadbalancer.server.port=3000
      - traefik.http.routers.hello-world.rule=Host(`hello.example.com`)
      - traefik.http.routers.hello-world.tls.certresolver=le
      - traefik.http.routers.hello-world.entrypoints=websecure
```
---