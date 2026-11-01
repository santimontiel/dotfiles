# Docker

Docker Engine, Buildx and Compose from Docker's official apt repo (`/etc/apt/sources.list.d/docker.sources`, key in `/etc/apt/keyrings/docker.asc`).

## Install

```bash
bash docker/install.sh              # packages + service + docker group
bash docker/install.sh --no-group   # docker will need sudo
```

Steps: install `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` (skipped if present), enable `docker.service`, add your user to the `docker` group. Needs sudo.

**Log out and back in after the first run** (or `newgrp docker`): group changes don't reach running sessions.

## Verify

```bash
docker run --rm hello-world
docker compose version
bash check.sh --offline
```

## Not covered

NVIDIA driver and `nvidia-container-toolkit` for GPU containers. Add them when a machine has a GPU.
