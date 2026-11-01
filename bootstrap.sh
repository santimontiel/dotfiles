#!/usr/bin/env bash
#
# One-shot setup for a fresh Ubuntu 26.04: prerequisites, apps, Docker, terminal,
# editor, ROS 2 and Git identity, then runs check.sh to confirm the result.
#
# Usage: bash bootstrap.sh [options]
#   --no-docker   skip Docker Engine
#   --no-ros      skip ROS 2 Lyrical (downloads 1-2 GB)
#   --no-git      skip the interactive Git/SSH/GitHub setup
#   -h, --help    show this help
#
# Needs sudo (it will ask for the password). A failing step is reported and the
# run continues with the next one. Safe to re-run: every installer skips what is
# already in place. Order matters: prerequisites -> apps (gives vscode its zip) ->
# docker -> alacritty -> vscode -> ros2 -> git (interactive, last).

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

DOCKER=1; ROS=1; GIT=1
for arg in "$@"; do
  case "$arg" in
    --no-docker) DOCKER=0 ;;
    --no-ros) ROS=0 ;;
    --no-git) GIT=0 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

require_not_root
command -v apt-get >/dev/null || die "This bootstrap needs an apt-based system"
. /etc/os-release
[[ "${VERSION_ID:-}" == 26.04 ]] || warn "Tested on Ubuntu 26.04, this is ${PRETTY_NAME:-unknown}. ROS will refuse to run elsewhere"
# `sudo -v` needs a terminal even with passwordless sudo, so try -n first.
sudo -n true 2>/dev/null || sudo -v || die "sudo is required"
# Keep the sudo ticket alive: ROS alone downloads for longer than sudo's 15 min timeout.
( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null || true' EXIT

header "Bootstrap" "${PRETTY_NAME:-Linux} - $(hostname)"
FAILED=()
STEPS=0; TOTAL_STEPS=$((4 + DOCKER + ROS + GIT))
# run <label> <command...>: run a step, remember it if it fails, keep going.
run() {
  local label="$1"; shift
  STEPS=$((STEPS+1))
  printf '\n%s━━ %d/%d  %s %s\n' "$B$CYN" "$STEPS" "$TOTAL_STEPS" "$label" "$RST"
  if "$@"; then return 0; fi
  FAILED+=("$label"); warn "$label failed; continuing"; return 1
}

# xz-utils and fontconfig are needed by fonts/install-jetbrains-mono-nf.sh.
prereqs() { TOTAL=1; step "Prerequisites"; apt_install git curl gpg ca-certificates python3 zip unzip tar xz-utils fontconfig && ok "git curl gpg python3 zip unzip tar xz-utils fontconfig"; }

# Everything below needs the prerequisites, so stop here if they fail. The rest are
# independent of each other: a failure is recorded and the next step still runs.
run "Prerequisites" prereqs || die "Prerequisites failed; nothing else can work. See $LOG_FILE"
run "Apps" bash "$HERE/apps/install.sh" || true
[[ $DOCKER -eq 0 ]] || run "Docker" bash "$HERE/docker/install.sh" || true
run "Alacritty" bash "$HERE/alacritty/install.sh" || true
run "VSCode" bash "$HERE/vscode/install.sh" || true
[[ $ROS -eq 0 ]] || run "ROS 2 Lyrical" bash "$HERE/ros2-lyrical/install.sh" || true
[[ $GIT -eq 0 ]] || run "Git and GitHub" bash "$HERE/git/setup.sh" || true

printf '\n%s━━ Verification %s\n' "$B$CYN" "$RST"
CHECK_ARGS=()
[[ $DOCKER -eq 1 ]] || CHECK_ARGS+=(--no-docker)
[[ $ROS -eq 1 ]] || CHECK_ARGS+=(--no-ros)
[[ $GIT -eq 1 ]] || CHECK_ARGS+=(--no-git)
CHECK_RC=0
bash "$HERE/check.sh" "${CHECK_ARGS[@]}" || CHECK_RC=$?

printf '\n'
info "Full installer output: $LOG_FILE"
printf '\n%sStill to do by hand%s\n' "$B" "$RST"
printf '  • Log out and back in (docker group, ~/.local/bin on PATH)\n'
printf '  • Log in once: claude, codex, pi (/login), Spotify, Discord, Claude Desktop, Brave\n'
[[ $GIT -eq 1 ]] || printf '  • Git identity and SSH key: bash git/setup.sh\n'
printf '  • Reboot if the kernel or drivers were updated\n'
if [[ ${#FAILED[@]} -eq 0 && $CHECK_RC -eq 0 ]]; then
  done_msg "Bootstrap complete: every step and check passed."
else
  [[ ${#FAILED[@]} -eq 0 ]] || printf '%s%s✘ Failed steps: %s%s\n' "$RED" "$B" "${FAILED[*]}" "$RST"
  [[ $CHECK_RC -eq 0 ]] || printf '%s%s✘ check.sh reported failures (see above)%s\n' "$RED" "$B" "$RST"
  exit 1
fi
