#!/bin/bash

if [ -z "$(ls -A /home/agent | grep -v lost+found)" ]; then
    echo "Empty host volume detected. Seeding skeleton files..."
    cp -a /opt/agent-home-skeleton/. /home/agent/
else
    echo "Agent home folder already initialized."
fi

# Ingest the system-provided pi config into the agent home (idempotent, every
# boot), so pre-existing home volumes pick up config on image upgrades. The
# heavy pieces (godot binary, docs, export templates, Playwright browsers) are
# image layers, and no mcp.json is shipped: create ~/.pi/agent/mcp.json yourself
# if you want MCP.
STUB=/etc/pi-agent/home

# System-managed skill files are synced on every boot (rewritten only when the
# content differs), so image upgrades reach pre-existing home volumes.
# Customise in your own skill folder instead.
for skill in "$STUB"/.pi/agent/skills/*/; do
    name=$(basename "$skill")
    mkdir -p "/home/agent/.pi/agent/skills/$name"
    for f in "$skill"*; do
        target="/home/agent/.pi/agent/skills/$name/$(basename "$f")"
        if ! cmp -s "$f" "$target"; then
            cp "$f" "$target"
            echo "Synced $name skill file: $(basename "$f")."
        fi
    done
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
