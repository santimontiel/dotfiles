#!/usr/bin/env bash
#
# Interactive Git + GitHub setup: identity, SSH key, ssh config, optional gh login.
#
# Usage: bash git/setup.sh [options]
#   --name "Full Name"   skip the name prompt
#   --email you@x.com    skip the email prompt
#   --key NAME           SSH key file name under ~/.ssh (default: id_ed25519_github)
#   --no-gh              don't offer 'gh auth login'
#   -h, --help           show this help
#
# Prompts show the current value in [brackets]; press Enter to keep it. Needs a
# terminal. Safe to re-run: never overwrites an existing key or config entry.

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

NAME=""; EMAIL=""; KEY=id_ed25519_github; GH=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="${2:?--name needs a value}"; shift ;;
    --email) EMAIL="${2:?--email needs a value}"; shift ;;
    --key) KEY="${2:?--key needs a value}"; shift ;;
    --no-gh) GH=0 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done
TOTAL=4
header "Git and GitHub" "identity, SSH key, gh login"
require_not_root
command -v git >/dev/null || die "git is missing. Run: bash apps/install.sh devtools"
[[ -t 0 || ( -n "$NAME" && -n "$EMAIL" ) ]] || die "No terminal to ask questions on. Pass --name and --email, or run it from a terminal"

# ask <prompt> <current> -> prints the answer (current if the user just presses Enter)
ask() {
  local ans
  if [[ -t 0 ]]; then read -r -p "  $1${2:+ [$2]}: " ans; fi
  printf '%s' "${ans:-$2}"
}

step "Identity"
[[ -n "$NAME" ]] || NAME="$(ask "Full name" "$(git config --global user.name || true)")"
[[ -n "$EMAIL" ]] || EMAIL="$(ask "Email (use your GitHub one)" "$(git config --global user.email || true)")"
[[ -n "$NAME" && -n "$EMAIL" ]] || die "Name and email are required"
[[ "$EMAIL" == *@*.* ]] || die "That doesn't look like an email: $EMAIL"
git config --global user.name "$NAME"
git config --global user.email "$EMAIL"
ok "user.name = $NAME, user.email = $EMAIL"

step "SSH key"
KEYFILE="$HOME/.ssh/$KEY"
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if [[ -f "$KEYFILE" ]]; then
  ok "$KEYFILE already exists (not touched)"
else
  command -v ssh-keygen >/dev/null || die "ssh-keygen missing. Run: sudo apt install openssh-client"
  if [[ -t 0 ]]; then
    info "Creating an ed25519 key. ssh-keygen will ask for a passphrase (recommended)"
    ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEYFILE"
  else
    warn "No terminal: creating the key WITHOUT a passphrase. Add one later with: ssh-keygen -p -f $KEYFILE"
    ssh-keygen -q -t ed25519 -N "" -C "$EMAIL" -f "$KEYFILE"
  fi
  ok "Created $KEYFILE"
fi

step "~/.ssh/config"
CFG="$HOME/.ssh/config"; touch "$CFG"; chmod 600 "$CFG"
if grep -qE '^Host[[:space:]]+github\.com' "$CFG"; then
  ok "A 'Host github.com' entry already exists (not touched)"
else
  printf '\nHost github.com\n  User git\n  IdentityFile ~/.ssh/%s\n  IdentitiesOnly yes\n' "$KEY" >> "$CFG"
  ok "Added a 'Host github.com' entry using $KEY"
fi

step "GitHub"
if [[ $GH -eq 0 ]]; then
  info "Skipped (--no-gh)"
elif ! command -v gh >/dev/null; then
  warn "gh is not installed (bash apps/install.sh devtools). Add $KEYFILE.pub at https://github.com/settings/keys by hand"
elif gh auth status >/dev/null 2>&1; then
  ok "gh is already logged in"
  gh auth setup-git >/dev/null 2>&1 || true
elif [[ -t 0 ]]; then
  ans="$(ask "Log in to GitHub with gh now and upload the SSH key? (y/N)" "N")"
  if [[ "$ans" =~ ^[Yy] ]]; then
    gh auth login -h github.com -p ssh --skip-ssh-key -w
    gh ssh-key add "$KEYFILE.pub" -t "$(hostname)" || warn "Could not upload the key (it may already be there)"
    gh auth setup-git
    ok "Logged in and key uploaded"
  else
    info "Skipped. Add this public key at https://github.com/settings/keys:"
    cat "$KEYFILE.pub"
  fi
else
  info "Not a terminal; skipping gh login. Public key: $KEYFILE.pub"
fi

# A clone made by get.sh uses HTTPS; switch it to SSH so 'git push' uses the key.
REPO_DIR="$(cd "$HERE/.." && pwd)"
origin="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
if [[ "$origin" =~ ^https://github\.com/([^/]+/[^/]+)$ ]]; then
  git -C "$REPO_DIR" remote set-url origin "git@github.com:${BASH_REMATCH[1]}"
  ok "Switched this repo's origin to SSH: git@github.com:${BASH_REMATCH[1]}"
fi

done_msg Done.
