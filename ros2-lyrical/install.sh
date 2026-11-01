#!/usr/bin/env bash
#
# Self-contained installer for ROS 2 Lyrical Luth on Ubuntu 26.04 (resolute).
#
# Usage: bash install.sh [--base] [--no-bashrc] [--help]
#   --base        install ros-lyrical-ros-base (headless) instead of desktop
#   --no-bashrc   don't touch ~/.bashrc
#
# Safe to re-run: every step checks its state first.
# Log file: logs/install-<timestamp>.log next to this script (full command output)

set -Eeuo pipefail

# ---------- config ----------
DISTRO="lyrical"
REQUIRED_CODENAME="resolute"
KEY_URL="https://raw.githubusercontent.com/ros/rosdistro/master/ros.key"
KEYRING="/usr/share/keyrings/ros-archive-keyring.gpg"
# http on purpose: packages.ros.org serves an osuosl.org TLS cert that doesn't
# match the hostname. Apt verifies packages via the GPG key instead.
REPO_URI="http://packages.ros.org/ros2/ubuntu"
SOURCES_FILE="/etc/apt/sources.list.d/ros2.sources"
PKG="ros-${DISTRO}-desktop"
EDIT_BASHRC=1

for arg in "$@"; do
  case "$arg" in
    --base) PKG="ros-${DISTRO}-ros-base" ;;
    --no-bashrc) EDIT_BASHRC=0 ;;
    -h|--help) sed -n '3,10p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

# ---------- logging ----------
LOG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"
: > "$LOG_FILE"

if [[ -t 1 ]]; then
  B=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYN=$'\e[36m'; RST=$'\e[0m'
else
  B=; DIM=; RED=; GRN=; YEL=; CYN=; RST=
fi

TOTAL=7; STEP=0; T0=$SECONDS
ts()   { date +%H:%M:%S; }
plain(){ printf '[%s] %s\n' "$(ts)" "$*" >> "$LOG_FILE"; }
step() { STEP=$((STEP+1)); printf '\n%s[%d/%d]%s %s%s%s\n' "$CYN" "$STEP" "$TOTAL" "$RST" "$B" "$*" "$RST"; plain "STEP $STEP/$TOTAL: $*"; }
info() { printf '  %s•%s %s\n' "$DIM" "$RST" "$*"; plain "$*"; }
ok()   { printf '  %s✔%s %s\n' "$GRN" "$RST" "$*"; plain "OK: $*"; }
warn() { printf '  %s!%s %s\n' "$YEL" "$RST" "$*"; plain "WARN: $*"; }
die()  { printf '\n%s✘ %s%s\n  Full log: %s\n' "$RED" "$*" "$RST" "$LOG_FILE" >&2; plain "FATAL: $*"; exit 1; }
trap 'die "Failed at line $LINENO: ${BASH_COMMAND}"' ERR

# Run a command quietly: output goes to the log; tail is shown only on failure.
run() {
  local desc="$1"; shift
  plain "RUN: $*"
  printf '  %s…%s %s' "$DIM" "$RST" "$desc"
  local t=$SECONDS
  if "$@" >> "$LOG_FILE" 2>&1; then
    printf '\r\e[K  %s✔%s %s %s(%ss)%s\n' "$GRN" "$RST" "$desc" "$DIM" "$((SECONDS-t))" "$RST"
  else
    printf '\r\e[K  %s✘%s %s\n' "$RED" "$RST" "$desc"
    echo "  ---- last log lines ----" >&2; tail -n 15 "$LOG_FILE" | sed 's/^/  | /' >&2
    die "Command failed: $*"
  fi
}

printf '%sROS 2 %s installer%s  %s(package: %s)%s\n' "$B" "${DISTRO^}" "$RST" "$DIM" "$PKG" "$RST"
info "Log: $LOG_FILE"

# ---------- 1. preflight ----------
step "Preflight checks"
[[ $EUID -ne 0 ]] || die "Run as your normal user, not root (the script calls sudo itself)."
# shellcheck disable=SC1091
. /etc/os-release
[[ "${VERSION_CODENAME:-}" == "$REQUIRED_CODENAME" ]] \
  || die "Needs Ubuntu 26.04 ($REQUIRED_CODENAME); found ${PRETTY_NAME:-unknown}."
ok "OS: $PRETTY_NAME"
[[ "$(dpkg --print-architecture)" == "amd64" || "$(dpkg --print-architecture)" == "arm64" ]] \
  || die "Unsupported architecture: $(dpkg --print-architecture)"
ok "Architecture: $(dpkg --print-architecture)"
for c in curl gpg; do command -v "$c" >/dev/null || info "$c missing, will be installed"; done
avail_gb=$(df --output=avail -BG /opt 2>/dev/null | tail -1 | tr -dc '0-9')
[[ "${avail_gb:-0}" -ge 5 ]] || die "Need >= 5 GB free on /opt (have ${avail_gb:-?} GB)."
ok "Disk space on /opt: ${avail_gb} GB free"
info "Requesting sudo (password may be asked once)"
sudo -n true 2>/dev/null || sudo -v || die "sudo is required."
# keep sudo alive for the whole run
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) >/dev/null 2>&1 &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

# ---------- 2. prerequisites ----------
step "Prerequisites"
run "apt update" sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 update
run "Installing curl, gnupg, software-properties-common" \
  sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y curl gnupg software-properties-common
run "Enabling 'universe' repository" sudo add-apt-repository -y universe

# ---------- 3. GPG key ----------
step "ROS GPG key"
tmpkey="$(mktemp)"
run "Downloading key from rosdistro" curl -fsSL --retry 3 -o "$tmpkey" "$KEY_URL"
[[ -s "$tmpkey" ]] || die "Downloaded key is empty."
# The upstream key may be ASCII-armored or already binary; accept either.
if grep -q "BEGIN PGP PUBLIC KEY BLOCK" "$tmpkey"; then
  run "Installing keyring (dearmored) to $KEYRING" bash -c "gpg --dearmor < '$tmpkey' | sudo tee '$KEYRING' >/dev/null"
else
  run "Installing keyring (binary) to $KEYRING" sudo install -m 644 "$tmpkey" "$KEYRING"
fi
run "Validating keyring" gpg --show-keys --with-colons "$KEYRING"
rm -f "$tmpkey"

# ---------- 4. apt source ----------
step "ROS apt source"
desired="Types: deb
URIs: ${REPO_URI}
Suites: ${VERSION_CODENAME}
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: ${KEYRING}"
if [[ -f "$SOURCES_FILE" ]] && [[ "$(cat "$SOURCES_FILE")" == "$desired" ]]; then
  ok "$SOURCES_FILE already up to date"
else
  [[ -f "$SOURCES_FILE" ]] && warn "Replacing existing $SOURCES_FILE (old copy saved as .bak)" \
    && sudo cp "$SOURCES_FILE" "$SOURCES_FILE.bak"
  printf '%s\n' "$desired" | sudo tee "$SOURCES_FILE" >/dev/null
  ok "Wrote $SOURCES_FILE"
fi
# A leftover ros2-apt-source package would define a second (possibly https) source.
if dpkg -s ros2-apt-source >/dev/null 2>&1; then
  warn "Package 'ros2-apt-source' is installed and may duplicate this source; consider removing it."
fi
run "apt update (with ROS repo)" sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 update
candidate="$(LC_ALL=C apt-cache policy "$PKG" | awk '/Candidate:/{print $2}')"
[[ -n "$candidate" && "$candidate" != "(none)" ]] \
  || die "$PKG has no install candidate. Is the ROS repo reachable for $VERSION_CODENAME?"
ok "$PKG candidate: $candidate"

# ---------- 5. install ----------
step "Installing $PKG and ros-dev-tools (this is the long step)"
info "Download is large (~1–2 GB); progress is in the log: tail -f $LOG_FILE"
run "apt install $PKG ros-dev-tools" sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y "$PKG" ros-dev-tools

# ---------- 6. shell setup ----------
step "Shell setup"
SETUP="/opt/ros/${DISTRO}/setup.bash"
[[ -f "$SETUP" ]] || die "$SETUP not found after install."
ok "Found $SETUP"
if [[ $EDIT_BASHRC -eq 1 ]]; then
  if grep -qF "$SETUP" "$HOME/.bashrc"; then
    ok "~/.bashrc already references $SETUP"
  else
    printf '\n# ROS 2 %s (uncomment to enable in every shell)\n# source %s\n' "${DISTRO^}" "$SETUP" >> "$HOME/.bashrc"
    ok "Added a commented-out source line to ~/.bashrc"
  fi
else
  info "Skipped ~/.bashrc (--no-bashrc)"
fi

# ---------- 7. verification ----------
step "Verification"
run "ROS_DISTRO is '$DISTRO'" bash -c "source '$SETUP' && [[ \"\$ROS_DISTRO\" == '$DISTRO' ]]"
run "ros2 CLI works" bash -c "source '$SETUP' && ros2 --help"
run "Talker/listener round trip" bash -c "
  source '$SETUP'
  out=\$(mktemp)
  timeout 15 ros2 run demo_nodes_cpp listener > \"\$out\" 2>&1 &
  lp=\$!
  sleep 2
  timeout 8 ros2 run demo_nodes_cpp talker >/dev/null 2>&1 || true
  sleep 1; kill \$lp 2>/dev/null || true
  grep -q 'I heard' \"\$out\""
ok "ROS 2 ${DISTRO^} version: $(dpkg-query -W -f='${Version}' "$PKG")"

printf '\n%s%sDone%s in %ss.\n' "$GRN" "$B" "$RST" "$((SECONDS-T0))"
printf '  Enable in this shell:  %ssource %s%s\n' "$B" "$SETUP" "$RST"
printf '  Full log:              %s\n' "$LOG_FILE"
plain "DONE in $((SECONDS-T0))s"
