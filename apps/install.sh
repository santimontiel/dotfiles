#!/usr/bin/env bash
#
# Installs everyday apps and CLI tools on an apt-based system.
#
# Usage: bash apps/install.sh [app ...]
#   (no args)   install everything below
#   apps:       devtools unzip 7zip herdr claude codex pi vscode brave spotify discord claude-desktop
#   -l, --list  list the apps
#   -h, --help  show this help
#
# Safe to re-run: an app that is already installed is skipped. Needs sudo for
# whatever is missing. Repo keys go to /usr/share/keyrings, repos to
# /etc/apt/sources.list.d. Discord has no apt repo, so its .deb is downloaded
# from discord.com and installed with apt.

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

ALL=(devtools unzip 7zip herdr claude codex pi vscode brave spotify discord claude-desktop)

# Spotify rotates its signing key now and then. If the download below 404s, take
# the new URL from https://www.spotify.com/download/linux/ and update it here.
SPOTIFY_KEY_URL="https://download.spotify.com/debian/pubkey_5384CE82BA52C83A.gpg"
CLAUDE_KEY_URL="https://downloads.claude.ai/keys/claude-code.asc"  # same key as the Claude Code apt repo
BRAVE_KEY_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg"
DISCORD_DEB_URL="https://discord.com/api/download?platform=linux&format=deb"

APPS=(); ONE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '3,14p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -l|--list) printf '%s\n' "${ALL[@]}"; exit 0 ;;
    --_one) ONE="${2:?}"; shift ;;   # internal: run one app in this process (see the loop at the bottom)
    *) [[ " ${ALL[*]} " == *" $1 "* ]] || die "Unknown app: $1 (try --list)"; APPS+=("$1") ;;
  esac
  shift
done
[[ ${#APPS[@]} -gt 0 ]] || APPS=("${ALL[@]}")
TOTAL=${#APPS[@]}
[[ -n "$ONE" ]] || header "Apps" "devtools, archivers, herdr and desktop apps"

require_not_root
command -v apt-get >/dev/null || die "This installer needs apt"
ARCH="$(dpkg --print-architecture)"
# Tools land in ~/.local/bin, which a shell only gets on PATH at login. Add it here so
# the "already installed" checks work on re-runs in the same session.
export PATH="$HOME/.local/bin:$PATH"
install_vscode() {
  if command -v code >/dev/null; then ok "Already installed: VSCode"; return; fi
  apt_install curl gpg
  fetch_key https://packages.microsoft.com/keys/microsoft.asc /usr/share/keyrings/microsoft.gpg
  printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: %s\nSigned-By: /usr/share/keyrings/microsoft.gpg\n' \
    "$ARCH" | sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null
  apt_refresh; apt_install code
  ok "Installed VSCode"
}

install_spotify() {
  if pkg_installed spotify-client; then ok "Already installed: Spotify"; return; fi
  apt_install curl gpg
  fetch_key "$SPOTIFY_KEY_URL" /usr/share/keyrings/spotify.gpg
  echo 'deb [signed-by=/usr/share/keyrings/spotify.gpg] https://repository.spotify.com stable non-free' \
    | sudo tee /etc/apt/sources.list.d/spotify.list >/dev/null
  apt_refresh; apt_install spotify-client
  ok "Installed Spotify"
}

install_discord() {
  if pkg_installed discord; then ok "Already installed: Discord $(dpkg-query -W -f='${Version}' discord)"; return; fi
  [[ "$ARCH" == amd64 ]] || die "Discord only publishes an amd64 .deb (this is $ARCH)"
  apt_install curl
  local dir; dir="$(mktemp -d)"
  info "Downloading the latest Discord .deb"
  curl -fsSL "$DISCORD_DEB_URL" -o "$dir/discord.deb" || { rm -rf "$dir"; die "Discord download failed"; }
  apt_install "$dir/discord.deb"
  rm -rf "$dir"
  ok "Installed Discord"
}

install_claude-desktop() {
  if pkg_installed claude-desktop; then ok "Already installed: Claude Desktop"; return; fi
  [[ "$ARCH" == amd64 || "$ARCH" == arm64 ]] || die "Claude Desktop only has amd64/arm64 packages (this is $ARCH)"
  apt_install curl gpg
  fetch_key "$CLAUDE_KEY_URL" /usr/share/keyrings/claude-desktop-archive-keyring.gpg
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.gpg] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
    | sudo tee /etc/apt/sources.list.d/claude-desktop.list >/dev/null
  apt_refresh; apt_install claude-desktop
  ok "Installed Claude Desktop"
}

install_brave() {
  if pkg_installed brave-browser; then ok "Already installed: Brave"; return; fi
  apt_install curl
  fetch_key "$BRAVE_KEY_URL" /usr/share/keyrings/brave-browser-archive-keyring.gpg
  printf 'Types: deb\nURIs: https://brave-browser-apt-release.s3.brave.com\nSuites: stable\nComponents: main\nArchitectures: amd64 arm64\nSigned-By: /usr/share/keyrings/brave-browser-archive-keyring.gpg\n' \
    | sudo tee /etc/apt/sources.list.d/brave-browser-release.sources >/dev/null
  apt_refresh; apt_install brave-browser
  ok "Installed Brave"
}

# Build tools and CLI utilities. Ubuntu names: fd-find gives `fdfind`, not `fd`.
DEVTOOLS=(git curl gpg python3 python3-venv pipx build-essential cmake tmux htop ripgrep fd-find jq gh)
install_devtools() {
  local missing=() p
  for p in "${DEVTOOLS[@]}"; do pkg_installed "$p" || missing+=("$p"); done
  if [[ ${#missing[@]} -eq 0 ]]; then ok "Already installed: ${DEVTOOLS[*]}"; return; fi
  apt_install "${missing[@]}"
  ok "Installed dev tools"
}

# herdr (terminal workspace manager for AI agents): static binary from GitHub releases,
# no sudo. It updates itself afterwards with `herdr update`.
install_herdr() {
  local dest="$HOME/.local/bin/herdr" asset tmp
  if [[ -x "$dest" ]] || command -v herdr >/dev/null; then ok "Already installed: $("${dest}" --version 2>/dev/null || herdr --version)"; return; fi
  case "$(uname -m)" in
    x86_64) asset=herdr-linux-x86_64 ;;
    aarch64|arm64) asset=herdr-linux-aarch64 ;;
    *) die "No herdr build for $(uname -m)" ;;
  esac
  command -v curl >/dev/null || apt_install curl
  tmp="$(mktemp)"
  curl -fsSL "https://github.com/herdrdev/herdr/releases/latest/download/$asset" -o "$tmp" || { rm -f "$tmp"; die "herdr download failed"; }
  mkdir -p "$(dirname "$dest")"
  install -m 755 "$tmp" "$dest"; rm -f "$tmp"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "$HOME/.local/bin is not on PATH in this shell; open a new terminal" ;; esac
  ok "Installed $("$dest" --version)"
}

# Claude Code CLI: Anthropic's native installer (no Node needed). Puts the binary in
# ~/.local/share/claude and a link in ~/.local/bin; it updates itself afterwards.
install_claude() {
  if command -v claude >/dev/null; then ok "Already installed: $(claude --version 2>/dev/null | head -1)"; return; fi
  command -v curl >/dev/null || apt_install curl
  local tmp; tmp="$(mktemp)"
  curl -fsSL https://claude.ai/install.sh -o "$tmp" || { rm -f "$tmp"; die "Could not download the Claude Code installer"; }
  run_logged "Running the Claude Code installer" bash "$tmp" || { rm -f "$tmp"; die "Claude Code installer failed"; }
  rm -f "$tmp"
  ok "Installed Claude Code. Run 'claude' to log in"
}

# OpenAI Codex CLI: static musl binary from GitHub releases, no sudo, no Node.
# Update later with the same command after deleting ~/.local/bin/codex (or `npm i -g @openai/codex`).
install_codex() {
  local dest="$HOME/.local/bin/codex" triple tmp bin
  if command -v codex >/dev/null; then ok "Already installed: $(codex --version 2>/dev/null | head -1)"; return; fi
  case "$(uname -m)" in
    x86_64) triple=x86_64-unknown-linux-musl ;;
    aarch64|arm64) triple=aarch64-unknown-linux-musl ;;
    *) die "No Codex build for $(uname -m)" ;;
  esac
  command -v curl >/dev/null || apt_install curl
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/openai/codex/releases/latest/download/codex-$triple.tar.gz" -o "$tmp/codex.tar.gz" \
    || { rm -rf "$tmp"; die "Codex download failed"; }
  mkdir "$tmp/x"; tar xzf "$tmp/codex.tar.gz" -C "$tmp/x" || { rm -rf "$tmp"; die "Could not unpack the Codex archive"; }
  # The archive holds one binary named after the platform; take that (or a plain 'codex').
  bin="$(find "$tmp/x" -type f \( -name codex -o -name "codex-$triple" \) | head -1)"
  [[ -n "$bin" ]] || { ls -R "$tmp/x" >&2; rm -rf "$tmp"; die "No codex binary found in the archive"; }
  mkdir -p "$(dirname "$dest")"; install -m 755 "$bin" "$dest"; rm -rf "$tmp"
  ok "Installed Codex $("$dest" --version 2>/dev/null | head -1). Run 'codex' to log in"
}

# pi (agentic harness, npm package @earendil-works/pi-coding-agent). Needs Node >= 22.19;
# Ubuntu 26.04's nodejs is 22.22. Installed into ~/.local so npm needs no sudo.
# --ignore-scripts is what the project recommends: dependency install scripts don't run.
PI_PKG="@earendil-works/pi-coding-agent"
node_ok() {
  command -v node >/dev/null || return 1
  local v; v="$(node -v 2>/dev/null | sed 's/^v//')"
  [[ "$(printf '%s\n22.19.0\n' "$v" | sort -V | head -1)" == 22.19.0 ]]
}
install_pi() {
  if command -v pi >/dev/null; then ok "Already installed: pi $(pi --version 2>/dev/null | head -1)"; return; fi
  if ! node_ok || ! command -v npm >/dev/null; then apt_install nodejs npm; fi
  node_ok || die "pi needs Node >= 22.19 but found $(node -v 2>/dev/null || echo none). Install a newer Node and re-run"
  run_logged "Installing $PI_PKG with npm" npm install -g --ignore-scripts --prefix "$HOME/.local" "$PI_PKG" \
    || die "npm install of $PI_PKG failed"
  command -v pi >/dev/null || [[ -x "$HOME/.local/bin/pi" ]] || die "pi is not in ~/.local/bin after install"
  ok "Installed pi $("$HOME/.local/bin/pi" --version 2>/dev/null | head -1). Run 'pi' and use /login"
}

install_unzip() {
  if command -v unzip >/dev/null; then ok "Already installed: unzip"; return; fi
  apt_install unzip zip
  ok "Installed unzip and zip"
}

# Ubuntu 26.04 ships the 7zip package (7zz, plus a 7z alias); p7zip-full is gone.
install_7zip() {
  if command -v 7z >/dev/null || command -v 7zz >/dev/null; then ok "Already installed: 7zip"; return; fi
  apt_install 7zip
  ok "Installed 7zip ($(command -v 7zz || command -v 7z))"
}

# Each app runs in its own process so one failure (a rotated key, a dead download)
# doesn't stop the others, and errexit stays active inside each installer.
if [[ -n "$ONE" ]]; then "install_$ONE"; exit; fi
FAILED=()
for app in "${APPS[@]}"; do
  step "$app"
  bash "${BASH_SOURCE[0]}" --_one "$app" || FAILED+=("$app")
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
  printf '\n%s%s✘ Failed: %s%s\n' "$RED" "$B" "${FAILED[*]}" "$RST" >&2
  printf '  Full output: %s\n  Retry with: bash apps/install.sh %s\n' "$LOG_FILE" "${FAILED[*]}" >&2
  exit 1
fi
done_msg Done.
