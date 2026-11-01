#!/usr/bin/env bash
#
# Tests the whole setup in a clean ubuntu:26.04 container: shellcheck, then bootstrap.sh
# as a normal user with passwordless sudo, then git/setup.sh and check.sh.
#
# Usage: bash test/container.sh [options]
#   --lint-only   run only shellcheck + bash -n
#   --ros         also install ROS 2 Lyrical (downloads 1-2 GB, slow)
#   --keep        leave the container running afterwards (docker exec -it dotfiles-test bash)
#   -h, --help    show this help
#
# Needs Docker and network. Uses the working tree (uncommitted changes included),
# copied into the container read-only, so nothing on this machine changes.
# Container limits: no systemd, no desktop and no GPU, so --no-docker is used and
# Docker, GNOME and font rendering are not tested. Real downloads happen (VSCode,
# Discord, Brave...), so a full run takes several minutes.

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
source "$REPO/lib/common.sh"

LINT_ONLY=0; ROS=0; KEEP=0
for arg in "$@"; do
  case "$arg" in
    --lint-only) LINT_ONLY=1 ;;
    --ros) ROS=1 ;;
    --keep) KEEP=1 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done
command -v docker >/dev/null || die "Docker is required"
docker info >/dev/null 2>&1 || die "Cannot talk to the Docker daemon (are you in the docker group?)"

IMAGE=ubuntu:26.04
NAME=dotfiles-test
TOTAL=2; [[ $LINT_ONLY -eq 1 ]] || TOTAL=3
header "Container test" "$IMAGE"

step "Lint (bash -n + shellcheck)"
docker run --rm -v "$REPO:/src:ro" "$IMAGE" bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null && apt-get install -y -qq shellcheck >/dev/null
  cd /src
  files=$(git ls-files "*.sh" 2>/dev/null || true)
  [ -n "$files" ] || files=$(find . -name "*.sh" -not -path "./logs/*")
  for f in $files; do bash -n "$f" || { echo "syntax error: $f"; exit 1; }; done
  # -x follows `source`; SC1091 (not following) is noise for the lib path.
  shellcheck -x -S warning $files
' && ok "bash -n and shellcheck clean" || die "Lint failed (see above)"
[[ $LINT_ONLY -eq 0 ]] || { done_msg "Lint passed."; exit 0; }

step "Prepare the container"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -v "$REPO:/src:ro" "$IMAGE" sleep infinity >/dev/null
docker exec "$NAME" bash -c '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null && apt-get install -y -qq sudo >/dev/null
  echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu
  chmod 440 /etc/sudoers.d/ubuntu
' && ok "Container $NAME ready (user: ubuntu, passwordless sudo)"

step "bootstrap.sh, then git/setup.sh and check.sh"
BOOT_ARGS=(--no-docker --no-git); [[ $ROS -eq 1 ]] || BOOT_ARGS+=(--no-ros)
CHECK_ARGS=(--offline --no-docker); [[ $ROS -eq 1 ]] || CHECK_ARGS+=(--no-ros)
rc=0
docker exec -u ubuntu -e HOME=/home/ubuntu -w /home/ubuntu "$NAME" bash -c '
  set -uo pipefail
  mkdir -p dotfiles && tar -C /src --exclude=./logs -cf - . | tar -C dotfiles -xf -
  cd dotfiles
  echo "### bootstrap.sh '"${BOOT_ARGS[*]}"'"
  bash bootstrap.sh '"${BOOT_ARGS[*]}"'; boot=$?
  echo "### git/setup.sh (non-interactive)"
  bash git/setup.sh --name "Test User" --email test@example.com --no-gh </dev/null; git=$?
  echo "### re-running apps (must be a no-op)"
  bash apps/install.sh; again=$?
  echo "### check.sh '"${CHECK_ARGS[*]}"'"
  export PATH="$HOME/.local/bin:$PATH"
  bash check.sh '"${CHECK_ARGS[*]}"'; chk=$?
  echo "### exit codes: bootstrap=$boot git=$git rerun=$again check=$chk"
  [ $((boot+git+again+chk)) -eq 0 ]
' || rc=$?

if [[ $KEEP -eq 1 ]]; then info "Container kept: docker exec -it -u ubuntu $NAME bash"
else docker rm -f "$NAME" >/dev/null 2>&1 || true; fi
[[ $rc -eq 0 ]] || die "Container test FAILED (exit $rc)"
done_msg "Container test passed."
