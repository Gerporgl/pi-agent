# podman-pi-agent

A minimal Ubuntu 26.04 container that runs the [pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) and [pi-web](https://www.npmjs.com/package/@jmfederico/pi-web) inside a full containerized sandbox.

## Design

- **Base**: Ubuntu 26.04 with a minimal set of CLI tools the agent can use (git, ripgrep, build-essential, jq, yq, etc.).
- **Init**: full `systemd` as entrypoint (`/sbin/init`), with `pi-web` and `pi-web-sessiond` managed as systemd services. Works well on Proxmox LXC (full TTY console, clean shutdown) and in nested podman containers.
- **Users**: pi-agent and pi-web run as the unprivileged `ubuntu` user. `openssh-server` is installed for administrative SSH access (as `root`).
- **Persistence**: agent/web state lives under `/home/ubuntu`, which is intended to be bind-mounted (see `home-data/` for a reference layout). Put your own `~/.pi/agent/models.json` (and other pi configs) in that mounted volume.

## Building

```bash
./build.sh            # builds pi-agent:latest (uses podman if available, else docker)
./build_and_run.sh    # build + local run
```

## Running

```bash
./run.sh              # example run: creates the container, sets a root password,
                      # copies your SSH key for root, and attaches
./run_local.sh        # same, but using the locally built image
```

Key run options (podman):

| Option | Purpose |
|---|---|
| `-v ./home-data:/home/ubuntu` | persistent agent + pi-web state |
| `--userns=keep-id` | keep host UID so mounted files are owned correctly |
| `-p 2222:22` | SSH access |
| `-p 8555:8504` | pi-web web UI |

`run.sh` is just an example script; it works equally well with **podman quadlets** or as a Proxmox LXC container. If not run as root, there is no way in — that is the intended default.

## Notes

- No automatic apt updates: systemd update timers are removed. Update by rebuilding the image.
- If `/home/ubuntu` is mounted empty, a one-shot systemd service seeds it with a home skeleton (dotfiles, pi configs).
