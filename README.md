# podman-pi-agent

A minimal Ubuntu 26.04 container that runs the [pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) and [pi-web](https://www.npmjs.com/package/@jmfederico/pi-web) inside a full containerized sandbox.

The entire container project was coded mostly by the pi agent itself (which also runs within it by itself and edit its own container based on given instructions...). The model used (at the time of writing) is [ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF:IQ3_S](https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF) (mtp), running on a 16GB vram amdgpu (9060XT) and fitting a 64K context size at kv q8 (providing around ~20 tokens/sec). This is all hosted on a proxmox server running on different lxc nested containers. The llama.cpp inference engine is hosted using this sibling container project: [llama-lxc](https://github.com/Gerporgl/llama-lxc) which is also hosted on the same proxmox host in a separate lxc container, and passing the amdgpu. All of this running in unprivileged mode.

## Design

- **Base**: Ubuntu 26.04 with a minimal set of CLI tools the agent can use (python, uv, node.js, gcc, git, ripgrep, build-essential, jq, yq, etc.).
- **Rust+Cargo**: Always the latest rust stable release, bundled with musl so the agent can build static binaries without any libc dependency
- **Godot**: the [Godot engine](https://godotengine.org) (headless-capable) is installed system-wide; the real binary lives at `/usr/local/lib/godot/godot` and `/usr/local/bin/godot` is a thin wrapper that auto-adds `--headless` when no display server is available, so MCP `run_project` and CI work headlessly. It ships together with the [`@coding-solo/godot-mcp`](https://www.npmjs.com/package/@coding-solo/godot-mcp) MCP server (global npm). pi connects to MCP servers through the [pi-mcp-adapter](https://www.npmjs.com/package/pi-mcp-adapter) package, also installed globally — it adds a single lazy `mcp` proxy tool, so Godot's MCP tools only enter the model context when actually used.
- **Init**: full `systemd` as entrypoint (`/sbin/init`), with `pi-web` and `pi-web-sessiond` managed as systemd services. Works well on Proxmox LXC (full TTY console, clean shutdown) and in nested podman containers.
- **Users**: pi-agent and pi-web run as the unprivileged `agent` user. `openssh-server` is installed for administrative SSH access (as `root`, running on **port 2223**, you'll need to mount your authorized_keys, or set a root password, see run.sh code).
- **Persistence**: agent/web state lives under `/home/agent`, which is intended to be bind-mounted (see `home-data/` for a reference layout). Put your own `~/.pi/agent/models.json` (and other pi configs) in that mounted volume.
  - Benefit: Base image can safely be updated regularly without losing anything the agent created inside its home folder, which is the only place it can write.

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
| `-v ./home-data:/home/agent` | persistent agent + pi-web state |
| `--userns=keep-id` | keep host UID so mounted files are owned correctly |
| `-p 2223:2223` | SSH access |
| `-p 8504:8504` | pi-web web UI |

`run.sh` is just an example script; it works equally well with **podman quadlets** or as a Proxmox LXC container. If not run as root, there is no way in — that is the intended default.

## Migrating an existing home folder (ubuntu → agent)

If your persistent home folder was created with an older image (when the user was `ubuntu`), migrate its pi / pi-web state to the `agent` layout:

```bash
./migrate.sh ./pi-agent-home              # add --dry-run to preview without changes
```

It renames pi session directories under `.pi/agent/sessions/` (`--home-ubuntu-*` → `--home-agent-*`), rewrites `/home/ubuntu` → `/home/agent` in the pi / pi-web state files (`trust.json`, `projects.json`, `archived-sessions.json`, `session-unread.json`, `sessiond-owner.json`), and updates the session header (first line) of each `*.jsonl` so its `cwd` matches the new project path — pi matches sessions to projects by that header field. The conversation lines inside `*.jsonl` files are left untouched. The script is idempotent (safe to re-run, e.g. to finish a partially completed migration) and refuses to run against the agent's own live home.

## Godot & MCP tools

The image ships the Godot engine (headless), the `godot-mcp` MCP server, and the `pi-mcp-adapter` pi package as system-wide layers. On every boot, `pi-home-init.service` ingests the small per-home config into `/home/agent` (idempotent, never clobbers user edits):

- `~/.config/mcp/mcp.json` — default MCP config declaring the `godot` server (only if you haven't created your own)
- `~/.pi/agent/skills/godot/SKILL.md` — a skill describing the godot MCP tools (only if missing)
- `~/.pi/agent/settings.json` — merges the global `pi-mcp-adapter` package path into `packages` (idempotent)

In pi, discover and call the tools through the `mcp` proxy: `mcp({ "search": "godot" })`, then `mcp({ "tool": "godot_run_project", "args": { ... } })`. For tasks the MCP tools don't cover, use `godot --headless` directly (the wrapper adds `--headless` automatically when no display is present).

## Notes

- No automatic apt updates: systemd update timers are removed. Update by rebuilding the image.
- If `/home/agent` is mounted empty, a one-shot systemd service seeds it with a home skeleton (dotfiles, pi configs). The per-boot ingestion described above runs regardless, so upgraded containers with an existing home volume pick up new system-provided config without any downloads.
