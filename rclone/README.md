# rclone

Installs [rclone](https://rclone.org) and explains how to connect a Google Drive account on a machine you only reach over SSH.

Use it to download from Google Drive when gdown fails with *"Too many users have viewed or downloaded this file recently"*. Without a login, gdown uses the public share link, and Drive limits downloads per file on that link. With a login, rclone uses your own account and usually gets past that limit. It also lists every file in a folder, while gdown's folder download stops at 50 files per folder.

**Status on the reference machine: installed 2026-11-18.** rclone v1.76.0 at `~/.local/bin/rclone`, with a read-only remote `gdrive:` used to download MultiRadarDataset `Testdrive_Oct22`.

## Install

```bash
bash rclone/install.sh                     # latest release
bash rclone/install.sh --version v1.76.0   # pinned release
```

No sudo. The script downloads the official zip, checks it against the release's `SHA256SUMS`, and puts the binary at `~/.local/bin/rclone`. Re-running with the same version does nothing. It never creates remotes.

## Connect Google Drive over SSH

The Google login needs a browser, and the remote machine has none you can see. rclone's login page runs on the remote machine at `127.0.0.1:53682`, so you forward that port to your laptop and open the page there.

**1. On the remote machine**, start the login (agents can run this in the background):

```bash
rclone config create gdrive drive scope=drive.readonly
```

It prints a link like `http://127.0.0.1:53682/auth?state=...` and then waits.

- `scope=drive.readonly` means rclone can only read files. Use `scope=drive` if you also need to upload.
- `gdrive` is the remote's name. Commands refer to it as `gdrive:`.

**2. On your laptop**, in a new terminal, open a tunnel. Use your normal SSH command with these flags added:

```bash
ssh -N -L 53682:localhost:53682 <user>@<host>
```

The command shows no output and keeps running. Leave it open.

**3. On your laptop's browser**, open the link from step 1. Sign in with the Google account that can see the files, then click **Allow**. When the page says "Success", stop the tunnel with Ctrl+C. The command from step 1 exits and saves the remote.

If port 53682 is already in use on the laptop, close whatever is using it. The port is fixed in rclone's Google login settings, so you can't pick a different one.

**Alternative without a tunnel:** if rclone is installed on the laptop, run `rclone authorize "drive"` there and paste the token it prints into `rclone config` on the remote machine. To get that prompt, answer `n` when it asks whether to use a web browser.

## Use

Download a shared folder by its ID (the part after `/folders/` in the Drive URL). No need to add it to your own Drive:

```bash
ID=1YUyU6s-IXMjRv-f_NbgtmrWd7qjloOwk
rclone size  gdrive: --drive-root-folder-id "$ID"              # count and total size first
rclone copy  gdrive: /path/to/dest --drive-root-folder-id "$ID" -P --transfers 4
rclone check gdrive: /path/to/dest --drive-root-folder-id "$ID" --size-only --one-way
```

- `copy` skips files that already exist with the same size, so re-running resumes the download. It never deletes anything at the destination (`sync` does, so avoid it for downloads).
- `--size-only` compares only file sizes, so `check` is fast. Drive doesn't provide checksums for every file.
- To download only some files, write one path per line to a list and pass it with `--files-from list.txt`.
- **Check free disk space against `rclone size` before a big copy.** Partial files are left behind if the disk fills up.

## Verify

```bash
rclone version | head -1          # rclone v1.76.0
rclone listremotes                # gdrive:
rclone about gdrive:              # shows the account's Drive quota (proves the login works)
```

## Rules for agents

- **`~/.config/rclone/rclone.conf` holds the OAuth refresh token.** Never commit it, print it, or copy it into logs. `rclone config create` prints the full config, token included, so redirect its output to a file and delete that file once the login finishes.
- The login (step 3) needs Santi in a browser. Start step 1 in the background, give Santi the link and the tunnel command, and wait.
- When checking whether a process is running, use `pgrep -af` to find its PID and then `kill <pid>`. Don't use `pkill -f '<pattern>'`: the pattern also appears in the shell running that command, so the shell kills itself.

## Known issue: shared client_id

Every command warns: *"This remote uses rclone's shared Google Drive client_id, which is being retired and will stop working during 2026."* It still worked on 2026-11-18. If logins or downloads start failing with quota or `403` errors, create your own client ID ([rclone docs](https://rclone.org/drive/#making-your-own-client-id)) and recreate the remote:

```bash
rclone config create gdrive drive scope=drive.readonly client_id=<id> client_secret=<secret>
```

## Uninstall

```bash
rm ~/.local/bin/rclone
rm -r ~/.config/rclone          # deletes the remotes and their tokens
```

Also revoke access at <https://myaccount.google.com/permissions> ("rclone").
