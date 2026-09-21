#!/bin/bash

if [ -z "$(ls -A /home/agent | grep -v lost+found)" ]; then
    echo "Empty host volume detected. Seeding skeleton files..."
    cp -a /opt/agent-home-skeleton/. /home/agent/
else
    echo "Agent home folder already initialized."
fi

# Ingest the system-provided pi config into the agent home (idempotent, every
# boot). The heavy pieces live in system-wide image layers (godot binary,
# global npm pi-mcp-adapter package, global godot-mcp bin); only these small
# files are ingested per home, so upgraded containers with a pre-existing
# home volume need no downloads at runtime.
STUB=/etc/pi-agent/home

# Default MCP config (godot server). Only ingested if the user has not
# created their own, so user edits are never clobbered on upgrades.
if [ ! -f /home/agent/.config/mcp/mcp.json ]; then
    mkdir -p /home/agent/.config/mcp
    cp "$STUB/.config/mcp/mcp.json" /home/agent/.config/mcp/mcp.json
    echo "Ingested default MCP config."
fi

# Godot skill. Only ingested if missing.
if [ ! -f /home/agent/.pi/agent/skills/godot/SKILL.md ]; then
    mkdir -p /home/agent/.pi/agent/skills/godot
    cp "$STUB/.pi/agent/skills/godot/SKILL.md" /home/agent/.pi/agent/skills/godot/SKILL.md
    echo "Ingested godot skill."
fi

# Reference export_presets.cfg (headless Linux/Windows exports). Only
# ingested if missing, so upgraded homes pick it up without clobbering.
if [ ! -f /home/agent/.pi/agent/skills/godot/export_presets.cfg.example ]; then
    mkdir -p /home/agent/.pi/agent/skills/godot
    cp "$STUB/.pi/agent/skills/godot/export_presets.cfg.example" /home/agent/.pi/agent/skills/godot/export_presets.cfg.example
    echo "Ingested godot export_presets.cfg example."
fi

# Godot export templates: make the system-wide templates available to the
# agent user (Godot looks in ~/.local/share/godot/export_templates/<ver>/).
# Symlink only if the user has not provided their own templates.
if [ ! -e /home/agent/.local/share/godot/export_templates ]; then
    mkdir -p /home/agent/.local/share/godot
    ln -s /usr/local/share/godot/export_templates /home/agent/.local/share/godot/export_templates
    echo "Linked Godot export templates for agent user."
fi

# Enable the system-wide pi-mcp-adapter package in the user's pi settings
# (idempotent merge; creates the settings file if it does not exist yet).
SETTINGS=/home/agent/.pi/agent/settings.json
ADAPTER_PKG=/usr/lib/node_modules/pi-mcp-adapter
mkdir -p /home/agent/.pi/agent
if [ ! -s "$SETTINGS" ]; then
    printf '{\n  "packages": [\n    "%s"\n  ]\n}\n' "$ADAPTER_PKG" > "$SETTINGS"
    echo "Created pi settings with pi-mcp-adapter package."
else
    jq --arg pkg "$ADAPTER_PKG" \
        '.packages = ((.packages // []) + (if ((.packages // []) | index($pkg)) then [] else [$pkg] end))' \
        "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    echo "Ensured pi-mcp-adapter package in pi settings."
fi

chown -R agent:agent /home/agent

if [ -f  /root/.ssh/authorized_keys_host ]; then
    echo "Copying host ssh public key to root user"
    cp /root/.ssh/authorized_keys_host /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
else
    echo "No host ssh public key found, skipping..."
fi
