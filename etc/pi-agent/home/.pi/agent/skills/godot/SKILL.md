---
name: godot
description: Use when working on Godot engine projects (project.godot, .tscn scenes, .gd scripts) — create/edit project files directly and run the engine headlessly with godot --headless to validate, import, run and export.
---

# Godot engine (headless, CLI-first)

Work on Godot projects with plain files + bash + the engine CLI. There is **no
Godot MCP server** in this image on purpose: scenes, scripts, resources and
settings are text files you write directly, and the engine itself is the only
validator you need.

- Engine binary: `/usr/local/bin/godot` (a wrapper around
  `/usr/local/lib/godot/godot` that auto-adds `--headless` when no display
  server is present, so plain `godot --path <project>` works headlessly).
- Installed version: check it with `godot --version` **at the start of a
  Godot task** — never assume it.
- Local official docs (version-matched): `/usr/local/share/godot-docs`.

## Read the local documentation first (source of truth)

This is the most important rule of this skill.

Your training knowledge of Godot is **not** the installed engine. The image
ships a recent Godot (see `godot --version`), and the API, node names,
signal/connection syntax, export preset options, renderer settings, resource
formats and CLI flags **do change between minor versions** (4.4 → 4.7 is not
the engine you memorised). Assuming you know the version you have installed is
the main source of wasted time here.

So:

1. **Before writing Godot-specific code or config, look it up locally.**
   `rg` the docs, read the matching `.rst`, *then* write the file. The docs are
   the version that is actually installed; they win over your memory.
2. **The moment something does not work** — a parse error, an unknown class or
   property, a signal that never fires, an export preset that fails, a node
   that is missing at runtime — **stop guessing**. Do not retry with variations.
   Go straight to the doc page for that class/feature and validate the exact
   name, signature, and requirements there. That is faster and much more
   reliable than trial and error.
3. Prefer the docs for *validation* of what you are about to type: class
   methods and properties (`classes/`), the feature tutorial
   (`tutorials/…`), and the CLI reference
   (`tutorials/editor/command_line_tutorial.rst`). If a doc page and your
   assumption disagree, the doc page is right.
4. If a search finds nothing, that is also information: the class or property
   may have been renamed, moved or removed in this version. Search the
   migration guides in `engine_details/development/` before improvising.

```bash
godot --version                                     # which engine is actually here
rg -il "topic" /usr/local/share/godot-docs          # find the relevant page(s)
rg -n "ClassName" /usr/local/share/godot-docs/classes/class_classname.rst
```

Docs layout:

- `index.rst` — master index of all sections
- `getting_started/` — first steps, project setup, scripting basics
- `tutorials/` — 2d, 3d, animation, shaders, physics, navigation, xr, …
  (plus `tutorials/editor/command_line_tutorial.rst`, the CLI reference)
- `classes/` — full API reference, one file per class, lowercased with a
  `class_` prefix (e.g. `classes/class_node3d.rst`)
- `engine_details/` — architecture, class notes, migration guides

## Workflow

1. `godot --version` (and note it for the whole task).
2. Create/modify the project as files: `project.godot`, `*.tscn` scenes,
   `*.gd` scripts, `export_presets.cfg`. Scenes and scripts are text — write
   them with the edit/write tools, following the class reference for property
   and node names.
3. Import/validate: `godot --headless --path <project> --import` (also imports
   new assets on first run).
4. Run and read the output: `godot --headless --path <project>` (stdout/stderr
   carries `print()`, engine errors, script errors and stack traces).
5. If it fails, read the error, then **look up the relevant class/feature in
   `/usr/local/share/godot-docs`** and fix the file accordingly.

```bash
godot --version                                             # installed engine
godot --path /path/to/project/project.godot --editor --quit # open once (imports)
godot --headless --path /path/to/project --import           # import assets, then quit
godot --headless --path /path/to/project                    # run the main scene
godot --headless --path /path/to/project res://scene.tscn   # run one scene
godot --headless --path /path/to/project -d                 # with command-line debugger
godot --headless --path /path/to/project -s res://tools/check.gd   # run a script
godot --headless --path /path/to/project -s res://tools/check.gd --check-only  # parse only
godot --headless --path /path/to/project --quit-after 10    # run N frames then exit
```

Useful notes (from `tutorials/editor/command_line_tutorial.rst` — verify there,
not here):

- Passing `project.godot` as the first argument always starts the **editor**;
  pass a scene path to run that scene instead.
- `-s/--script <script>` takes a **resource path relative to the project**
  (`res://…` or a bare name resolved as `res://<name>`), and the script must
  inherit from `SceneTree` or `MainLoop`.
- `--quit-after N` bounds the run so a game loop cannot hang the command; use
  it for any run you expect to terminate.
- Arguments after `--` are user args, read by the project with
  `OS.get_cmdline_user_args()`.
- Export output paths are relative to the directory containing
  `project.godot`, not to the current working directory.
- Never run `godot -e`/`--editor` expecting a GUI on this machine; use
  `--import` / `--quit` / `--quit-after` for headless editor work.

Run long or blocking runs with a timeout so a stuck game loop cannot hang the
session: `timeout 60 godot --headless --path <project> --quit-after 600`.

## Exporting releases (Linux / Windows)

Official export templates are installed system-wide at
`/usr/local/share/godot/export_templates/<version>/` (Linux x86/arm32 +
Windows x86) and are available to the `agent` user via a symlink created by
`init-agent` (`~/.local/share/godot/export_templates`).

A ready-to-use `export_presets.cfg` covering both platforms ships with this
skill: `~/.pi/agent/skills/godot/export_presets.cfg.example`. To export a
release:

1. `cp ~/.pi/agent/skills/godot/export_presets.cfg.example <project>/export_presets.cfg`
   and edit the `export_path` values (and preset names) as needed.
2. `mkdir -p <project>/build` (Godot requires the target's base directory to exist).
3. Export: `godot --headless --path <project> --export-release "Linux" build/linux`
   and `godot --headless --path <project> --export-release "Windows Desktop" build/windows.exe`.

Each export produces a native executable plus a `.pck` data file beside it.

If you write the cfg by hand, check the **installed** docs for the current
option names instead of relying on memory; the usual gotchas: `platform` must
be the exporter display name (`"Linux"`, `"Windows Desktop"` — not `"Windows"`),
each preset needs `binary_format/architecture` plus at least one texture format
(e.g. `texture_format/s3tc_bptc=true`) in its options section, and comments use
`;` (not `#`) — a `#` line breaks parsing of the whole file.
