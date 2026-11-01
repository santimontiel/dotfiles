# Git and GitHub

Interactive setup of your Git identity, an SSH key for GitHub and, optionally, `gh` login. Run it in a terminal: it asks questions.

## Run

```bash
bash git/setup.sh
bash git/setup.sh --name "Santi" --email you@x.com --no-gh   # no prompts for the identity
```

Steps:

1. **Identity:** asks for name and email (current values shown in `[brackets]`, Enter keeps them) and sets `git config --global user.name/user.email`.
2. **SSH key:** creates `~/.ssh/id_ed25519_github` (`--key NAME` to change) with `ssh-keygen`, which asks for a passphrase. An existing key is never touched.
3. **`~/.ssh/config`:** adds a `Host github.com` entry pointing at the key, unless one exists.
4. **GitHub:** offers `gh auth login` (SSH, browser flow), uploads the public key with `gh ssh-key add`, and runs `gh auth setup-git`. If you decline, it prints the public key for https://github.com/settings/keys.

Needs `git` (and `gh` for step 4): `bash apps/install.sh devtools`.

## Verify

```bash
ssh -T git@github.com     # "Hi <user>! You've successfully authenticated"
bash check.sh
```

## Pitfalls

- Passphrase-protected keys need `ssh-add` (GNOME usually does it on first use) before non-interactive `git push` works.
- Agents: this script is interactive. Ask Santi to run it with `! bash git/setup.sh`, or pass `--name` and `--email`.
