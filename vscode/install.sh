#!/usr/bin/env bash
#
# Installs VSCode settings and the "Thiago Monokai Pro for VSCode" color theme.
#
# Usage: bash vscode/install.sh [options]
#   --skip-packages   don't install VSCode if it's missing (no sudo needed then)
#   --theme-only      only build and install the theme extension (no font, no settings)
#   -h, --help        show this help
#
# What it changes:
#   - installs the theme as extension "thiago.thiago-monokai-pro" (built from vscode/theme/)
#   - merges the keys in vscode/settings.json into ~/.config/Code/User/settings.json;
#     every other key in your settings is kept, and a backup is saved first
#
# Safe to re-run. Close VSCode first, or reload its window afterwards (see README).

set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"
trap 'die "Failed at line $LINENO: ${BASH_COMMAND}"' ERR

PACKAGES=1; THEME_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --skip-packages) PACKAGES=0 ;;
    --theme-only) THEME_ONLY=1 ;;
    -h|--help) awk 'NR>2 && /^#/ {sub(/^# ?/, ""); print; next} NR>2 {exit}' "$0"; exit 0 ;;
    *) die "Unknown option: $arg (try --help)" ;;
  esac
done

EXT_ID="thiago.thiago-monokai-pro"
LEGACY_IDS=("thiago.alacritty-monokai-pro")   # earlier names of the same theme
USER_SETTINGS="$HOME/.config/Code/User/settings.json"
TOTAL=5

printf '%sVSCode installer%s\n' "$B" "$RST"

step "Preflight"
require_not_root
command -v python3 >/dev/null || die "python3 is required to merge settings.json"
command -v zip >/dev/null || die "zip is required to package the theme. Install it with: sudo apt install -y zip"
if pgrep -x code >/dev/null; then
  warn "VSCode is running. It won't see the new theme until you reload its window (Ctrl+Shift+P > Developer: Reload Window)"
fi

step "VSCode package"
if command -v code >/dev/null; then
  ok "Already installed: VSCode $(code --version 2>/dev/null | head -1)"
elif [[ $PACKAGES -eq 1 ]]; then
  command -v apt-get >/dev/null || die "VSCode is missing and this system has no apt. Install VSCode manually, then re-run."
  info "Adding Microsoft's apt repo and installing 'code' (sudo may ask for a password)"
  sudo apt-get update -qq
  sudo apt-get install -y curl gpg
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /usr/share/keyrings/microsoft.gpg >/dev/null
  printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/code\nSuites: stable\nComponents: main\nArchitectures: %s\nSigned-By: /usr/share/keyrings/microsoft.gpg\n' \
    "$(dpkg --print-architecture)" | sudo tee /etc/apt/sources.list.d/vscode.sources >/dev/null
  sudo apt-get update -qq
  sudo apt-get install -y code
  ok "Installed: VSCode $(code --version 2>/dev/null | head -1)"
else
  die "VSCode ('code') is not installed and --skip-packages was given"
fi

step "Font"
if [[ $THEME_ONLY -eq 1 ]]; then info "Skipped (--theme-only)"; else bash "$HERE/../fonts/install-jetbrains-mono-nf.sh"; fi

step "Theme extension"
version="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$HERE/theme/package.json")"
build="$(mktemp -d)"; trap 'rm -rf "$build"' EXIT
mkdir -p "$build/pkg/extension"
cp -r "$HERE/theme/package.json" "$HERE/theme/themes" "$build/pkg/extension/"
cat > "$build/pkg/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json"/><Default Extension=".vsixmanifest" ContentType="text/xml"/></Types>
XML
cat > "$build/pkg/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="thiago-monokai-pro" Version="$version" Publisher="thiago"/>
    <DisplayName>Thiago Monokai Pro for VSCode</DisplayName>
    <Description xml:space="preserve">Monokai Pro palette with a darker background, matching Thiago Monokai Pro for Alacritty</Description>
    <Categories>Themes</Categories>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.70.0"/></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
XML
vsix="$build/thiago-monokai-pro-$version.vsix"
(cd "$build/pkg" && zip -qr "$vsix" '[Content_Types].xml' extension.vsixmanifest extension)
code --install-extension "$vsix" --force >/dev/null 2>&1 || die "code --install-extension failed for $vsix"
installed="$(code --list-extensions 2>/dev/null)"
grep -qx "$EXT_ID" <<<"$installed" || die "VSCode doesn't list $EXT_ID after installing it"
ok "Installed $EXT_ID $version"
for old in "${LEGACY_IDS[@]}"; do
  if grep -qx "$old" <<<"$installed"; then
    code --uninstall-extension "$old" >/dev/null 2>&1 && warn "Removed old copy of the theme: $old"
  fi
done

step "Settings"
if [[ $THEME_ONLY -eq 1 ]]; then
  info "Skipped (--theme-only)"
else
  mkdir -p "$(dirname "$USER_SETTINGS")"
  [[ -f "$USER_SETTINGS" ]] && cp "$USER_SETTINGS" "$USER_SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  python3 - "$HERE/settings.json" "$USER_SETTINGS" <<'PY' || die "Could not merge settings. Fix $USER_SETTINGS (see the error above) or set the keys from vscode/settings.json by hand"
import json, os, sys
repo_path, user_path = sys.argv[1], sys.argv[2]
managed = json.load(open(repo_path))
user = {}
if os.path.exists(user_path) and open(user_path).read().strip():
    try:
        user = json.load(open(user_path))
    except json.JSONDecodeError as e:
        # VSCode allows comments and trailing commas; plain json doesn't. Don't guess, stop.
        sys.exit(f"{user_path} is not plain JSON ({e}); it probably has comments or trailing commas")
changed = {k: v for k, v in managed.items() if user.get(k) != v}
user.update(managed)
with open(user_path, "w") as f:
    json.dump(user, f, indent=4)
    f.write("\n")
for k, v in changed.items():
    print(f"  set {k} = {json.dumps(v)}")
if not changed:
    print("  all managed keys were already set")
PY
  ok "Merged vscode/settings.json into $USER_SETTINGS (backup saved next to it)"
fi

printf '\n%s%sDone.%s Reload any open VSCode window to apply the theme (Ctrl+Shift+P > Developer: Reload Window).\n' "$GRN" "$B" "$RST"
