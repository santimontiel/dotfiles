# Apps

One script that installs everyday apps and CLI tools on an apt-based system.

| App | How it's installed | Already-installed check |
|---|---|---|
| `devtools` | Ubuntu repo: `git curl gpg python3 python3-venv pipx build-essential cmake tmux htop ripgrep fd-find jq gh` (`fd-find` installs `fdfind`, not `fd`) | dpkg, per package |
| `herdr` | Static binary from GitHub releases to `~/.local/bin/herdr`, no sudo. Update later with `herdr update` | `herdr` on `PATH` |
| `claude` | Claude Code CLI via Anthropic's native installer (`claude.ai/install.sh`), binary in `~/.local/share/claude`, link in `~/.local/bin`. Self-updating | `claude` on `PATH` |
| `codex` | OpenAI Codex CLI: static musl binary from GitHub releases to `~/.local/bin/codex`, no sudo, no Node | `codex` on `PATH` |
| `pi` | pi agentic harness: npm package `@earendil-works/pi-coding-agent`, installed with `--ignore-scripts` into `~/.local`. Installs `nodejs` + `npm` from apt if Node < 22.19 | `pi` on `PATH` |
| `vscode` | Microsoft apt repo, package `code` | `code` on `PATH` |
| `brave` | Brave apt repo, package `brave-browser` | dpkg |
| `spotify` | Spotify apt repo, package `spotify-client` | dpkg |
| `discord` | Latest `.deb` from discord.com (no apt repo), installed with apt | dpkg |
| `claude-desktop` | Anthropic apt repo, package `claude-desktop` | dpkg |
| `unzip` | Ubuntu repo: `unzip` and `zip` | `unzip` on `PATH` |
| `7zip` | Ubuntu repo, package `7zip` (gives `7zz` and `7z`; `p7zip-full` no longer exists on 26.04) | `7z` or `7zz` on `PATH` |

## Install

```bash
bash apps/install.sh                  # everything
bash apps/install.sh 7zip discord     # only these
bash apps/install.sh --list
```

Needs sudo for anything missing; apps already installed are skipped without it. Repo keys go to `/usr/share/keyrings`, repo files to `/etc/apt/sources.list.d`.

## Verify

```bash
bash check.sh --offline
```

## Pitfalls

- **Log in once per tool, by hand:** `claude`, `codex` and `pi` (`/login`) each need an interactive login or API key. The installer can't do that.
- **`pi` was renamed:** the old `@mariozechner/pi-coding-agent` package is deprecated; this installer uses `@earendil-works/pi-coding-agent`. Settings in `~/.pi/agent` carry over.
- **`codex` is not auto-updated** by the installer. Delete `~/.local/bin/codex` and re-run `bash apps/install.sh codex` to get the latest release.
- **New tools need a new shell:** `~/.local/bin` joins `PATH` at login only if it existed then.

- **Spotify's signing key rotates.** If the key download 404s, take the new URL from https://www.spotify.com/download/linux/ and update `SPOTIFY_KEY_URL` in `install.sh`.
- **Discord's `.deb` isn't updated by apt.** Re-running the installer won't upgrade it; Discord updates itself on launch.

## Adding an app

Shared apt helpers (`apt_install`, `fetch_key`, `pkg_installed`) live in `lib/common.sh`. Add its name to `ALL` and an `install_<name>` function in `install.sh` that returns early with `ok` when already installed.
