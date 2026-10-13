#!/bin/bash
# Godot wrapper: adds --headless when there is no display server, so CLI usage
# works headlessly while the editor still runs normally with a display present.
# Real binary: /usr/local/lib/godot/godot
if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    exec /usr/local/lib/godot/godot --headless "$@"
fi
exec /usr/local/lib/godot/godot "$@"
