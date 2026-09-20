#!/bin/bash

if [ -z "$(ls -A /home/agent | grep -v lost+found)" ]; then
    echo "Empty host volume detected. Seeding skeleton files..."
    cp -a /opt/agent-home-skeleton/. /home/agent/
else
    echo "Agent home folder already initialized."
fi

chown -R agent:agent /home/agent

if [ -f  /root/.ssh/authorized_keys_host ]; then
    echo "Copying host ssh public key to root user"
    cp /root/.ssh/authorized_keys_host /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
else
    echo "No host ssh public key found, skipping..."
fi
