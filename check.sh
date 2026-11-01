#!/usr/bin/env bash
#
# Verifies that this machine matches what the repo sets up. Changes nothing.
#
# Usage: bash check.sh [options]
#   --no-docker   don't check Docker
#   --no-ros      don't check ROS 2
#   --no-git      don't check Git identity / SSH / GitHub
#   --offline     skip the checks that need the network (GitHub SSH)
#   -h, --help    show this help
#
# Exit code is 0 when nothing failed, 1 otherwise. Warnings (!) don't fail the run.
# Failed checks (✘) say what to run to fix them.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

DOCKER=1; ROS=1; GIT=1; OFFLINE=0
for arg in "$@"; do
  case "$arg" in
    --no-docker) DOCKER=0 ;;
    --no-ros) ROS=0 ;;
    --no-git) GIT=0 ;;
    --offline) OFFLINE=1 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done
header "Check" "$(hostname) - $(. /etc/os-release && echo "$PRETTY_NAME")"
export LC_ALL=C

PASS=0; FAIL=0; WARN=0
pass()  { PASS=$((PASS+1)); ok "$*"; }
fail()  { FAIL=$((FAIL+1)); printf '  %s✘%s %s\n' "$RED" "$RST" "$*"; }
soft()  { WARN=$((WARN+1)); warn "$*"; }
# need_cmd <command> <fix>
need_cmd() { if command -v "$1" >/dev/null 2>&1; then pass "$1"; else fail "$1 not found. Fix: $2"; fi; }
need_pkg() { if pkg_installed "$1"; then pass "$1 ($(dpkg-query -W -f='${Version}' "$1"))"; else fail "package $1 not installed. Fix: $2"; fi; }

SUMMARY=(); CUR=""; CP=0; CF=0; CW=0
close_section() { [[ -z "$CUR" ]] || SUMMARY+=("$CUR|$((PASS-CP))|$((WARN-CW))|$((FAIL-CF))"); }
open_section() { close_section; CUR="$1"; CP=$PASS; CF=$FAIL; CW=$WARN; section "$1"; }

open_section "Base tools"
FIX_DEV="bash apps/install.sh devtools unzip"
for c in git curl gpg python3 cmake tmux htop rg fdfind jq gh pipx zip unzip; do need_cmd "$c" "$FIX_DEV"; done
gcc_out="$(command -v gcc || true)"; [[ -n "$gcc_out" ]] && pass "gcc (build-essential)" || fail "gcc not found. Fix: $FIX_DEV"
if command -v 7z >/dev/null || command -v 7zz >/dev/null; then pass "7zip"; else fail "7zip not found. Fix: bash apps/install.sh 7zip"; fi

open_section "Apps"
need_cmd code "bash apps/install.sh vscode"
need_pkg brave-browser "bash apps/install.sh brave"
need_pkg spotify-client "bash apps/install.sh spotify"
need_pkg discord "bash apps/install.sh discord"
need_pkg claude-desktop "bash apps/install.sh claude-desktop"
if [[ -x "$HOME/.local/bin/herdr" ]] || command -v herdr >/dev/null; then
  pass "herdr ($("${HOME}/.local/bin/herdr" --version 2>/dev/null || herdr --version 2>/dev/null))"
else fail "herdr not found. Fix: bash apps/install.sh herdr"; fi
for t in claude codex pi; do
  if command -v "$t" >/dev/null || [[ -x "$HOME/.local/bin/$t" ]]; then pass "$t ($("$HOME/.local/bin/$t" --version 2>/dev/null | head -1 || true))"
  else fail "$t not found. Fix: bash apps/install.sh $t"; fi
done
case ":$PATH:" in *":$HOME/.local/bin:"*) pass "~/.local/bin is on PATH" ;; *) soft "~/.local/bin is not on PATH in this shell (open a new terminal)" ;; esac

if [[ $DOCKER -eq 1 ]]; then
  open_section "Docker"
  FIX="bash docker/install.sh"
  need_pkg docker-ce "$FIX"
  need_pkg docker-compose-plugin "$FIX"
  need_pkg docker-buildx-plugin "$FIX"
  svc="$(systemctl is-active docker 2>/dev/null || true)"
  [[ "$svc" == active ]] && pass "docker.service is active" || fail "docker.service is '$svc'. Fix: sudo systemctl enable --now docker"
  grp="$(getent group docker || true)"
  if grep -qE "[:,]$USER(,|$)" <<<"$grp"; then
    pass "$USER is in the docker group"
    sess="$(id -nG)"
    if grep -qw docker <<<"$sess"; then
      if docker info >/dev/null 2>&1; then pass "docker daemon reachable without sudo"; else fail "docker info failed even though you're in the group"; fi
    else
      soft "This session predates the group change. Log out and back in to use docker without sudo"
    fi
  else
    fail "$USER is not in the docker group. Fix: bash docker/install.sh"
  fi
fi

open_section "Terminal"
if command -v alacritty >/dev/null; then
  pass "alacritty ($(alacritty --version 2>/dev/null))"
  conf="$HOME/.config/alacritty/alacritty.toml"
  theme="$HOME/.config/alacritty/themes/thiago-monokai-pro.toml"
  if [[ -f "$conf" ]] && cmp -s "$conf" "$HERE/alacritty/alacritty.toml"; then pass "alacritty.toml matches the repo"; else fail "alacritty.toml missing or differs from the repo. Fix: bash alacritty/install.sh"; fi
  if [[ -f "$theme" ]] && cmp -s "$theme" "$HERE/alacritty/themes/thiago-monokai-pro.toml"; then pass "Alacritty theme matches the repo"; else fail "Alacritty theme missing or differs. Fix: bash alacritty/install.sh"; fi
  if [[ -f "$conf" ]]; then
    if alacritty migrate --dry-run -c "$conf" >/dev/null 2>&1; then pass "alacritty config parses"; else fail "alacritty config does not parse"; fi
  fi
else
  fail "alacritty not found. Fix: bash alacritty/install.sh"
fi
fonts="$(fc-list : family 2>/dev/null || true)"
grep -qF "JetBrainsMono NF" <<<"$fonts" && pass "JetBrainsMono NF font" || fail "JetBrainsMono NF font missing. Fix: bash fonts/install-jetbrains-mono-nf.sh"

open_section "VSCode"
if command -v code >/dev/null; then
  exts="$(code --list-extensions 2>/dev/null || true)"
  grep -qx "thiago.thiago-monokai-pro" <<<"$exts" && pass "theme extension installed" || fail "theme extension missing. Fix: bash vscode/install.sh"
  user_settings="$HOME/.config/Code/User/settings.json"
  diff_out="$(python3 -I - "$HERE/vscode/settings.json" "$user_settings" <<'PY' 2>&1
import json, re, sys
managed = json.load(open(sys.argv[1]))
try:
    # VSCode accepts trailing commas; plain json does not
    user = json.loads(re.sub(r',(\s*[}\]])', r'\1', open(sys.argv[2]).read()))
except Exception as e:
    print(f"cannot read {sys.argv[2]}: {e}"); sys.exit(1)
bad = [k for k, v in managed.items() if user.get(k) != v]
if bad:
    print("differ: " + ", ".join(bad)); sys.exit(1)
PY
  )" && pass "settings.json has the managed keys" || fail "VSCode settings: $diff_out. Fix: bash vscode/install.sh"
else
  fail "VSCode missing, can't check theme and settings. Fix: bash apps/install.sh vscode"
fi

if [[ $GIT -eq 1 ]]; then
  open_section "Git and GitHub"
  fix="bash git/setup.sh"
  n="$(git config --global user.name 2>/dev/null || true)"; e="$(git config --global user.email 2>/dev/null || true)"
  [[ -n "$n" ]] && pass "git user.name = $n" || fail "git user.name not set. Fix: $fix"
  [[ -n "$e" ]] && pass "git user.email = $e" || fail "git user.email not set. Fix: $fix"
  keys="$(ls "$HOME"/.ssh/id_*.pub 2>/dev/null || true)"
  [[ -n "$keys" ]] && pass "SSH public key present" || fail "no ~/.ssh/id_*.pub. Fix: $fix"
  grep -qE '^Host[[:space:]]+github\.com' "$HOME/.ssh/config" 2>/dev/null && pass "~/.ssh/config has Host github.com" || soft "no 'Host github.com' in ~/.ssh/config (run $fix)"
  if command -v gh >/dev/null; then
    if gh auth status >/dev/null 2>&1; then pass "gh is logged in"; else soft "gh is not logged in (run $fix or 'gh auth login')"; fi
  fi
  if [[ $OFFLINE -eq 1 ]]; then
    info "Skipped GitHub SSH test (--offline)"
  else
    # ssh -T exits 1 on success ("Hi user! You've successfully authenticated"), so read the text.
    ssh_out="$(timeout 15 ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1 || true)"
    if grep -q 'successfully authenticated' <<<"$ssh_out"; then pass "GitHub accepts your SSH key"
    else soft "GitHub SSH test did not authenticate (key not uploaded yet, passphrase not in agent, or offline)"; fi
  fi
fi

if [[ $ROS -eq 1 ]]; then
  open_section "ROS 2 Lyrical"
  if pkg_installed ros-lyrical-desktop || pkg_installed ros-lyrical-ros-base; then pass "ROS 2 Lyrical package installed"; else fail "ROS 2 Lyrical not installed. Fix: bash ros2-lyrical/install.sh"; fi
  [[ -f /opt/ros/lyrical/setup.bash ]] && pass "/opt/ros/lyrical/setup.bash exists" || fail "/opt/ros/lyrical/setup.bash missing"
  if [[ -f /opt/ros/lyrical/setup.bash ]]; then
    ver="$(bash -c 'source /opt/ros/lyrical/setup.bash && ros2 --help >/dev/null 2>&1 && echo ok' 2>/dev/null || true)"
    [[ "$ver" == ok ]] && pass "ros2 CLI runs after sourcing setup.bash" || fail "ros2 CLI does not run after sourcing setup.bash"
  fi
fi

close_section
printf '\n%sSummary%s\n' "$B" "$RST"
for row in "${SUMMARY[@]}"; do
  IFS='|' read -r name p w f <<<"$row"
  if [[ $f -gt 0 ]]; then icon="$RED✘$RST"; elif [[ $w -gt 0 ]]; then icon="$YEL!$RST"; else icon="$GRN✔$RST"; fi
  printf '  %s %-18s %s%d ok%s' "$icon" "$name" "$GRN" "$p" "$RST"
  [[ $w -eq 0 ]] || printf '  %s%d warn%s' "$YEL" "$w" "$RST"
  [[ $f -eq 0 ]] || printf '  %s%d failed%s' "$RED" "$f" "$RST"
  printf '\n'
done
if [[ $FAIL -eq 0 ]]; then
  printf '\n%s%sAll good:%s %d checks passed, %d warnings\n' "$GRN" "$B" "$RST" "$PASS" "$WARN"
else
  printf '\n%s%s%d failed:%s %d passed, %d warnings. Each ✘ above says how to fix it\n' "$RED" "$B" "$FAIL" "$RST" "$PASS" "$WARN"
fi
[[ $FAIL -eq 0 ]]
