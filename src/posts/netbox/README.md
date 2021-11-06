---
title: Setting up Netbox with Pomerium
date: 2021-10-29 16:52:56
author: Patrick Kerwood
excerpt: This post is a how-to on setting up Netbox with Docker Compose. In this example I will put Pomerium in front of the WebUI to be able to use Azure an Identity Provider and utilize Netbox's remote auth feature to auto create users that Pomerium grants access to.
type: post
blog: true
tags: [docker-compose, pomerium]
meta:
  - name: description
    content: Setting up Netbox with Pomerium and Azure as IDP.
---

{{ $frontmatter.excerpt }}

Netbox does not support OIDC login out of the box. I believe it is possible to fiddle around with Django to enable social login, but nothing as easy as using Pomerium. Netbox comes with a remote [auth feature](https://netbox.readthedocs.io/en/stable/configuration/optional-settings/#remote_auth_enabled) where you setup Netbox to create or login a users based on a specific header in the request. Keep in mind that if anyone is able to get access to Netbox, around Pomerium, that person could create a header with a username and impersonate that user.

As usual I am using my default [Traefik setup](/posts/traefik-2-docker-compose/) for proxying and certificates.

## Azure App Registration

As mentioned, I will be using Azure as Identity Provider. I will not be going into detail on creating the necessary Azure App Registration, but it is quite straight forward and the steps are as follows.

- Create the Azure App Registration with default settings.
- Set the callback URL to `https://your-netbox-url.org/oauth2/callback` in the `Authentication` menu.
- Create a secret in the `Certificates & secrets` menu.
- Grant the `Directory.Read.All`, `Group.Read.All` and `User.Read.All` API permissions on the Microsoft Graph API, in the `API permissions` menu. Remeber to grant admin consent.

You can find more documentation on Pomerium IDPs [here.](https://www.pomerium.com/docs/identity-providers/)

## Pomerium

Like Azure App Registration, I'm not going into detail on how to setup Pomerium, but you can have a look at my [other post.](/posts/pomerium-docker-compose/)

Below is an example on a route configuration which will proxy requests from `https://netbox.example.org` to the `netbox` docker compose service. The policy will allow the user if the users email domain is `example.org`
_or_ is in the Azure AD group `62f8f72a-3e06-11ec-9bbc-0242ac130002` _or_ is the specific user `user@example.com`.

As you probably noticed the group name is a UUID, that's because by default Azure will send the UUID on all the groups instead of the names. It is possible to change that by adding a groups claim. Have a look at [this post](/posts/pinniped-kubernetes-single-sign-on/#identity-provider-details) if you want to do that.

One last thing, `pass_identity_headers: true` needs to be there to send the Pomerium ID headers to Netbox with the username.

Find more documentation on Pomerium Routes [here.](https://www.pomerium.io/reference/#routes)

```yml{1,7-12}
- from: https://netbox.example.org
  to: http://netbox:8080
  pass_identity_headers: true
  policy:
    - allow:
        or:
          - domain:
              is: example.org
          - groups:
              has: '62f8f72a-3e06-11ec-9bbc-0242ac130002'
          - email:
              is: user@example.com
```

Save your route configuration to a file, `base64` encode it and add it to the `ROUTES` property in the docker compose file.

```sh
base64 -w 0 routes.yml
```

## Docker Compose

### Pomerium Settings

- Change the cookie secret with the output of this command, `head -c32 /dev/urandom | base64`.
- Set `IDP_PROVIDER_URL`, `IDP_CLIENT_ID` and `IDP_CLIENT_SECRET` with information from the Azure App Registration.
- Set the `AUTHENTICATE_SERVICE_URL` to your netbox URL.
- Set the Traefik router rule `` Host(`netbox.example.org`) `` to your netbox URL.

### Netbox Settings

In the Netbox service I use the `REMOTE_*` environment variables to enable remote authentication. To give users default permissions
you will have to set `REMOTE_AUTH_DEFAULT_GROUPS`, create the group manually after login and assign permissions to it.

- Set the `REMOTE_AUTH_DEFAULT_GROUPS` if you want to use another name than `Default`.
- Set the `SECRET_KEY` to a random string.
- Set the `SUPERUSER_API_TOKEN` to a long and random hex string (no more than 40 characters). You can use `openssl rand -hex 20`.
- Set the `SUPERUSER_PASSWORD` to set the default admin password.

Optionally you can change all the database passwords to something different.

```yml{21,23-26,35,47,56,58,60}
version: '3.9'

networks:
  netbox:
  traefik-proxy:
    external: true

volumes:
  netbox-media-files:
  netbox-postgres-data:
  netbox-redis-data:

services:
  pomerium:
    image: pomerium/pomerium:latest
    container_name: pomerium
    restart: unless-stopped
    environment:
      INSECURE_SERVER: 'true'
      ADDRESS: :80
      COOKIE_SECRET: hga0ITGAa+eZWJqM7ZtPdPes+qEK9lT5Jtkj7I9u8+o=
      IDP_PROVIDER: azure
      IDP_PROVIDER_URL: https://login.microsoftonline.com/<azure-tenant-uuid-here>/v2.0
      IDP_CLIENT_ID: <azure-client-id-here>
      IDP_CLIENT_SECRET: <azure-secret-id-here>
      AUTHENTICATE_SERVICE_URL: https://netbox.example.org
      JWT_CLAIMS_HEADERS: email
      ROUTES: LSBmcm9tOiBodHRwczovL25ldGJveC5saW51eG5ldC5pbwog.......
    networks:
      - traefik-proxy
      - netbox
    labels:
      - traefik.enable=true
      - traefik.http.services.netbox.loadbalancer.server.port=80
      - traefik.http.routers.netbox.rule=Host(`netbox.example.org`)
      - traefik.http.routers.netbox.tls.certresolver=le
      - traefik.http.routers.netbox.entrypoints=websecure
      - traefik.docker.network=traefik-proxy

  netbox: &netbox
    image: netboxcommunity/netbox:v3.0-1.4.1
    container_name: netbox
    environment:
      - REMOTE_AUTH_ENABLED=True
      - REMOTE_AUTH_AUTO_CREATE_USER=True
      - REMOTE_AUTH_HEADER=HTTP_X_POMERIUM_CLAIM_EMAIL
      - REMOTE_AUTH_DEFAULT_GROUPS=Default
      - DB_HOST=postgres
      - DB_NAME=netbox
      - DB_PASSWORD=J5brHrAXFLQSif0K
      - DB_USER=netbox
      - REDIS_CACHE_HOST=redis-cache
      - REDIS_CACHE_PASSWORD=t4Ph722qJ5QHeQ1qfu36
      - REDIS_HOST=redis
      - REDIS_PASSWORD=H733Kdjndks81
      - SECRET_KEY=r8OwDznjdciP9ghmRfdu1Ysxm0AiPeDCQhKE+N_rClfWNj
      - SKIP_SUPERUSER=false
      - SUPERUSER_API_TOKEN=c577fb74c376d710a79cb657ddc3c75bb7c54c8b
      - SUPERUSER_NAME=admin
      - SUPERUSER_PASSWORD=admin
    user: 'unit:root'
    volumes:
      - netbox-media-files:/opt/netbox/netbox/media:z
    networks:
      - netbox
    depends_on:
      - postgres
      - redis
      - redis-cache

  netbox-worker:
    <<: *netbox
    container_name: netbox-worker
    command: /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py rqworker
    networks:
      - netbox

  netbox-housekeeping:
    <<: *netbox
    container_name: netbox-housekeeping
    command: /opt/netbox/housekeeping.sh
    networks:
      - netbox

  postgres:
    container_name: netbox-postgres
    image: postgres:13-alpine
    environment:
      - POSTGRES_DB=netbox
      - POSTGRES_PASSWORD=J5brHrAXFLQSif0K
      - POSTGRES_USER=netbox
    volumes:
      - netbox-postgres-data:/var/lib/postgresql/data
    networks:
      - netbox

  redis:
    image: redis:6-alpine
    container_name: netbox-redis
    command: sh -c "redis-server --appendonly yes --requirepass $$REDIS_PASSWORD"
    environment:
      - REDIS_PASSWORD=H733Kdjndks81
    volumes:
      - netbox-redis-data:/data
    networks:
      - netbox

  redis-cache:
    container_name: netbox-redis-cache
    image: redis:6-alpine
    command: sh -c "redis-server --requirepass $$REDIS_PASSWORD"
    environment:
      - REDIS_PASSWORD=t4Ph722qJ5QHeQ1qfu36
    networks:
      - netbox
```

After deploying the application stack with docker compose, there's just a few extra steps you need to do.

You should be able to login with your IDP and Netbox will create your user with your email as the username, but you will not have any permissoins.

The quick reader is probably wondering why I didn't just set `REMOTE_AUTH_SUPERUSERS`, the answer is that not all `REMOTE_*` variables are supported in this Docker build.

After you've logged in successfully with your IDP for the first time, do the following steps.

- Disable remote auth by commenting out the `JWT_CLAIMS_HEADERS` environment variable in the `pomerium` service and run `docker-compose up -d` to re-create it. This will stop Pomerium in sending the needed header.
- Go to the Netbox WebUI again, you will probably stil be logged in with your user, just logout and login again with the default admin user.
- Go to the Admin settings and give your IDP user superuser permissions by ticking the `Superuser status` and `Staff status` boxes in the user settings.
- While you are there, you might as well create that `Default` group you've specified with the `REMOTE_AUTH_DEFAULT_GROUPS` variable.
- Save and logout.
- Enable the `JWT_CLAIMS_HEADERS` variable again and re-create `pomerium`.

## References

- [Netbox Docs](https://netbox.readthedocs.io)
- [Netbox Community Github](https://github.com/netbox-community/netbox)
- [Netbox Community Docker Github](https://github.com/netbox-community/netbox-docker)

---
