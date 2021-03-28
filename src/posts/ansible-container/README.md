---
title: Ansible Container
date: 2021-02-21 15:12:14
author: Patrick Kerwood
excerpt: When working with Ansible I really don't want to soil my laptop with Python. And why would I when running tasks inside a container is such as breeze. Combining that with aliases, you can run ansible commands as if it was installed locally.
blog: true
tags: [ansible]
meta:
- name: description
  content: How to run ansible in a local container seamlessly.
---
{{ $frontmatter.excerpt }}

## Building the image

Below is a Dockerfile to build an Ansible container for executing `ansible` and `ansible-playbook`. At time of writing the Ansible version is `2.10.6`.

```
FROM alpine:3.13

ENV BUILD_PACKAGES \
  bash \
  curl \
  tar \
  openssh-client \
  sshpass \
  git \
  python3 \
  py-boto \
  py-dateutil \
  py-httplib2 \
  py3-jinja2 \
  py-paramiko \
  py-pip \
  py-yaml \
  py3-wheel \
  ca-certificates

RUN set -x && \
    echo "==> Adding build-dependencies..."  && \
    apk --update add --virtual build-dependencies \
      gcc \
      musl-dev \
      libffi-dev \
      openssl-dev \
      python3-dev && \
    \
    echo "==> Upgrading apk and system..."  && \
    apk update && apk upgrade && \
    \
    echo "==> Adding Python runtime..."  && \
    apk add --no-cache ${BUILD_PACKAGES} && \
    pip install --upgrade pip && \
    pip install python-keyczar docker-py && \
    \
    echo "==> Installing ansible..."  && \
    pip install ansible && \
    \
    echo "==> Cleaning up..."  && \
    apk del build-dependencies && \
    rm -rf /var/cache/apk/* && \
    \
    echo "==> Adding hosts for convenience..."  && \
    mkdir -p /etc/ansible /ansible && \
    echo "[local]" >> /etc/ansible/hosts && \
    echo "localhost" >> /etc/ansible/hosts

ENV ANSIBLE_GATHERING smart
ENV ANSIBLE_HOST_KEY_CHECKING false
ENV ANSIBLE_RETRY_FILES_ENABLED false
ENV ANSIBLE_ROLES_PATH /ansible/playbooks/roles
ENV ANSIBLE_SSH_PIPELINING True
ENV PYTHONPATH /ansible/lib
ENV PATH /ansible/bin:$PATH
ENV ANSIBLE_LIBRARY /ansible/library

WORKDIR /ansible/playbooks

ENTRYPOINT ["ansible-playbook"]
```

Save the content above as `Dockerfile` and build the image.

Build with Docker.
```sh
docker build -t ansible .
```

Build with Buildah
```sh
buildah bud -t ansible
```

## Creating aliases

The trick here is to create two aliases that start a container and run your ansible tasks, but without you noticing that they actually run inside a container.

Add below lines to your `.zshrc`, `.bashrc` or what ever shell you use. The aliases will mount your current directory into `/ansible/playbook`, this means that you'll have to be in the same directory as your playbooks when running your ansible commands. They also bring your SSH keys in from `~/.ssh` directory into the container to use in your tasks.

Aliases for Docker
```sh
alias ansible='docker run --rm -it -v $(pwd):/ansible/playbooks -v ~/.ssh:/root/.ssh --entrypoint=ansible ansible'
alias ansible-playbook='docker run --rm -it -v $(pwd):/ansible/playbooks -v ~/.ssh:/root/.ssh  ansible'
```

Aliases for Podman
```sh
alias ansible='podman run --rm -it -v $(pwd):/ansible/playbooks:Z -v ~/.ssh:/root/.ssh:Z --entrypoint=ansible ansible'
alias ansible-playbook='podman run --rm -it -v $(pwd):/ansible/playbooks:Z -v ~/.ssh:/root/.ssh:Z  ansible'
```

You can now run your ansible commands as if you installed it locally.

---