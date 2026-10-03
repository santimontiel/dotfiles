# Shared helpers for the installers in this repo. Source it, don't run it:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
#
# Output conventions (agents can grep for these):
#   "  ✔ ..."  step succeeded or was already in the desired state
#   "  • ..."  information, nothing changed
#   "  ! ..."  warning, the run continues
#   "✘ ..."    fatal error, the script exits non-zero

if [[ -t 1 ]]; then
  B=$'\e[1m'; DIM=$'\e[2m'; RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; CYN=$'\e[36m'; RST=$'\e[0m'
else
  B=; DIM=; RED=; GRN=; YEL=; CYN=; RST=
fi

STEP=0
step() { STEP=$((STEP+1)); printf '\n%s[%d/%d]%s %s%s%s\n' "$CYN" "$STEP" "${TOTAL:-?}" "$RST" "$B" "$*" "$RST"; }
info() { printf '  %s•%s %s\n' "$DIM" "$RST" "$*"; }
ok()   { printf '  %s✔%s %s\n' "$GRN" "$RST" "$*"; }
warn() { printf '  %s!%s %s\n' "$YEL" "$RST" "$*"; }
die()  { printf '\n%s✘ %s%s\n' "$RED" "$*" "$RST" >&2; exit 1; }

require_not_root() {
  [[ $EUID -ne 0 ]] || die "Run as your normal user, not root (the script calls sudo itself when needed)."
}

# Put $src at $dst. Mode "link" makes a symlink, "copy" copies the file.
# If $dst already exists with different content, it is moved to $dst.bak-<timestamp> first.
place_file() {
  local mode="$1" src="$2" dst="$3"
  mkdir -p "$(dirname "$dst")"
  if [[ "$mode" == link && -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
    ok "$dst already links to the repo"; return
  fi
  if [[ "$mode" == copy && -f "$dst" && ! -L "$dst" ]] && cmp -s "$src" "$dst"; then
    ok "$dst already up to date"; return
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    local bak="$dst.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$dst" "$bak"
    warn "Moved existing $dst to $bak"
  fi
  if [[ "$mode" == link ]]; then
    ln -s "$(readlink -f "$src")" "$dst"; ok "Linked $dst -> $(readlink -f "$src")"
  else
    cp "$src" "$dst"; ok "Copied $src to $dst"
  fi
}
