---
name: godot
description: Use when working on Godot engine projects (project.godot, .tscn scenes, .gd scripts) — run projects headlessly, capture debug output, manage scenes and nodes.
---

# Godot engine (headless)

The Godot engine binary is at `/usr/local/bin/godot` (headless-capable). A `godot` MCP server is available as deferred tools in the `mcp__godot` namespace. They load lazily — `tool_search` exposes them only when you actually need them.

## Workflow

1. Discover and load the godot MCP tools: `tool_search({ "query": "godot" })` — this exposes them as `mcp__godot__*` tools for the next step.
2. Call a tool directly: `mcp__godot__run_project({ "projectPath": "/path/to/project" })`

Tool names are namespaced as `mcp__godot__<tool>` (e.g. `mcp__godot__run_project`).

## Tools (server: godot)

- `run_project` — run a project headlessly and capture output (params: `projectPath`, optional `scene`)
- `get_debug_output` — read console output and errors from the running/last run
- `stop_project` — stop the currently running project
- `launch_editor` — launch the Godot editor for a project (params: `projectPath`)
- `get_godot_version` — print the installed Godot version
- `list_projects` — find Godot projects under a directory
- `get_project_info` — retrieve metadata about a project
- `create_scene` / `add_node` / `load_sprite` / `save_scene` — scene and node manipulation
- `export_mesh_library` — export a 3D scene as a MeshLibrary resource (GridMap)
- `get_uid` / `update_project_uids` — resource UID management (Godot 4.4+)

Note: `/usr/local/bin/godot` is a wrapper that auto-adds `--headless` when no display server is available, so plain `godot --path <project>` works on headless machines (and `run_project` works through the MCP server).

## Fallback: direct CLI

For tasks the MCP tools do not cover (import, export templates, custom flags), use the binary directly:

```bash
godot --headless --path /path/to/project --quit          # validate / import a project
godot --headless --path /path/to/project --export-release <preset> out.pck
godot --version
```

## Official documentation (local)

The complete official Godot documentation, matching the installed engine version, is at `/usr/local/share/godot-docs` (reStructuredText, plain text — no build needed).

Layout:
- `index.rst` — master index of all sections
- `getting_started/` — first steps, project setup, scripting basics
- `tutorials/` — 2d, 3d, animation, shaders, physics, navigation, xr, ...
- `classes/` — full API reference, one file per class, lowercased with a `class_` prefix (e.g. `classes/class_node3d.rst`)
- `engine_details/` — architecture, class notes, migration guides

How to use it:

```bash
rg -il "topic" /usr/local/share/godot-docs    # find the relevant page(s)
```

then read the matching `.rst` file(s). For a specific class, go directly to `classes/class_<lowercase_name>.rst` (e.g. `class_node3d.rst`).

## Exporting releases (Linux / Windows)

Official export templates are installed system-wide at `/usr/local/share/godot/export_templates/<version>/` (Linux x86/arm32 + Windows x86) and are available to the `agent` user via a symlink created by `init-agent` (`~/.local/share/godot/export_templates`).

A ready-to-use `export_presets.cfg` covering both platforms ships with this skill: `~/.pi/agent/skills/godot/export_presets.cfg.example`. To export a release:

1. `cp ~/.pi/agent/skills/godot/export_presets.cfg.example <project>/export_presets.cfg` and edit the `export_path` values (and preset names) as needed.
2. `mkdir -p <project>/build` (Godot requires the target's base directory to exist).
3. Export: `godot --headless --path <project> --export-release "Linux" build/linux` and `godot --headless --path <project> --export-release "Windows Desktop" build/windows.exe`.

Each export produces a native executable plus a `.pck` data file beside it.

If you write the cfg by hand, note the gotchas: `platform` must be the exporter display name (`"Linux"`, `"Windows Desktop"` — not `"Windows"`), each preset needs `binary_format/architecture` plus at least one texture format (e.g. `texture_format/s3tc_bptc=true`) in its options section, and comments use `;` (not `#`) — a `#` line breaks parsing of the whole file.
