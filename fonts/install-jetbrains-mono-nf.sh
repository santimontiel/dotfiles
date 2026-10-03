#!/usr/bin/env bash
#
# Installs JetBrains Mono Nerd Font (Nerd Fonts v3.5.1) for the current user.
# Used by alacritty/install.sh and vscode/install.sh; can also run on its own.
#
# Usage: bash fonts/install-jetbrains-mono-nf.sh [--force] [--help]
#   --force   reinstall even if the font is already present
#
# No sudo needed. Installs to ~/.local/share/fonts/JetBrainsMonoNF/.
# Safe to re-run: skips the download when the font is already installed.

set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

NF_VERSION="v3.5.1"
URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NF_VERSION}/JetBrainsMono.tar.xz"
DEST="$HOME/.local/share/fonts/JetBrainsMonoNF"
FAMILY="JetBrainsMono NF"   # family name the configs in this repo refer to
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

require_not_root
for c in curl tar xz fc-cache fc-list; do
  command -v "$c" >/dev/null || die "Missing '$c'. Install it with: sudo apt install -y curl tar xz-utils fontconfig"
done

# Capture fc-list output first: `fc-list | grep -q` fails under pipefail because
# grep exits early and fc-list gets SIGPIPE.
has_font() { local fams; fams="$(fc-list : family)"; grep -qF "$FAMILY" <<<"$fams"; }

if [[ $FORCE -eq 0 ]] && has_font; then
  ok "Font '$FAMILY' already installed"
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
info "Downloading JetBrains Mono Nerd Font $NF_VERSION"
curl -fsSL --retry 3 -o "$tmp/font.tar.xz" "$URL" || die "Download failed: $URL"
mkdir -p "$DEST"
tar -xJf "$tmp/font.tar.xz" -C "$DEST" || die "Could not extract the font archive"
fc-cache -f "$DEST" >/dev/null
has_font || die "Font installed to $DEST but fontconfig doesn't list '$FAMILY'"
ok "Installed '$FAMILY' to $DEST"
