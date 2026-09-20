---
name: godot
description: Use when working on Godot engine projects (project.godot, .tscn scenes, .gd scripts) — run projects headlessly, capture debug output, manage scenes and nodes.
---

# Godot engine (headless)

The Godot engine binary is at `/usr/local/bin/godot` (headless-capable). A `godot` MCP server is available through the `mcp` proxy tool (provided by the pi-mcp-adapter package). It starts lazily — only when you actually call one of its tools.

## Workflow

1. Discover the exact tool schemas: `mcp({ "search": "godot" })`
2. Call a tool: `mcp({ "tool": "godot_run_project", "args": { "projectPath": "/path/to/project" } })`

Tool names are prefixed with the server name (`godot_`).

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
