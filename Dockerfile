FROM zensical/zensical:0.0.73 AS build
WORKDIR /docs
COPY zensical.toml .
COPY docs ./docs
COPY overrides ./overrides
RUN zensical build --clean --strict

FROM caddy:2.11-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /docs/site /srv
