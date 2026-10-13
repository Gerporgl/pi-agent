#!/bin/bash

if [ -z "$(ls -A /home/agent | grep -v lost+found)" ]; then
    echo "Empty host volume detected. Seeding skeleton files..."
    cp -a /opt/agent-home-skeleton/. /home/agent/
else
    echo "Agent home folder already initialized."
fi

# Ingest the system-provided pi config into the agent home (idempotent, every
# boot), so pre-existing home volumes pick up config on image upgrades. The
# heavy pieces (godot binary, docs, export templates) are image layers, and no
# mcp.json is shipped: create ~/.pi/agent/mcp.json yourself if you want MCP.
STUB=/etc/pi-agent/home

# Godot skill files are system-managed: synced on every boot (rewritten only
# when content differs). Customise in your own skill folder instead.
mkdir -p /home/agent/.pi/agent/skills/godot
for f in SKILL.md export_presets.cfg.example; do
    if ! cmp -s "$STUB/.pi/agent/skills/godot/$f" "/home/agent/.pi/agent/skills/godot/$f"; then
        cp "$STUB/.pi/agent/skills/godot/$f" "/home/agent/.pi/agent/skills/godot/$f"
        echo "Synced godot skill file: $f."
    fi
done

# Make the system-wide export templates visible to the agent user, unless it
# already has its own.
if [ ! -e /home/agent/.local/share/godot/export_templates ]; then
    mkdir -p /home/agent/.local/share/godot
    ln -s /usr/local/share/godot/export_templates /home/agent/.local/share/godot/export_templates
    echo "Linked Godot export templates for agent user."
fi

chown -R agent:agent /home/agent

if [ -f  /root/.ssh/authorized_keys_host ]; then
    echo "Copying host ssh public key to root user"
    cp /root/.ssh/authorized_keys_host /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
else
    echo "No host ssh public key found, skipping..."
fi
