# shellcheck shell=bash
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

# header "Title" [subtitle]: a boxed banner for the start of a script.
header() {
  local t="$1" sub="${2:-}" w=${#1}
  [[ ${#sub} -gt $w ]] && w=${#sub}
  local rule; rule="$(printf '─%.0s' $(seq 1 $((w+2))))"
  printf '\n%s╭%s╮%s\n' "$CYN" "$rule" "$RST"
  printf '%s│%s %s%-*s%s %s│%s\n' "$CYN" "$RST" "$B" "$w" "$t" "$RST" "$CYN" "$RST"
  [[ -z "$sub" ]] || printf '%s│%s %s%-*s%s %s│%s\n' "$CYN" "$RST" "$DIM" "$w" "$sub" "$RST" "$CYN" "$RST"
  printf '%s╰%s╯%s\n' "$CYN" "$rule" "$RST"
}
# section "Title": a labelled rule between groups of output.
section() { printf '\n%s%s%s %s%s\n' "$B" "$1" "$RST" "$DIM" "$(printf '─%.0s' $(seq 1 $((50-${#1}>4?50-${#1}:4))))$RST"; }
STEP=0
step() { STEP=$((STEP+1)); printf '\n%s[%d/%d]%s %s%s%s\n' "$CYN" "$STEP" "${TOTAL:-?}" "$RST" "$B" "$*" "$RST"; }
done_msg() { printf '\n%s%s✔ %s%s\n' "$GRN" "$B" "${*:-Done.}" "$RST"; }
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
    local bak; bak="$dst.bak-$(date +%Y%m%d-%H%M%S)"
    mv "$dst" "$bak"
    warn "Moved existing $dst to $bak"
  fi
  if [[ "$mode" == link ]]; then
    ln -s "$(readlink -f "$src")" "$dst"; ok "Linked $dst -> $(readlink -f "$src")"
  else
    cp "$src" "$dst"; ok "Copied $src to $dst"
  fi
}

# ---- logged commands and apt helpers (used by apps/, docker/, bootstrap.sh) ----
# Noisy commands write to a log file; the terminal only gets one line per action,
# plus the tail of the log if the command fails. DOTFILES_VERBOSE=1 shows everything.
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${DOTFILES_LOG:-$(dirname "$_COMMON_DIR")/logs/setup-$(date +%Y%m%d).log}"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

# run_logged <description> <command...>
run_logged() {
  local desc="$1"; shift
  if [[ "${DOTFILES_VERBOSE:-0}" == 1 ]]; then info "$desc"; "$@"; return; fi
  info "$desc ${DIM}(log: ${LOG_FILE#"$PWD"/})${RST}"
  local out rc=0
  out="$(mktemp)"
  "$@" >"$out" 2>&1 || rc=$?
  { printf '\n$ %s\n' "$*"; cat "$out"; } >>"$LOG_FILE" 2>/dev/null || true
  if [[ $rc -ne 0 ]]; then
    printf '  %s✘%s %s failed (exit %d). Last lines of its output (full log: %s):\n' "$RED" "$RST" "$desc" "$rc" "$LOG_FILE" >&2
    tail -n 15 "$out" | sed 's/^/      /' >&2
  fi
  rm -f "$out"
  return $rc
}

# Fail early with a clear message when sudo can't ask for a password (no terminal).
need_sudo() {
  sudo -n true 2>/dev/null && return 0
  [[ -t 0 ]] || die "sudo needs a password but there is no terminal. Run this script from a terminal window (the '!' prefix in Claude Code has no terminal)"
}
# The "package lists are fresh" flag is a file, not a variable, so it survives the
# per-app child processes that apps/install.sh starts.
export APT_STAMP="${APT_STAMP:-$(mktemp -u /tmp/dotfiles-apt.XXXXXX)}"
# A fresh install often runs unattended-upgrades first and holds the dpkg lock;
# wait for it (up to 10 min) instead of failing. DEBIAN_FRONTEND avoids prompts.
APT=(sudo env DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600)
apt_refresh() { rm -f "$APT_STAMP"; }   # call after adding a repo
apt_update() {
  need_sudo
  [[ -e "$APT_STAMP" ]] && return 0
  run_logged "Updating package lists" "${APT[@]}" update -qq || return
  : >"$APT_STAMP"
}
apt_install() { apt_update || return; run_logged "Installing $*" "${APT[@]}" install -y -qq "$@"; }
pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q '^install ok installed'; }
# fetch_key <url> <dest-path>: download a repo signing key to <dest-path>.
# Armored keys are dearmored when the dest ends in .gpg; otherwise kept as-is (.asc).
fetch_key() {
  local url="$1" dest="$2" tmp
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; die "Could not download the key from $url"; }
  sudo mkdir -p "$(dirname "$dest")"
  if [[ "$dest" == *.gpg ]] && grep -q 'BEGIN PGP' "$tmp"; then gpg --dearmor <"$tmp" | sudo tee "$dest" >/dev/null
  else sudo install -m 644 "$tmp" "$dest"; fi
  rm -f "$tmp"
}
