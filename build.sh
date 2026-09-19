#!/bin/bash

set -e

podman=$(podman -v 2>/dev/null | grep -c -i podman)
if [ "$podman" == "1" ]; then
	command=podman
else
	command=docker
	echo "You are using docker, this container has been tested mostly with podman"
fi

# --- Dynamically fetch the latest versions ---

# Major version of the current latest stable LTS Node.js release (e.g. 24)
node_major=$(curl -fsS https://nodejs.org/dist/index.json \
	| jq -r '[.[] | select(.lts != false)][0].version' \
	| sed 's/^v//' | cut -d. -f1)

# Latest published versions of the npm packages
pi_version=$(curl -fsS "https://registry.npmjs.org/@earendil-works%2Fpi-coding-agent" \
	| jq -r '."dist-tags".latest')
pi_web_version=$(curl -fsS "https://registry.npmjs.org/@jmfederico%2Fpi-web" \
	| jq -r '."dist-tags".latest')

if [[ ! "$node_major" =~ ^[0-9]+$ ]] || [[ -z "$pi_version" || "$pi_version" == "null" ]] || [[ -z "$pi_web_version" || "$pi_web_version" == "null" ]]; then
	echo "ERROR: Unable to get the latest versions! (node_major=$node_major pi_version=$pi_version pi_web_version=$pi_web_version)"
	exit 1
fi

echo "node_major=$node_major"
echo "pi_version=$pi_version"
echo "pi_web_version=$pi_web_version"

# Store the versions and the full tag in .txt files for later use
echo "$node_major" > node_version.txt
echo "$pi_version" > pi_version.txt
echo "$pi_web_version" > pi_web_version.txt
tag="pi-agent:node-${node_major}-pi-${pi_version}-pi-web-${pi_web_version}"
echo "$tag" > pi_agent_tag.txt
echo "tag=$tag"

# Build args only change when one of the 3 components was updated,
# so cached layers are reused otherwise.
DOCKER_BUILDKIT=1 $command build \
	--build-arg NODE_MAJOR="$node_major" \
	--build-arg PI_VERSION="$pi_version" \
	--build-arg PI_WEB_VERSION="$pi_web_version" \
	-t pi-agent:latest \
	-t "$tag" .
