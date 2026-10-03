# VSCode

JetBrains Mono Nerd Font in the editor and built-in terminal, plus the **Thiago Monokai Pro for VSCode** color theme. The colors match [Thiago Monokai Pro for Alacritty](../alacritty/README.md).

## Files

| Repo file | Purpose |
|---|---|
| `settings.json` | The settings this repo manages. Merged into `~/.config/Code/User/settings.json` |
| `theme/package.json` | Extension manifest: id `thiago.thiago-monokai-pro`, theme label `Thiago Monokai Pro for VSCode` |
| `theme/themes/thiago-monokai-pro.json` | All theme colors: UI, syntax, semantic tokens, terminal |
| `install.sh` | Installer: packages the theme as a `.vsix`, installs it, merges settings |

## Install

```bash
bash vscode/install.sh                   # VSCode if missing + font + theme + settings
bash vscode/install.sh --skip-packages   # no sudo; fails if VSCode isn't installed
bash vscode/install.sh --theme-only      # only rebuild and reinstall the theme
```

**Close VSCode before running, or reload its window afterwards** (Ctrl+Shift+P → "Developer: Reload Window"). See [Pitfalls](#pitfalls).

Steps, in order:

1. Preflight: not root, `python3` and `zip` available, warns if VSCode is running.
2. VSCode: skipped if `code` is on `PATH`. Otherwise adds Microsoft's apt repo (`/etc/apt/sources.list.d/vscode.sources`, key in `/usr/share/keyrings/microsoft.gpg`) and installs `code` (sudo).
3. Font: runs `fonts/install-jetbrains-mono-nf.sh` (skipped with `--theme-only`).
4. Theme: builds a `.vsix` in a temp folder from `theme/` and runs `code --install-extension <vsix> --force`. Also removes `thiago.alacritty-monokai-pro`, an earlier name of the same theme, if it's installed.
5. Settings (skipped with `--theme-only`): backs up `~/.config/Code/User/settings.json` to `settings.json.bak-<timestamp>`, then sets each key from `vscode/settings.json` and prints the ones that changed. All your other keys are kept.

No `vsce` or Node is needed. The `.vsix` is a zip with a manifest, built by the script.

## Verify

```bash
code --list-extensions | grep -x thiago.thiago-monokai-pro
python3 -c 'import json,os; s=json.load(open(os.path.expanduser("~/.config/Code/User/settings.json"))); print(s["workbench.colorTheme"], s["editor.fontFamily"], s["editor.fontSize"])'
# Thiago Monokai Pro for VSCode 'JetBrainsMono NF', monospace 13
```

Seeing the theme applied requires a reloaded VSCode window. If you can't check that, say so.

## Managed settings

| Key | Value | Notes |
|---|---|---|
| `editor.fontFamily` | `'JetBrainsMono NF', monospace` | `JetBrainsMono NF` is the fontconfig family name. Check with `fc-list : family \| grep JetBrains` |
| `editor.fontSize` | `13` | VSCode sizes are pixels, not points. 13 px ≈ 10 pt, the Alacritty font size |
| `terminal.integrated.fontFamily` | `'JetBrainsMono NF'` | |
| `terminal.integrated.fontSize` | `13` | |
| `workbench.colorTheme` | `Thiago Monokai Pro for VSCode` | Must equal the theme `label` in `theme/package.json` |

To add or change a setting, edit `vscode/settings.json` and re-run the installer. Removing a key from `vscode/settings.json` does **not** remove it from the user settings; delete it there by hand.

## Theme: Thiago Monokai Pro for VSCode

Built from the Alacritty palette, with UI shades derived from it.

| Role | Color |
|---|---|
| Editor and terminal background | `#222122` |
| Sidebar, tabs, title and status bars | `#1A191A` |
| Borders | `#121112` |
| Current line, inputs | `#2E2D2F` |
| Selection | `#5B595C` |
| Text | `#FDF9F3` |
| Comments | `#908E8F`, italic |
| Accent (active tab, badges, buttons) | `#FFD866` |

Syntax: keywords and tags pink `#FF6188`, strings yellow `#FFD866`, functions and decorators green `#A9DC76`, types, classes and attributes cyan `#78DCE8`, numbers and constants purple `#AB9DF2`, parameters orange `#FC9867` italic. The built-in terminal uses the Alacritty ANSI colors exactly, including orange for "blue".

### Changing the theme

1. Edit `theme/themes/thiago-monokai-pro.json`. VSCode's color keys are listed at https://code.visualstudio.com/api/references/theme-color.
2. Run `bash vscode/install.sh --theme-only`.
3. Reload the VSCode window.

Bump `version` in `theme/package.json` only if you want VSCode to show a new version; `--force` reinstalls the same version fine.

To rename the theme, change the `label` and `displayName` in `theme/package.json`, `name` in the theme JSON, `<DisplayName>` in `install.sh`, and `workbench.colorTheme` in `settings.json` together. Changing the extension id (`name`/`publisher` in `package.json`) installs a second extension: add the old id to `LEGACY_IDS` in `install.sh` so it gets removed.

## Pitfalls

These all happened on the reference machine:

- **A running VSCode doesn't see extensions installed from the command line.** Reload the window after installing.
- **Uninstalling the active theme while VSCode is open makes VSCode delete `workbench.colorTheme` from settings.json**, and it falls back to the default theme. The installer installs the new theme first, removes legacy copies second and writes settings last for this reason. If it happens anyway, re-run the installer with VSCode closed.
- **settings.json with comments or trailing commas** (VSCode allows both) can't be parsed by the merge step. The script stops without changing anything. Either remove the comments or set the keys from `vscode/settings.json` by hand.
- **An uninstalled extension's folder stays in `~/.vscode/extensions/`** until VSCode next starts. It's listed in `~/.vscode/extensions/.obsolete` and is harmless.

## Rollback

- Settings: restore the newest `~/.config/Code/User/settings.json.bak-<timestamp>`.
- Theme: `code --uninstall-extension thiago.thiago-monokai-pro` with VSCode closed, then pick another theme.
