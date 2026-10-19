# podman-pi-agent

A minimal Ubuntu 26.04 container that runs the [pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) and [pi-web](https://www.npmjs.com/package/@jmfederico/pi-web) inside a full containerized sandbox.

## Design

- **Base**: Ubuntu 26.04 with the CLI tools the agent uses (python + uv, Node.js, gcc, git, ripgrep, fd, build-essential, jq, yq, podman…).
- **Rust + Cargo**: latest stable, with the musl target so the agent can build fully static binaries.
- **Godot**: engine installed system-wide (real binary at `/usr/local/lib/godot/godot`, `/usr/local/bin/godot` adds `--headless` when there is no display), plus official export templates and the official docs at `/usr/local/share/godot-docs`. Godot work is plain files + `godot --headless`; **no Godot MCP server is installed**.
- **Playwright**: `playwright` + `@playwright/test` globally (`playwright` CLI) with **Firefox** and the **Chromium headless shell** preinstalled in `/usr/local/share/ms-playwright` — screenshots, PDFs, scraping, JS-rendered pages and e2e tests work offline, nothing is downloaded at runtime. Headless only (no display, no WebKit).
- **Init**: full `systemd` as entrypoint (`/sbin/init`); `pi-web` and `pi-web-sessiond` run as services. Works on Proxmox LXC (tty console, clean shutdown) and nested podman containers.
- **Users**: everything runs as the unprivileged `agent` user. `openssh-server` gives root admin SSH on **port 2223** (mount an authorized_keys or set a root password, see `run.sh`).
- **Persistence**: all state lives under `/home/agent`, meant to be bind-mounted — so the base image can be replaced at any time without losing anything the agent wrote. Put your own `~/.pi/agent/models.json` and other pi configs in that volume.

## Building

```bash
./build.sh            # podman if available, else docker; CT_TOOL env var overrides
./build_and_run.sh    # build + local run
```

`build.sh` resolves the latest stable Node major, pi, pi-web, Rust, Godot and Playwright versions, then builds **one stage at a time** so each component is cached separately:

| Stage | Image tag | Build args | Changes |
|---|---|---|---|
| `base` | `pi-agent-base:latest` | `NODE_MAJOR` | rare |
| `rust` | `pi-agent-rust:latest` | `RUST_VERSION`, `TARGET_ARCH` | rare |
| `godot` | `pi-agent-godot:latest` | `GODOT_VERSION`, `TARGET_ARCH` | rare |
| `playwright` | `pi-agent-playwright:latest` (on top of `godot`) | `PLAYWRIGHT_VERSION` | rare |
| `apps` | `pi-agent-apps:latest` | `PI_VERSION`, `PI_WEB_VERSION`, `TARGET_ARCH` | frequent |
| `runtime` | `pi-agent-runtime:latest` | — | assembly |
| `final` | `pi-agent:latest` + version tag | `IMAGE_VERSION` | every build |

The version tag (`node-<major>-pi-<ver>-pi-web-<ver>-rust-<ver>-godot-<ver>-pw-<ver>`) is also stored as the `org.opencontainers.image.version` OCI label:

```bash
podman image inspect --format '{{index .Labels "org.opencontainers.image.version"}}' pi-agent:latest
```

Cold build ≈ 10 min / 5 GB (browsers and their system libraries add ≈ 0.6 GB); a pi or pi-web bump then reuses the apt, Node, Rust, Godot and Playwright layers (≈ 30 s).

## Running

```bash
./run.sh              # example: creates the container, sets a root password,
                      # copies your ssh key for root, then attaches
./run_local.sh        # same, against the locally built image
```

| Option | Purpose |
|---|---|
| `-v ./home-data:/home/agent` | persistent agent + pi-web state |
| `--userns=keep-id` | keep host UID so mounted files are owned correctly |
| `-p 2223:2223` | SSH (root admin) |
| `-p 8504:8504` | pi-web web UI |

`run.sh` is only an example — quadlets and Proxmox LXC work equally well. Without a root password there is no way in: that is the intended default.

## Migrating an old home folder (ubuntu → agent)

If your home volume predates the `agent` user:

```bash
./migrate.sh ./pi-agent-home      # --dry-run to preview
```

It renames the pi session directories, rewrites `/home/ubuntu` → `/home/agent` in the pi/pi-web state files, and fixes each session's `cwd` header. Idempotent, and it refuses to run against the agent's own live home.

## Godot

The image ships the engine, the official export templates (Linux x86/arm32 + Windows x86) and the official docs as system-wide layers — nothing is downloaded at runtime. On every boot `pi-home-init.service` ingests a small per-home config into `/home/agent`: the system-managed skills (always synced from the image, so customise in your own skill folder) and a symlink to the export templates. The godot skill points the agent at the local docs (`index.rst`, `tutorials/`, `classes/`) and makes it check the installed engine version instead of relying on training knowledge. To export: copy `export_presets.cfg.example` to `export_presets.cfg` in the project, then `godot --headless --path <project> --export-release "Linux" build/linux`.

## Playwright

Browsers are image layers, so a session can screenshot, print to PDF, scrape or run e2e tests with no download and no network for the tooling itself. Installed: the `playwright` and `@playwright/test` npm packages (global) plus **Firefox** and the **Chromium headless shell** under `/usr/local/share/ms-playwright` (`PLAYWRIGHT_BROWSERS_PATH` is set in the image config, in `/etc/environment` and in both pi-web units). There is no display, so only headless runs work — and no WebKit.

```bash
playwright --version
playwright screenshot --browser firefox --full-page https://example.com shot.png
cd /path/to/project && playwright-link    # link the global packages into node_modules
npx playwright test                       # chromium + firefox projects
```

The `playwright` skill (`~/.pi/agent/skills/playwright/SKILL.md`) tells the agent the same: never run `playwright install`, never `npm install playwright` in a project (use `playwright-link`), headless only.

## Notes

- No automatic apt updates (timers removed) — update by rebuilding the image.
- If `/home/agent` is mounted empty it gets seeded from a home skeleton; the per-boot config ingest runs either way.
- pi-web config is baked read-only at `/etc/pi-web/config.js` (edit `etc/pi-web/config.js` and rebuild). By default agents cannot spawn extra sessions or subsessions, since they cost context — see the [pi-web config reference](https://pi-web.dev/config) for the keys.
