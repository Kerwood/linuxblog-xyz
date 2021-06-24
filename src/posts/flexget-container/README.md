---
title: Creating a Flexget container
date: 2021-06-24 18:53:41
author: Patrick Kerwood
excerpt: Since there isn't an official container image for Flexget, here's a quick how-to on building one your self.
type: post
blog: true
tags: [flexget]
meta:
- name: description
  content: How to create a Flexget container.
---

{{ $frontmatter.excerpt }}

Below is a `Dockerfile` that creates an image with Flexget that can be used transparently like a normal command.

```
FROM python:3.9-alpine

ARG FLEXGET_UID
  
# Create a user to run the application
RUN adduser -D -u ${FLEXGET_UID} flexget
WORKDIR /home/flexget

# Flexget config directory.
VOLUME /home/flexget/.flexget
  
# Install build dependencies and FlexGet
RUN apk update && apk add --no-cache gcc g++ linux-headers musl-dev && \
    pip3 install -U pip && pip3 install flexget
  
USER flexget
ENTRYPOINT ["/usr/local/bin/flexget"]
```

Save the file and build the image with below build command. The flexget user inside the container will get a user ID of `1000`. If you're not sure why you should change it, just leave it.

```sh
docker build --build-arg FLEXGET_UID=1000 ARG-HERE -t flexget .
```

 ## Run example

Run the Flexget container with a config folder mounted.  
 ```sh
 docker run -v /path/to/config/folder:/home/flexget/.flexget -d flexget daemon start
 ```
