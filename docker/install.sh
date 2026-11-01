#!/usr/bin/env bash
#
# Installs Docker Engine + Compose + Buildx from Docker's official apt repo.
#
# Usage: bash docker/install.sh [--no-group]
#   --no-group   don't add your user to the 'docker' group (then docker needs sudo)
#   -h, --help   show this help
#
# Needs sudo. Safe to re-run: skips what's already in place. After the first run,
# log out and back in (or run `newgrp docker`) so the group change takes effect.

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

GROUP=1
for arg in "$@"; do
  case "$arg" in
    --no-group) GROUP=0 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done
TOTAL=3
header "Docker" "Engine, Compose and Buildx"
require_not_root
command -v apt-get >/dev/null || die "This installer needs apt"
PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

step "Docker packages"
missing=()
for p in "${PKGS[@]}"; do pkg_installed "$p" || missing+=("$p"); done
if [[ ${#missing[@]} -eq 0 ]]; then
  ok "Already installed: $(docker --version)"
else
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  apt_install ca-certificates curl
  fetch_key https://download.docker.com/linux/ubuntu/gpg /etc/apt/keyrings/docker.asc
  printf 'Types: deb\nURIs: https://download.docker.com/linux/ubuntu\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
    "$codename" "$(dpkg --print-architecture)" | sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null
  apt_refresh
  apt_install "${PKGS[@]}"
  ok "Installed: $(docker --version)"
fi

step "Service"
if [[ "$(systemctl is-active docker 2>/dev/null || true)" == active ]]; then
  ok "docker.service is running"
else
  sudo systemctl enable --now docker
  ok "docker.service enabled and started"
fi

step "docker group"
if [[ $GROUP -eq 0 ]]; then
  info "Skipped (--no-group)"
elif id -nG "$USER" | tr ' ' '\n' | grep -qx docker || getent group docker | grep -qE "[:,]$USER(,|$)"; then
  ok "$USER is in the docker group"
else
  sudo usermod -aG docker "$USER"
  warn "Added $USER to the docker group. Log out and back in (or run 'newgrp docker') before using docker without sudo"
fi

done_msg Done.
