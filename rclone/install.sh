#!/usr/bin/env bash
#
# Installs the rclone binary to ~/.local/bin from downloads.rclone.org, verified
# against the release's SHA256SUMS. No sudo, no apt.
#
# Usage: bash rclone/install.sh [--version vX.Y.Z]
#   --version V   install release V (e.g. v1.76.0) instead of the latest
#   -h, --help    show this help
#
# Writes ~/.local/bin/rclone, replacing an older version there. Re-running with the
# same version changes nothing. Does NOT create remotes: connecting Google Drive
# needs a browser login, see rclone/README.md.

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?--version needs a value like v1.76.0}"; shift 2 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $1 (try --help)" ;;
  esac
done

BIN_DIR="$HOME/.local/bin"
DEST="$BIN_DIR/rclone"
TOTAL=4
header "rclone" "binary in ~/.local/bin"

step "Preflight"
require_not_root
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "Unsupported architecture: $(uname -m)" ;;
esac
for c in curl unzip sha256sum; do
  command -v "$c" >/dev/null || die "Missing '$c'. Install it with: sudo apt install $c"
done
ok "linux-$ARCH, curl, unzip and sha256sum available"

step "Resolve version"
if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL https://downloads.rclone.org/version.txt | awk '{print $2}')"
  [[ "$VERSION" == v* ]] || die "Could not read the latest version from downloads.rclone.org/version.txt"
  info "Latest release: $VERSION"
else
  info "Requested release: $VERSION"
fi
CURRENT=""
if [[ -x "$DEST" ]]; then
  CURRENT="$(LC_ALL=C "$DEST" version 2>/dev/null | awk 'NR==1{print $2}')"
fi
if [[ "$CURRENT" == "$VERSION" ]]; then
  ok "$DEST is already $VERSION"
  SKIP=1
else
  [[ -n "$CURRENT" ]] && info "Installed: $CURRENT, will replace it"
  SKIP=0
fi

step "Download and verify"
if [[ $SKIP -eq 1 ]]; then
  ok "Nothing to download"
else
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  ZIP="rclone-$VERSION-linux-$ARCH.zip"
  curl -fsSL "https://downloads.rclone.org/$VERSION/$ZIP" -o "$TMP/$ZIP" || die "Download failed: $VERSION/$ZIP"
  curl -fsSL "https://downloads.rclone.org/$VERSION/SHA256SUMS" -o "$TMP/SHA256SUMS" || die "Could not fetch SHA256SUMS for $VERSION"
  SUMS="$(cat "$TMP/SHA256SUMS")"
  WANT="$(awk -v f="$ZIP" '$2==f{print $1}' <<<"$SUMS")"
  [[ -n "$WANT" ]] || die "$ZIP is not listed in SHA256SUMS"
  GOT="$(sha256sum "$TMP/$ZIP" | awk '{print $1}')"
  [[ "$WANT" == "$GOT" ]] || die "Checksum mismatch for $ZIP (want $WANT, got $GOT)"
  ok "Checksum matches ($GOT)"
  unzip -q "$TMP/$ZIP" -d "$TMP"
  mkdir -p "$BIN_DIR"
  install -m 0755 "$TMP/rclone-$VERSION-linux-$ARCH/rclone" "$DEST"
  ok "Installed $DEST"
fi

step "Verify"
INSTALLED="$(LC_ALL=C "$DEST" version | awk 'NR==1{print $2}')"
[[ "$INSTALLED" == "$VERSION" ]] || die "$DEST reports $INSTALLED, expected $VERSION"
ok "$DEST version $INSTALLED"
case ":$PATH:" in
  *":$BIN_DIR:"*) ok "$BIN_DIR is on PATH" ;;
  *) warn "$BIN_DIR is not on PATH in this shell. Ubuntu's ~/.profile adds it on next login if it exists." ;;
esac
if [[ -f "$HOME/.config/rclone/rclone.conf" ]]; then
  info "Existing remotes: $("$DEST" listremotes 2>/dev/null | tr '\n' ' ')"
else
  info "No remotes yet. To connect Google Drive, follow rclone/README.md"
fi
done_msg
