# Alacritty

Alacritty terminal with JetBrains Mono Nerd Font and the **Thiago Monokai Pro for Alacritty** theme (Monokai Pro colors on a darker background). The colors match [Thiago Monokai Pro for VSCode](../vscode/README.md).

## Files

| Repo file | Installed at | Purpose |
|---|---|---|
| `alacritty.toml` | `~/.config/alacritty/alacritty.toml` | Window, font and cursor settings. Loads the theme file |
| `themes/thiago-monokai-pro.toml` | `~/.config/alacritty/themes/thiago-monokai-pro.toml` | All colors |
| `install.sh` | | Installer |

By default both files are **symlinked** into the repo, so editing either path edits the repo copy. Use `--copy` for independent copies, for example when the repo will be deleted or moved.

## Install

```bash
bash alacritty/install.sh                      # package + font + config
bash alacritty/install.sh --skip-packages      # no sudo: font + config only
bash alacritty/install.sh --default-terminal   # also make Alacritty the default terminal (sudo)
```

| Flag | Effect |
|---|---|
| `--copy` | Copy the config files instead of symlinking them |
| `--skip-packages` | Don't apt install `alacritty`. No sudo needed |
| `--default-terminal` | Set GNOME's default terminal to `alacritty` and point `x-terminal-emulator` at it (sudo) |
| `--color-prompt` | Uncomment `force_color_prompt=yes` in `~/.bashrc` (see [Colored prompt](#colored-prompt)) |

Steps, in order:

1. Preflight: not root, apt available.
2. `sudo apt-get install -y alacritty`, skipped if `alacritty` is already on `PATH`.
3. Font: runs `fonts/install-jetbrains-mono-nf.sh`, which downloads Nerd Fonts v3.5.1 into `~/.local/share/fonts/JetBrainsMonoNF/` if fontconfig doesn't already list `JetBrainsMono NF`.
4. Config: places both files. An existing file with different content is moved to `<file>.bak-<timestamp>` first.
5. Optional `~/.bashrc` and default-terminal changes, only with their flags.
6. Checks that the theme file exists and that `alacritty migrate --dry-run` parses the config.

The script is safe to re-run. The second run prints only `✔` lines.

## Verify

```bash
alacritty --version                                    # alacritty 0.16.1 on the reference machine
alacritty migrate --dry-run -c ~/.config/alacritty/alacritty.toml >/dev/null && echo "config OK"
ls -l ~/.config/alacritty/alacritty.toml ~/.config/alacritty/themes/thiago-monokai-pro.toml
fc-list : family | grep -F "JetBrainsMono Nerd Font Mono"
```

`migrate --dry-run` catches TOML syntax errors but **not** a missing import file, which is why the `ls` line matters. The visual result (font, colors) can only be checked by opening a window. If you have no display, say so rather than claiming it works.

## Config reference

| Setting | Value | Notes |
|---|---|---|
| Font | JetBrainsMono Nerd Font Mono, size 10 | The "Mono" variant keeps Nerd Font icons one cell wide |
| Theme | `themes/thiago-monokai-pro.toml` | Loaded with `[general] import = [...]` (Alacritty 0.14+ syntax) |
| Opacity | 0.90 | Background shows through slightly, so it looks a bit lighter than `#222122` |
| Window size | 102 columns x 23 lines | |
| Padding | 8 px each side | |
| Cursor | Block, no blinking | |

Alacritty reloads its config live: open windows pick up saved changes, including changes to imported files.

## Theme: Thiago Monokai Pro for Alacritty

Monokai Pro with the background darkened from `#363537` to `#222122` (2026-10-03).

| | Normal | Bright |
|---|---|---|
| black | `#222122` | `#908E8F` |
| red | `#FF6188` | `#FF6188` |
| green | `#A9DC76` | `#A9DC76` |
| yellow | `#FFD866` | `#FFD866` |
| blue | `#FC9867` (orange) | `#FC9867` |
| magenta | `#AB9DF2` | `#AB9DF2` |
| cyan | `#78DCE8` | `#78DCE8` |
| white | `#FDF9F3` | `#FDF9F3` |

Background `#222122`, foreground `#FDF9F3`, cursor `#FDF9F3` with `#222122` text.

- Monokai Pro has no blue, so ANSI blue is orange on purpose. Programs that print blue show orange.
- "black" is the background color on purpose, as in the original palette.
- To change colors, edit `themes/thiago-monokai-pro.toml`. If you change the background, also change `editor.background`, `terminal.background` and `terminal.ansiBlack` in `vscode/theme/themes/thiago-monokai-pro.json` so the two themes keep matching.

## Colored prompt

Alacritty sets `TERM=alacritty`. Ubuntu's default `~/.bashrc` only enables a colored prompt for `xterm-color` or `*-256color`, so the prompt comes out uncolored. Two fixes:

- **Applied on the reference machine:** `force_color_prompt=yes` uncommented in `~/.bashrc` (`--color-prompt` does this).
- **Alternative:** add this to `alacritty.toml` and leave `.bashrc` alone. Some programs may then expect xterm features Alacritty doesn't have.

  ```toml
  [env]
  TERM = "xterm-256color"
  ```

Not verified: that `TERM` was the only cause.

## Default terminal

`--default-terminal` sets:

- `org.gnome.desktop.default-applications.terminal`: `exec='alacritty'`, `exec-arg='-e'`.
- `x-terminal-emulator` alternative: the `alacritty` binary (registered with priority 50 if missing).

Both were in place on the reference machine on 2026-10-03. Ctrl+Alt+T is GNOME's built-in shortcut and should follow the GNOME setting, but this hasn't been tested. If it still opens another terminal, add a custom GNOME shortcut that runs `alacritty`.

## Rollback

- Config: delete the symlink and rename the newest `~/.config/alacritty/alacritty.toml.bak-<timestamp>` back. Same for the theme file.
- `~/.bashrc`: restore `~/.bashrc.bak-<timestamp>`, or re-comment the `force_color_prompt` line.
- Default terminal: `sudo update-alternatives --config x-terminal-emulator` and `gsettings reset org.gnome.desktop.default-applications.terminal exec`.
- Package: `sudo apt remove alacritty`.

## Related

herdr (`~/.local/bin/herdr`, 0.9.3 on the reference machine) handles tabs, panes and persistent sessions, so Alacritty only hosts it. It isn't installed by this repo. To start herdr directly in every window, add:

```toml
[terminal.shell]
program = "/home/thiago/.local/bin/herdr"
```
