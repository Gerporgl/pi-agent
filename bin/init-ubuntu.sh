#!/bin/bash

if [ -z "$(ls -A /home/ubuntu | grep -v lost+found)" ]; then
    echo "Empty host volume detected. Seeding skeleton files..."
    cp -a /opt/ubuntu_skeleton/. /home/ubuntu/
else
    echo "Ubuntu home folder already initilized."
fi

chown -R ubuntu:ubuntu /home/ubuntu

if [ -f  /root/.ssh/authorized_keys_host ]; then
    echo "Copying host ssh public key to root user"
    cp /root/.ssh/authorized_keys_host /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
else
    echo "No host ssh public key found, skipping..."
fi
