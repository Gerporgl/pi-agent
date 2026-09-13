#!/bin/bash

podman=$(podman -v 2>/dev/null | grep -c -i podman)
if [ "$podman" == "1" ]; then
	command=podman
else
	command=docker
	echo "You are using docker, this container has been tested mostly with podman"
fi

DOCKER_BUILDKIT=1 $command build -t pi-agent:latest .
