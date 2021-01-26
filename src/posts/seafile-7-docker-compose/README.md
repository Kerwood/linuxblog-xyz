---
title: Deploying Seafile with Docker
date: 2020-05-15 08:51:42
author: Patrick Kerwood
excerpt: A Docker Compose configuration example on deploying Seafile. In this example I'll deploy it in a Traefik proxy network and with the appropriate Traefik labels.
type: post
blog: true
tags: [seafile, docker-compose, config]
---
A Docker Compose configuration example on deploying Seafile. In this example I'll deploy it in a Traefik proxy network and with the appropriate Traefik labels.

There are 3 services that make up Seafile. A MariaDB, Memcached key-value store and Seafile itsself. If you look closely, you can see that there are two networks, `traefik-proxy` which should exist and `seafile` which Docker Compose will create. All 3 services are added to the `seafile` network and the `seafile` service is also added to the already existing `traefik-proxy` network, for enabling Traefik to proxy traffic to the service.

## Docker Compose
You need to change the environment variables highlighted in the code below. Notice that `SEAFILE_SERVER_LETSENCRYPT` is set to `false`. That's because Traefik handles my LE certificates, not Seafile.

Change Traefik labels on the `seafile` service to fit your needs. Remember, if your Traefik network is different to `traefik-proxy`, change the `traefik.docker.network` label aswell.

```yaml{8,37-40,42,45-49}
version: '3.7'
services:
  db:
    image: mariadb:10.1
    container_name: seafile-mysql
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=<db-password>  # Required, set the root's password of MySQL service.
      - MYSQL_LOG_CONSOLE=true
    volumes:
      - seafile-db:/var/lib/mysql  # Required, specifies the path to MySQL data persistent store.
    networks:
      - seafile

  memcached:
    image: memcached:1.5.6
    container_name: seafile-memcached
    restart: unless-stopped
    entrypoint: memcached -m 256
    networks:
      - seafile

  seafile:
    image: seafileltd/seafile-mc:latest
    container_name: seafile
    restart: unless-stopped
    expose:
      - 80
      - 443
    volumes:
      - seafile-data:/shared   # Required, specifies the path to Seafile data persistent store.
    networks:
      - traefik-proxy
      - seafile
    environment:
      - DB_HOST=db
      - DB_ROOT_PASSWD=<db-password> # Required, the value shuold be root's password of MySQL service.
      - TIME_ZONE=Europe/Copenhagen  # Optional, default is UTC. Should be uncomment and set to your local time zone.
      - SEAFILE_ADMIN_EMAIL=your@email.com # Specifies Seafile admin user, default is 'me@example.com'.
      - SEAFILE_ADMIN_PASSWORD=asecret     # Specifies Seafile admin password, default is 'asecret'.
      - SEAFILE_SERVER_LETSENCRYPT=false   # Whether to use https or not.
      - SEAFILE_SERVER_HOSTNAME=cloud.example.org # Specifies your domainname
    labels:
      - traefik.enable=true
      - traefik.http.services.seafile.loadbalancer.server.port=80
      - traefik.http.routers.seafile.rule=Host(`cloud.example.org`)
      - traefik.http.routers.seafile.tls.certresolver=le
      - traefik.http.routers.seafile.entrypoints=websecure
      - traefik.docker.network=traefik-proxy

networks:
  traefik-proxy:
    external: true
  seafile:

volumes:
  seafile-db:
  seafile-data:
```

### Source links
  - Official [Github Repo](https://github.com/haiwen/seafile-docker)
  - Official [docker-compose.yml](https://download.seafile.com/d/320e8adf90fa43ad8fee/files/?p=/docker/docker-compose.yml) file.

### Minor fix
After deploying above Docker Compose file, there is just one more thing you need to fix. Personally I would call it a bug, but according to the developer, its by design. The issue is that a couple of variable needs to be fixed for Seafile to get content.

Open a shell in the `seafile` container.
```sh
docker exec -it seafile bash
```

Open `/opt/seafile/conf/ccnet.conf` file with `vi`. (Sorry peeps, only the `vi` editor is available in the container)
```sh
vi /opt/seafile/conf/ccnet.conf
```

```
[General]
SERVICE_URL = http://cloud.example.org:8000
...
```

Change the `SERVICE_URL` variable to fit your needs. If you are using SSL, remember to change `http` to `https`. And of course if you are using port `80` or `443`, just delete the port section.
```
[General]
SERVICE_URL = https://cloud.example.org
```

The same thing goes for the `FILE_SERVER_ROOT` variable in `/opt/seafile/conf/seahub_settings.py`, if you are using SSL/HTTPS.
```
...
FILE_SERVER_ROOT = "https://cloud.example.org/seafhttp"
```

Restart all Docker Compose services and you are good to go.
```sh
docker-compose restart
```

An issue has been raised with the developer about this "design".
 [https://github.com/haiwen/seafile-docker/issues/182](https://github.com/haiwen/seafile-docker/issues/182)

---