zensical := "zensical/zensical:0.0.73"
image := "linuxblog-xyz"

# Run as your own user, so site/ and .cache/ aren't owned by root.
docker_run := "docker run --rm --user $(id -u):$(id -g) -v \"$PWD\":/docs:z"

# List the recipes.
default:
    @just --list

# Live-reloading preview on http://localhost:<port>.
serve port="8000":
    {{ docker_run }} -it -p {{ port }}:8000 {{ zensical }}

# Strict build into site/, the same check as the GitHub Pages deploy.
build:
    {{ docker_run }} {{ zensical }} build --clean --strict

# Build the production image (Zensical build + Caddy).
image:
    docker build -t {{ image }} .

# Serve the production image on http://localhost:<port>.
run port="8080": image
    docker run --rm -it -p {{ port }}:80 {{ image }}

# Remove build output.
clean:
    rm -rf site .cache
