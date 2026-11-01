#!/usr/bin/env bash
#
# Installs Alacritty with this repo's config and the "Thiago Monokai Pro for Alacritty" theme.
#
# Usage: bash alacritty/install.sh [options]
#   --copy               copy the config files instead of symlinking them to the repo
#   --skip-packages      don't apt install alacritty (no sudo needed then)
#   --default-terminal   make Alacritty the default terminal (GNOME + x-terminal-emulator, needs sudo)
#   --color-prompt       enable force_color_prompt=yes in ~/.bashrc (see README)
#   -h, --help           show this help
#
# Safe to re-run: each step checks its state first. Existing files that differ are
# moved to <file>.bak-<timestamp>, never deleted.

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"
trap 'die "Failed at line $LINENO: ${BASH_COMMAND}"' ERR

MODE="link"; PACKAGES=1; DEFAULT_TERM=0; COLOR_PROMPT=0
for arg in "$@"; do
  case "$arg" in
    --copy) MODE=copy ;;
    --skip-packages) PACKAGES=0 ;;
    --default-terminal) DEFAULT_TERM=1 ;;
    --color-prompt) COLOR_PROMPT=1 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

CONF_DIR="$HOME/.config/alacritty"
TOTAL=5

printf '%sAlacritty installer%s  %s(config mode: %s)%s\n' "$B" "$RST" "$DIM" "$MODE" "$RST"

step "Preflight"
require_not_root
command -v apt-get >/dev/null || die "This script expects a Debian/Ubuntu system with apt."
ok "System: $(. /etc/os-release && echo "$PRETTY_NAME")"

step "Alacritty package"
if command -v alacritty >/dev/null; then
  ok "Already installed: $(alacritty --version)"
elif [[ $PACKAGES -eq 1 ]]; then
  apt_install alacritty
  ok "Installed: $(alacritty --version)"
else
  warn "alacritty is not installed and --skip-packages was given; config will still be placed"
fi

step "Font"
bash "$HERE/../fonts/install-jetbrains-mono-nf.sh"

step "Config and theme"
place_file "$MODE" "$HERE/alacritty.toml" "$CONF_DIR/alacritty.toml"
place_file "$MODE" "$HERE/themes/thiago-monokai-pro.toml" "$CONF_DIR/themes/thiago-monokai-pro.toml"

step "Optional system integration"
if [[ $COLOR_PROMPT -eq 1 ]]; then
  if grep -qE '^force_color_prompt=yes' "$HOME/.bashrc"; then
    ok "~/.bashrc already has force_color_prompt=yes"
  elif grep -qE '^#force_color_prompt=yes' "$HOME/.bashrc"; then
    cp "$HOME/.bashrc" "$HOME/.bashrc.bak-$(date +%Y%m%d-%H%M%S)"
    sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' "$HOME/.bashrc"
    ok "Uncommented force_color_prompt=yes in ~/.bashrc (backup saved next to it)"
  else
    warn "No force_color_prompt line in ~/.bashrc; not changed. See README for the [env] TERM alternative"
  fi
else
  info "Skipped colored prompt (pass --color-prompt)"
fi
if [[ $DEFAULT_TERM -eq 1 ]]; then
  command -v alacritty >/dev/null || die "--default-terminal needs alacritty installed"
  if command -v gsettings >/dev/null; then
    gsettings set org.gnome.desktop.default-applications.terminal exec 'alacritty'
    gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e'
    ok "GNOME default terminal set to alacritty"
  else
    info "gsettings not found; skipped the GNOME setting"
  fi
  bin="$(command -v alacritty)"
  alts="$(update-alternatives --list x-terminal-emulator 2>/dev/null || true)"
  if ! grep -qx "$bin" <<<"$alts"; then
    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$bin" 50
  fi
  sudo update-alternatives --set x-terminal-emulator "$bin" >/dev/null
  ok "x-terminal-emulator -> $(readlink -f /etc/alternatives/x-terminal-emulator)"
else
  info "Skipped default terminal (pass --default-terminal)"
fi

# Verification: alacritty has no --check flag. `migrate --dry-run` parses the config
# and fails on TOML errors, but a missing import file passes silently, so check that too.
[[ -f "$CONF_DIR/themes/thiago-monokai-pro.toml" ]] || die "Theme file missing: $CONF_DIR/themes/thiago-monokai-pro.toml"
if command -v alacritty >/dev/null; then
  alacritty migrate --dry-run -c "$CONF_DIR/alacritty.toml" >/dev/null 2>&1 \
    && ok "Config parses (alacritty migrate --dry-run)" \
    || die "alacritty could not parse $CONF_DIR/alacritty.toml; run: alacritty migrate --dry-run -c $CONF_DIR/alacritty.toml"
fi

printf '\n%s%sDone.%s Open a new Alacritty window to see the result (open ones reload the config live).\n' "$GRN" "$B" "$RST"
