#!/usr/bin/env bash
#
# Entry point for a brand-new machine with nothing configured (no git, no SSH key).
# Installs git + curl, clones this repo over HTTPS (it is public) and runs bootstrap.sh.
#
# Usage (run from a terminal, keep the "bash <(...)" form so prompts and sudo work):
#   bash <(curl -fsSL https://raw.githubusercontent.com/santimontiel/dotfiles/master/get.sh)
#   bash <(curl -fsSL https://raw.githubusercontent.com/santimontiel/dotfiles/master/get.sh) --no-ros
#
# Arguments are passed on to bootstrap.sh (--no-docker --no-ros --no-git).
# Environment:
#   DOTFILES_DIR   where to clone (default: ~/Workspace/Tools/dotfiles)
#   DOTFILES_REPO  repo URL (default: https://github.com/santimontiel/dotfiles.git)
#   DOTFILES_REF   branch, tag or commit to use instead of the latest master
#                  (e.g. DOTFILES_REF=v1.0, so a blank machine runs a version you tested)
#
# Safe to re-run: an existing clone is fast-forwarded, never overwritten.

set -Eeuo pipefail
REPO="${DOTFILES_REPO:-https://github.com/santimontiel/dotfiles.git}"
DIR="${DOTFILES_DIR:-$HOME/Workspace/Tools/dotfiles}"
REF="${DOTFILES_REF:-}"

case "${1:-}" in -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;; esac

die() { printf '\n✘ %s\n' "$*" >&2; exit 1; }
[[ $EUID -ne 0 ]] || die "Run as your normal user, not root"
command -v apt-get >/dev/null || die "This needs an apt-based system (Ubuntu 26.04)"
# `curl | bash` eats stdin, so sudo and the Git prompts could not ask anything.
if [[ ! -t 0 ]]; then
  { : </dev/tty; } 2>/dev/null || die "No terminal available. Run it from a terminal window"
  exec </dev/tty
fi

printf '• Installing git and curl (sudo may ask for your password)\n'
if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y -qq git curl ca-certificates
fi

if [[ -d "$DIR/.git" ]]; then
  printf '• %s already exists, updating it\n' "$DIR"
  if [[ -z "$REF" ]]; then
    git -C "$DIR" pull --ff-only || printf '! Could not fast-forward; continuing with the existing copy\n'
  fi
elif [[ -e "$DIR" ]]; then
  die "$DIR exists but is not a git clone. Move it or set DOTFILES_DIR"
else
  printf '• Cloning %s into %s\n' "$REPO" "$DIR"
  mkdir -p "$(dirname "$DIR")"
  git clone "$REPO" "$DIR"
fi

if [[ -n "$REF" ]]; then
  printf '• Using %s\n' "$REF"
  git -C "$DIR" fetch --quiet --tags origin
  git -C "$DIR" checkout --quiet "$REF" || die "Could not check out $REF"
fi

cd "$DIR"
exec bash bootstrap.sh "$@"
