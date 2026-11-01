# dotfiles

Santi's machine setup: apps, Docker, terminal, editor, ROS 2 and Git. Each folder installs one tool with a single idempotent script.

**Audience: a coding agent acting on Santi's instructions.** Read this file first, then the README of the folder you're working in.

| Folder | What it sets up | Installer | Needs sudo |
|---|---|---|---|
| [`alacritty/`](alacritty/README.md) | Alacritty terminal, config, "Thiago Monokai Pro for Alacritty" theme | `alacritty/install.sh` | Only to apt install Alacritty, or with `--default-terminal` |
| [`vscode/`](vscode/README.md) | VSCode font settings, "Thiago Monokai Pro for VSCode" theme | `vscode/install.sh` | Only if VSCode itself is missing |
| [`ros2-lyrical/`](ros2-lyrical/README.md) | ROS 2 Lyrical Luth from the ROS apt repo | `ros2-lyrical/install.sh` | Yes |
| [`apps/`](apps/README.md) | Dev tools, unzip, 7zip, herdr, Claude Code, Codex, pi, VSCode, Brave, Spotify, Discord, Claude Desktop | `apps/install.sh [app ...]` | Only for apps that are missing |
| [`docker/`](docker/README.md) | Docker Engine, Compose, Buildx, docker group | `docker/install.sh` | Yes |
| [`git/`](git/README.md) | Git identity, SSH key, `gh` login. **Interactive** | `git/setup.sh` | No |
| `get.sh` | Entry point for a blank machine: installs git, clones the repo, runs `bootstrap.sh` | `bash <(curl -fsSL .../get.sh)` | Yes |
| `bootstrap.sh` | Runs everything above in the right order, then `check.sh` | `bootstrap.sh` | Yes |
| `check.sh` | Read-only verification that the machine matches the repo | `check.sh` | No |
| `test/` | `container.sh`: runs shellcheck and the whole setup in a clean `ubuntu:26.04` container | `bash test/container.sh [--ros] [--lint-only]` | No (needs Docker) |
| `fonts/` | JetBrains Mono Nerd Font v3.5.1 (used by Alacritty and VSCode) | `fonts/install-jetbrains-mono-nf.sh` | No |
| `lib/` | Shared shell helpers for the installers. Not run directly | | |

Target system: Ubuntu 26.04 LTS ("resolute"), x86_64, GNOME, bash. The Alacritty and VSCode installers work on any apt-based system. The ROS installer refuses to run on anything but Ubuntu 26.04.

## Full setup on a new machine

On a brand-new machine (no git, no SSH key), from a terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/santimontiel/dotfiles/master/get.sh)
```

`get.sh` installs `git` and `curl`, clones this public repo over HTTPS into `~/Workspace/Tools/dotfiles` (`DOTFILES_DIR` to change it) and runs `bootstrap.sh`. Arguments are passed on: append `--no-ros`, `--no-docker` or `--no-git`. Use the `bash <(...)` form, not `curl ... | bash`: the pipe takes over stdin, so the sudo and Git prompts couldn't ask anything. When `git/setup.sh` finishes, it switches the clone's `origin` from HTTPS to SSH so `git push` uses your new key.

With git already available: `bash bootstrap.sh` from the repo root.

`bootstrap.sh` installs prerequisites, then runs `apps`, `docker`, `alacritty`, `vscode`, `ros2-lyrical` and `git/setup.sh` (the only interactive one, last), and finishes with `check.sh`. A failed step is reported and the rest continue. Order matters: `apps` comes before `vscode` because the VSCode installer needs `zip`.

To check a machine at any time: `bash check.sh` (add `--offline` to skip the GitHub SSH test). It changes nothing, prints `✔`/`!`/`✘` with the fix command for each failure, and exits non-zero if anything failed.

## Testing changes

`bash test/container.sh` runs shellcheck, then `bootstrap.sh`, `git/setup.sh`, a second `apps` run (must be a no-op) and `check.sh` in a throwaway `ubuntu:26.04` container, using the working tree. Add `--ros` to include ROS 2 (1-2 GB), `--lint-only` for just shellcheck. It does not cover Docker Engine (no systemd in the container), GNOME or the GPU, nor `get.sh` itself (it clones from GitHub, so push first). Run it before relying on a change on a real machine.

## Rules for agents

1. **Run the installers, don't reimplement them.** Every script checks its own state and only changes what's missing, so re-running is always safe. Don't copy config files by hand: the scripts back up whatever they replace.
2. **Check `--help` before running.** Each script documents its flags at the top of the file and prints them with `--help`.
3. **sudo:** you can't type Santi's password. If a script needs sudo and the credential isn't cached (`sudo -n true` fails), stop and ask Santi to run the command. In Claude Code, typing `! bash <script>` in the prompt runs it so the output lands in the conversation. Use `--skip-packages` to run the no-sudo parts on your own.
4. **Read the output markers.** `✔` done or already in place, `•` info, `!` warning (the run continues), `✘` fatal (exit code is non-zero). Report every `!` and `✘` line to Santi verbatim.
5. **Never delete backups** (`*.bak-<timestamp>`) unless Santi asks. They're the rollback path.
6. **Edit configs in the repo, not in `~/.config`.** Alacritty's files are symlinked into the repo by default, so editing either path changes the repo copy. VSCode's settings are merged, not linked: change `vscode/settings.json` and re-run the installer.
7. **Verify, then say what you verified.** Run `bash check.sh` first; each README also has a "Verify" section. If you couldn't run a check (no display, no sudo), say so instead of reporting success.
8. **Run `bash test/container.sh`** after changing an installer.
9. **Commits** use Gitmoji + Conventional Commits, for example `✨ feat: Add tmux config`.

## Adding a new tool

Create `<tool>/install.sh` and `<tool>/README.md` following the existing ones:

- Start the script with a header comment (purpose, usage, flags, what it changes), `set -Eeuo pipefail`, and `source "$HERE/../lib/common.sh"`.
- Make every step idempotent and print `✔` when there's nothing to do.
- Use `place_file link|copy <src> <dst>` from `lib/common.sh` to put config files in place; it backs up anything it replaces.
- Don't pipe into `grep -q` under `pipefail` (`cmd | grep -q x`): grep exits early, `cmd` gets SIGPIPE, and the pipeline fails at random. Capture the output in a variable first. This has broken two installers here already.
- Run `LC_ALL=C` on any command whose output you parse (the system locale is Spanish).
- Test with a throwaway `HOME` before touching the real one: `HOME=$(mktemp -d) bash <tool>/install.sh --skip-packages`.
- Add a row to the table above.
