---
title: Grafana Auth Proxy Authentication
date: 2020-11-08 16:34:48
author: Patrick Kerwood
excerpt: Instead of managing a local user database in Grafana, you can let a reverse proxy handle the authentication and Grafana will create a user based on that login. In this example  I use Pomerium as the authenticating proxy.
type: post
blog: true
tags: [grafana, pomerium, oidc]
---
{{ $frontmatter.excerpt }}

With Grafana you have the option to let a reverse proxy handle authentication to the application. To be fair, Grafana actually supports multiple [OAuth Providers](https://grafana.com/docs/grafana/latest/auth/) like Google, Azure, etc. but if you for some reason just want to use Pomerium, look no further.

As usual I have include my default [Traefik configuration.](https://linuxblog.xyz/posts/traefik-2-docker-compose/)

I'm not going to go into setting up Pomerium, you can see [this post](https://linuxblog.xyz/posts/pomerium-docker-compose/) for details on that. There are though a few extra things that we need to configure in Pomerium.

We need to ad `pass_identity_headers: true` to the Pomerium policy.

```yaml{3}
- from: https://grafana.example.org
  to: http://grafana:3000
  pass_identity_headers: true
  allowed_users:
    - use@example.org
```

The second is is adding the `JWT_CLAIMS_HEADERS: email` environment variable to the Pomerium service.

If you have read my posts before you know that I like to configure my applications by environment variables, if possible, for easy portability. If you look at the `grafana` service in the compose file, you will see the environment variables that makes Pomerium authentication possible. The current role given to an authenticated users is `Admin`. Other possible roles are `Editor` or `Viewer`.

Remember to change the `GF_AUTH_SIGNOUT_REDIRECT_URL` variable to fit your URL.

Populate the `COOKIE_SECRET` variable with the output of `head -c32 /dev/urandom | base64`.

```yaml{25,33,45,52}
version: "3.8"

networks:
  traefik-proxy:
    external: true
  grafana:

volumes:
  grafana-data:

services:
  pomerium:
    image: pomerium/pomerium:latest
    container_name: pomerium
    restart: unless-stopped
    environment:
      INSECURE_SERVER: "true"
      ADDRESS: :80
      COOKIE_SECRET: cookie-secret-here
      IDP_PROVIDER: google
      IDP_PROVIDER_URL: https://accounts.google.com
      IDP_CLIENT_ID: yyyy.apps.googleusercontent.com
      IDP_CLIENT_SECRET: xxxxxxxxxxxxxxxxxxx
      AUTHENTICATE_SERVICE_URL: https://grafana.example.org
      JWT_CLAIMS_HEADERS: email
      POLICY: LSBmcm9tOiBodHRwczovL2dyYWZhbmEuZXhhbXBsZS5vcmcKICB0bzogaHR0cDovL2dyYWZhbmE6MzAwMAogIHBhc3NfaWRlbnRpdHlfaGVhZGVyczogdHJ1ZQogIGFsbG93ZWRfdXNlcnM6CiAgICAtIHVzZUBleGFtcGxlLm9yZwo=
    networks:
      - traefik-proxy
      - grafana
    labels:
      - traefik.enable=true
      - traefik.http.services.pomerium.loadbalancer.server.port=80
      - traefik.http.routers.pomerium.rule=Host(`grafana.example.org`)
      - traefik.http.routers.pomerium.tls.certresolver=le
      - traefik.http.routers.pomerium.entrypoints=websecure
      - traefik.docker.network=traefik-proxy

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    environment:
      GF_USERS_ALLOW_SIGN_UP: "false"
      GF_USERS_AUTO_ASSIGN_ORG: "true"
      GF_USERS_AUTO_ASSIGN_ORG_ROLE: Admin
      GF_AUTH_PROXY_ENABLED: "true"
      GF_AUTH_PROXY_HEADER_NAME: X-Pomerium-Claim-Email
      GF_AUTH_PROXY_HEADER_PROPERTY: username
      GF_AUTH_PROXY_AUTO_SIGN_UP: "true"
      GF_AUTH_PROXY_SYNC_TTL: 60
      GF_AUTH_PROXY_ENABLE_LOGIN_TOKEN: "false"
      GF_AUTH_SIGNOUT_REDIRECT_URL: https://grafana.example.org/.pomerium/sign_out
    volumes:
      - grafana-data:/var/lib/grafana
    expose:
      - 3000
    networks:
      - grafana
```

If you prefer a Grafana configuration file, here's the configuration in `ini`format. Just save it as `grafana.ini` and mount it to `/etc/grafana/grafana.ini`.
```ini{4,15}
[users]
allow_sign_up = false
auto_assign_org = true
auto_assign_org_role = Editor

[auth.proxy]
enabled = true
header_name = X-Pomerium-Claim-Email
header_property = username
auto_sign_up = true
sync_ttl = 60
enable_login_token = false

[auth]
signout_redirect_url = https://grafana.example.org/.pomerium/sign_out
```


## Reference
- [https://grafana.com/docs/grafana/latest/auth/auth-proxy/](https://grafana.com/docs/grafana/latest/auth/auth-proxy/)
- [https://grafana.com/docs/grafana/latest/permissions/organization_roles/](https://grafana.com/docs/grafana/latest/permissions/organization_roles/)
---