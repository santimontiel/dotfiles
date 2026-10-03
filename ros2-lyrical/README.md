# ROS 2 Lyrical Luth

Installs ROS 2 Lyrical Luth (May 2026 release) from the official ROS apt repo on Ubuntu 26.04 "resolute".

**Status on the reference machine: installed and verified on 2026-10-01.** `ros-lyrical-desktop` 0.13.0-3resolute.20260915.155952 at `/opt/ros/lyrical`. The last run took 226 s and passed every check, including a talker/listener round trip.

## Requirements

The script checks all of these and stops with a clear message if one fails:

- Ubuntu 26.04 (`VERSION_CODENAME=resolute`). Lyrical targets only this release.
- amd64 or arm64.
- At least 5 GB free on `/opt`.
- A normal user with sudo. **Don't run it as root or with `sudo bash`**: it calls sudo itself.
- Network access to `raw.githubusercontent.com` (GPG key) and `packages.ros.org` (packages, over http).

## Install

```bash
bash ros2-lyrical/install.sh             # desktop (rviz, rqt, demos)
bash ros2-lyrical/install.sh --base      # headless: ros-lyrical-ros-base
bash ros2-lyrical/install.sh --no-bashrc # don't touch ~/.bashrc
```

**Agents:** this script always needs sudo and asks for the password once with `sudo -v`. If `sudo -n true` fails, don't try to work around it: ask Santi to run `! bash ros2-lyrical/install.sh` in Claude Code, or to run `sudo -v` in your shell first. The script keeps the sudo credential alive during the run.

The script is idempotent: every step checks its state first, so re-running is safe and also repairs a half-finished install.

### Steps

Each step is printed as `[n/7]`:

1. **Preflight:** OS codename, architecture, disk space on `/opt`, sudo.
2. **Prerequisites:** `apt-get update`, installs `curl`, `gnupg`, `software-properties-common`, enables `universe`.
3. **GPG key:** downloads `ros.key` from `ros/rosdistro` and installs it to `/usr/share/keyrings/ros-archive-keyring.gpg`. Accepts armored or binary keys.
4. **Apt source:** writes `/etc/apt/sources.list.d/ros2.sources` (http URI, see below). An existing different file is saved as `.bak`. Checks that the package has an install candidate.
5. **Install:** `ros-lyrical-desktop` (or `-ros-base`) and `ros-dev-tools`. Downloads 1-2 GB; this is the long step.
6. **Shell setup:** appends a **commented-out** `source /opt/ros/lyrical/setup.bash` line to `~/.bashrc`, unless one is already there.
7. **Verification:** `ROS_DISTRO` is `lyrical`, `ros2 --help` works, and a C++ talker/listener exchange messages.

### Logs

The console shows one line per action with its duration. Full command output goes to `ros2-lyrical/logs/install-<timestamp>.log` next to the script. On failure the last 15 log lines are printed with the failing command. To follow the long install step:

```bash
tail -f ros2-lyrical/logs/install-*.log
```

`logs/` is git-ignored.

## Usage

The `source` line in `~/.bashrc` is commented out on purpose, so ROS doesn't load in every shell. Enable it per shell:

```bash
source /opt/ros/lyrical/setup.bash
```

Or uncomment the line in `~/.bashrc` (line 121 on the reference machine; it was still commented out on 2026-10-03).

## Verify

The script runs these checks itself in step 7. To repeat them by hand:

```bash
source /opt/ros/lyrical/setup.bash
printenv ROS_DISTRO                      # lyrical
ros2 run demo_nodes_cpp talker           # shell 1
ros2 run demo_nodes_py listener          # shell 2: prints "I heard: [Hello World: N]"
dpkg-query -W -f='${Version}\n' ros-lyrical-desktop
```

## Why the script writes the apt source itself

`https://packages.ros.org` fails certificate verification from the reference machine: it serves OSUOSL's `*.osuosl.org` certificate, which doesn't cover that hostname. So the script writes the source with an `http://` URI instead of using the `ros2-apt-source` deb. Not verified: whether that deb would write an `https://` URI and hit the same error.

http is safe here because apt checks every package against the GPG key in `Signed-By`. **Don't** switch to `curl -k` or `[trusted=yes]`.

If `ros2-apt-source` is installed, the script warns, because it may define a second, duplicate source.

## Compatibility checks done before the first install (2026-10-01)

- `http://packages.ros.org/ros2/ubuntu/dists/resolute/` had `ros-lyrical-desktop`, `ros-lyrical-ros-base` and `ros-lyrical-ros-core`.
- `ros-apt-source` 1.3.0 had a `resolute` build of `ros2-apt-source`.
- `/opt/ros` didn't exist yet.

## Install history

Two bugs broke the first runs. Both are fixed, and both are worth knowing when writing scripts for this machine:

- **Locale:** the system locale is Spanish, so `apt-cache policy` printed `Candidato:` and matching `Candidate:` failed. Fix: `LC_ALL=C` on commands whose output is parsed.
- **`pipefail` + `grep -q`:** `grep -q` exits at the first match, `apt-cache` gets SIGPIPE, and the whole pipeline counts as failed. Fix: capture the output in a variable, then grep it.

## Uninstall

```bash
sudo apt remove --autoremove 'ros-lyrical-*' ros-dev-tools
sudo rm /etc/apt/sources.list.d/ros2.sources /usr/share/keyrings/ros-archive-keyring.gpg
sudo apt-get update
```

Then delete the ROS lines from `~/.bashrc`.
