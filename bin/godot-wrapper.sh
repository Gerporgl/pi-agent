#!/bin/bash
# Godot wrapper: auto-adds --headless when no display server is available, so
# headless usage (MCP run_project, CI, import/export) works on machines
# without X11/Wayland or a GPU. With a display present, the engine runs
# normally (editor, live preview).
#
# The real engine binary lives at /usr/local/lib/godot/godot.
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    exec /usr/local/lib/godot/godot --headless "$@"
fi
exec /usr/local/lib/godot/godot "$@"
