# dotfiles

Santi's machine setup: terminal, editor and ROS 2. Each folder installs one tool with a single idempotent script.

**Audience: a coding agent acting on Santi's instructions.** Read this file first, then the README of the folder you're working in.

| Folder | What it sets up | Installer | Needs sudo |
|---|---|---|---|
| [`alacritty/`](alacritty/README.md) | Alacritty terminal, config, "Thiago Monokai Pro for Alacritty" theme | `alacritty/install.sh` | Only to apt install Alacritty, or with `--default-terminal` |
| [`vscode/`](vscode/README.md) | VSCode font settings, "Thiago Monokai Pro for VSCode" theme | `vscode/install.sh` | Only if VSCode itself is missing |
| [`ros2-lyrical/`](ros2-lyrical/README.md) | ROS 2 Lyrical Luth from the ROS apt repo | `ros2-lyrical/install.sh` | Yes |
| `fonts/` | JetBrains Mono Nerd Font v3.5.1 (used by Alacritty and VSCode) | `fonts/install-jetbrains-mono-nf.sh` | No |
| `lib/` | Shared shell helpers for the installers. Not run directly | | |

Target system: Ubuntu 26.04 LTS ("resolute"), x86_64, GNOME, bash. The Alacritty and VSCode installers work on any apt-based system. The ROS installer refuses to run on anything but Ubuntu 26.04.

## Full setup on a new machine

Run from the repo root, in this order:

```bash
bash alacritty/install.sh          # also installs the font
bash vscode/install.sh
bash ros2-lyrical/install.sh       # long: downloads 1-2 GB
```

The order only matters for speed: the font is installed by whichever of the first two runs first, and the other skips it.

## Rules for agents

1. **Run the installers, don't reimplement them.** Every script checks its own state and only changes what's missing, so re-running is always safe. Don't copy config files by hand: the scripts back up whatever they replace.
2. **Check `--help` before running.** Each script documents its flags at the top of the file and prints them with `--help`.
3. **sudo:** you can't type Santi's password. If a script needs sudo and the credential isn't cached (`sudo -n true` fails), stop and ask Santi to run the command. In Claude Code, typing `! bash <script>` in the prompt runs it so the output lands in the conversation. Use `--skip-packages` to run the no-sudo parts on your own.
4. **Read the output markers.** `✔` done or already in place, `•` info, `!` warning (the run continues), `✘` fatal (exit code is non-zero). Report every `!` and `✘` line to Santi verbatim.
5. **Never delete backups** (`*.bak-<timestamp>`) unless Santi asks. They're the rollback path.
6. **Edit configs in the repo, not in `~/.config`.** Alacritty's files are symlinked into the repo by default, so editing either path changes the repo copy. VSCode's settings are merged, not linked: change `vscode/settings.json` and re-run the installer.
7. **Verify, then say what you verified.** Each README has a "Verify" section. If you couldn't run a check (no display, no sudo), say so instead of reporting success.
8. **Commits** use Gitmoji + Conventional Commits, for example `✨ feat: Add tmux config`.

## Adding a new tool

Create `<tool>/install.sh` and `<tool>/README.md` following the existing ones:

- Start the script with a header comment (purpose, usage, flags, what it changes), `set -Eeuo pipefail`, and `source "$HERE/../lib/common.sh"`.
- Make every step idempotent and print `✔` when there's nothing to do.
- Use `place_file link|copy <src> <dst>` from `lib/common.sh` to put config files in place; it backs up anything it replaces.
- Don't pipe into `grep -q` under `pipefail` (`cmd | grep -q x`): grep exits early, `cmd` gets SIGPIPE, and the pipeline fails at random. Capture the output in a variable first. This has broken two installers here already.
- Run `LC_ALL=C` on any command whose output you parse (the system locale is Spanish).
- Test with a throwaway `HOME` before touching the real one: `HOME=$(mktemp -d) bash <tool>/install.sh --skip-packages`.
- Add a row to the table above.
