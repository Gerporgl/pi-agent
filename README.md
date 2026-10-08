# podman-pi-agent

A minimal Ubuntu 26.04 container that runs the [pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) and [pi-web](https://www.npmjs.com/package/@jmfederico/pi-web) inside a full containerized sandbox.

The entire container project was coded mostly by the pi agent itself (which also runs within it by itself and edit its own container based on given instructions...). The model used (at the time of writing) is [ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF:IQ3_S](https://huggingface.co/ISTA-DASLab/Qwen3.8-27B-GSQ-RCO-GGUF) (mtp), running on a 16GB vram amdgpu (9060XT) and fitting a 64K context size at kv q8 (providing around ~20 tokens/sec). This is all hosted on a proxmox server running on different lxc nested containers. The llama.cpp inference engine is hosted using this sibling container project: [llama-lxc](https://github.com/Gerporgl/llama-lxc) which is also hosted on the same proxmox host in a separate lxc container, and passing the amdgpu. All of this running in unprivileged mode.

## Design

- **Base**: Ubuntu 26.04 with a minimal set of CLI tools the agent can use (python, uv, node.js, gcc, git, ripgrep, fd-find, build-essential, jq, yq, etc.).

  `ripgrep` and `fd-find` are installed on purpose: pi's `grep`/`find` tools search `PATH` for `rg` and `fd`/`fdfind` and otherwise download the binaries from GitHub into `~/.pi/agent/bin/` on first session start. With the apt packages present, no download ever happens (so the image also works with `PI_OFFLINE`/`pi --offline`). A `~/.pi/agent/bin/fd` downloaded by an older image takes precedence over the apt one; delete it if you want the packaged version.
- **Rust+Cargo**: Always the latest rust stable release, bundled with musl so the agent can build static binaries without any libc dependency
- **Godot**: the [Godot engine](https://godotengine.org) (headless-capable) is installed system-wide; the real binary lives at `/usr/local/lib/godot/godot` and `/usr/local/bin/godot` is a thin wrapper that auto-adds `--headless` when no display server is available, so plain `godot --path <project>` usage and CI work headlessly. It ships together with the official [Godot documentation](https://github.com/godotengine/godot-docs) (reStructuredText, version-matched to the engine) at `/usr/local/share/godot-docs`. Projects are created/edited as plain text files and driven through the CLI with bash: **no Godot MCP server is installed** (a `godot-mcp` server used to ship; it was removed after too many issues — CLI + headless mode proved more reliable).
- **Init**: full `systemd` as entrypoint (`/sbin/init`), with `pi-web` and `pi-web-sessiond` managed as systemd services. Works well on Proxmox LXC (full TTY console, clean shutdown) and in nested podman containers.
- **Users**: pi-agent and pi-web run as the unprivileged `agent` user. `openssh-server` is installed for administrative SSH access (as `root`, running on **port 2223**, you'll need to mount your authorized_keys, or set a root password, see run.sh code).
- **Persistence**: agent/web state lives under `/home/agent`, which is intended to be bind-mounted (see `home-data/` for a reference layout). Put your own `~/.pi/agent/models.json` (and other pi configs) in that mounted volume.
  - Benefit: Base image can safely be updated regularly without losing anything the agent created inside its home folder, which is the only place it can write.

## Building

```bash
./build.sh            # builds every stage + pi-agent:latest (podman if available, else docker)
./build_and_run.sh    # build + local run
```

`build.sh` builds **one stage at a time** (`--target <stage> -t pi-agent-<stage>:latest`),
so each stage is a real tagged image in the local store — see "Build stages and
cache reuse" below.
The image tag encodes all component versions (e.g. `node-24-pi-0.86.1-pi-web-1.202609.0-rust-1.98.1-godot-4.7.2`) and is also embedded in the image itself as the `org.opencontainers.image.version` OCI label, so it can be read at runtime without knowing the tag:

```bash
podman image inspect --format '{{index .Labels "org.opencontainers.image.version"}}' pi-agent:latest
```

### Vendored pi-web build (terminal polling fix)

`pi-web` is **not** installed from the npm registry. The `apps` stage installs
the vendored tarball `vendor/pi-web/jmfederico-pi-web-1.202610.1.tgz`, a build
of the fork branch `fix/terminal-requested-terminal-reload-once`
(`github.com/Gerporgl/pi-web`) which fixes the terminal list polling storm that
made `pi-web-sessiond` burn CPU. `build.sh` verifies the tarball's sha256, reads
its version from `package/package.json` (so tag, `PI_WEB_VERSION` and the
installed code always agree), and the Dockerfile fails the build if the tarball
version mismatches the build arg or if the fix is missing from the installed
copy.

Why a vendored tarball: the tarball is `npm pack` output, so it contains the
built `dist/` (`npm i -g github:Gerporgl/pi-web#branch` installs **without**
`dist/` and is broken). Never hotpatch `/usr/lib/node_modules/@jmfederico/pi-web/dist/`
in a running container instead: the plugin package revision is a sha256 over the
whole package checked by both the gateway and the session daemon, and the
terminal plugin is a required manifest entry — editing one file makes
`/api/plugins` return 500 and breaks the whole UI.

To update the fork build, re-pack it and change filename, both hashes
(`build.sh` + this section), the `COPY` line and the `PI_WEB_VERSION` default
together:

```bash
cd /home/agent/github-pi-web/pi-web && git checkout fix/terminal-requested-terminal-reload-once && git pull
npm ci && npm run verify
npm pack --pack-destination ../tarball        # runs prepack -> full build
cp ../tarball/jmfederico-pi-web-<version>.tgz <repo>/vendor/pi-web/ && sha256sum <repo>/vendor/pi-web/*.tgz
```

Once the fix lands in the published upstream package, revert to the registry
install in `build.sh` + `apps` and delete `vendor/pi-web/`.

### Build stages and cache reuse

The Dockerfile is a **multi-stage build**: each component is its own stage and
declares *only* the build args it consumes, so bumping one component rebuilds
only that stage and reuses the rest from the local layer cache.

| Stage (`--target`) | Tagged image | Contents | Args it declares | Changes |
|---|---|---|---|---|
| `base` | `pi-agent-base:latest` | apt layer, user setup, Node.js runtime | `NODE_MAJOR` | rare |
| `rust` | `pi-agent-rust:latest` | Rust toolchain + musl target | `RUST_VERSION`, `TARGET_ARCH` | rare |
| `godot` | `pi-agent-godot:latest` | engine + export templates + docs | `GODOT_VERSION`, `TARGET_ARCH` | rare |
| `apps` | `pi-agent-apps:latest` | pi (npm) + pi-web (vendored fork tarball) + npm bin list | `PI_VERSION`, `PI_WEB_VERSION`, `TARGET_ARCH` | frequent |
| `runtime` | `pi-agent-runtime:latest` | assembly (`COPY --from=`) | — | — |
| `final` | `pi-agent:latest` + `pi-agent:<version tag>` | service files, config, OCI label | `IMAGE_VERSION` | every build |

Each stage is built and tagged separately, and downstream stages refer to the
**built images** (`FROM pi-agent-base:latest`, `COPY --from=pi-agent-rust:latest`,
…) instead of the in-file stage names — the same pattern as the `llama-lxc`
project. Because every intermediate stage carries a real tag, `podman image
prune` / `docker image prune` cannot throw away the layers of a component that
was not rebuilt: pruning untagged leftovers keeps the cache intact, and the
next build reuses those tagged images. `pi-agent-runtime:latest` is the
assembled toolchain before the service/config layers, `pi-agent:latest` (plus
the version tag) is the final image.

Two container-build rules drive this layout:

1. Layer caching is **linear**: a changed instruction busts that layer and
everything after it. That is why the assembly stage starts from `godot` and
copies the rarely-updated component first (`rust`) and the frequent one last
(`apps`), and why the ever-changing `IMAGE_VERSION` label is quarantined in the
last stage.
2. **podman/buildah busts every layer of a stage** when any build arg
*declared in that stage* changes — even layers above it, even if unused there.
So version args must never be declared globally at the top of the file.

Measured on a local podman 5.7 build (full cold build ≈ 6 min / 3.95 GB image):
a pi version bump re-runs only `apps` + assembly + final — the apt,
Node, Rust (450 MB download) and Godot (1.36 GB download) layers all come from
cache, ≈ 24 s.

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

## Godot (headless CLI)

The image ships the Godot engine (headless), the official Godot export templates (Linux x86/arm32 + Windows x86) and the official Godot documentation (reStructuredText, version-matched to the engine) at `/usr/local/share/godot-docs`, as system-wide layers. Godot work is done with plain files + bash + `godot --headless`; **no Godot MCP server is installed** (the `godot-mcp` package and its default `~/.pi/agent/mcp.json` were removed — too many issues, the CLI/headless path is more reliable). If you want MCP servers, create your own `~/.pi/agent/mcp.json`; nothing is ingested there anymore.

On every boot, `pi-home-init.service` ingests the small per-home config into `/home/agent`. The godot skill files are system-managed and always synced from the image (so image upgrades reach pre-existing homes; customise in your own skill folder instead of editing them); everything else is only ingested if missing, so user edits are never clobbered:

- `~/.pi/agent/skills/godot/SKILL.md` — a skill describing the headless CLI workflow and the local documentation (always synced from the image)
- `~/.pi/agent/skills/godot/export_presets.cfg.example` — a ready-to-use preset file for headless Linux/Windows exports (always synced from the image)
- `~/.local/share/godot/export_templates` — symlink to the system-wide export templates (only if you haven't provided your own)

The godot `SKILL.md` (synced into the agent home) tells the agent where the local documentation lives and how to navigate it: `index.rst` is the master index, `tutorials/` holds the topic guides (including the command-line reference), and `classes/` is the full API reference (one `.rst` per class). The agent typically greps it with `rg` and reads the matching pages.

The skill makes the **local documentation the source of truth**: the agent must check `godot --version`, look up classes and CLI flags in `/usr/local/share/godot-docs` before writing Godot-specific code, and must go back to the docs immediately when something does not work instead of retrying from memory — training knowledge of another Godot version (4.4, 4.3, …) is not the installed engine and its API differs.

Because the official export templates are installed, Linux and Windows Desktop releases can be exported headlessly from the CLI: copy `~/.pi/agent/skills/godot/export_presets.cfg.example` into the project as `export_presets.cfg` (edit the `export_path` values), then `godot --headless --path <project> --export-release "Linux" build/linux` / `--export-release "Windows Desktop" build/windows.exe`.

## Notes

- **Daily pi-web restart**: `pi-web-restart.timer` fires at **06:00 container local time** and runs `pi-web-restart.service`, which restarts `pi-web-sessiond.service` then `pi-web.service`. This is a temporary workaround for upstream pi-web issues (terminal URL spamming and MCP server instantiation) until they are fixed upstream. The time is whatever the container's local time is — `/etc/localtime` is normally bind-mounted by the host, so it follows the host timezone; without it the container is UTC and the restart happens at 06:00 UTC. Nothing timezone-related is baked into the image. `Persistent=true` means a container that was not running at 06:00 does the restart once at boot instead of waiting a full day. Turn it off with `systemctl disable --now pi-web-restart.timer` inside the container (or remove the two `systemd/pi-web-restart.*` files and the `COPY`/`enable` lines in the Dockerfile once the upstream fixes land).
- No automatic apt updates: systemd update timers are removed. Update by rebuilding the image.
- If `/home/agent` is mounted empty, a one-shot systemd service seeds it with a home skeleton (dotfiles, pi configs). The per-boot ingestion described above runs regardless, so upgraded containers with an existing home volume pick up new system-provided config without any downloads.
