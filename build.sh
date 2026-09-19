#!/bin/bash

set -e

# Container tool: podman by default, docker otherwise; CT_TOOL overrides
command=docker
if command -v podman >/dev/null 2>&1; then
	command=podman
fi
if [ -n "${CT_TOOL:-}" ]; then
	command=$CT_TOOL
fi
echo "Using container tool: $command"

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

# Current stable Rust version (e.g. 1.98.1)
rust_version=$(curl -fsS https://static.rust-lang.org/dist/channel-rust-stable.toml \
	| awk '/^\[pkg\.rust\]/{f=1; next} f && /^version =/{print; exit}' \
	| cut -d'"' -f2 | cut -d' ' -f1)

# Target triple matching the architecture we are building for
case "$(uname -m)" in
	x86_64)  target_arch="x86_64-unknown-linux-gnu" ;;
	aarch64) target_arch="aarch64-unknown-linux-gnu" ;;
	*) echo "ERROR: unsupported architecture: $(uname -m)"; exit 1 ;;
esac

if [[ ! "$node_major" =~ ^[0-9]+$ ]] || [[ -z "$pi_version" || "$pi_version" == "null" ]] || [[ -z "$pi_web_version" || "$pi_web_version" == "null" ]] || [[ ! "$rust_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "ERROR: Unable to get the latest versions! (node_major=$node_major pi_version=$pi_version pi_web_version=$pi_web_version rust_version=$rust_version)"
	exit 1
fi

echo "node_major=$node_major"
echo "pi_version=$pi_version"
echo "pi_web_version=$pi_web_version"
echo "rust_version=$rust_version"
echo "target_arch=$target_arch"

# Store the versions and the tag in .txt files for later use
echo "$node_major" > node_version.txt
echo "$pi_version" > pi_version.txt
echo "$pi_web_version" > pi_web_version.txt
echo "$rust_version" > rust_version.txt
tag="node-${node_major}-pi-${pi_version}-pi-web-${pi_web_version}-rust-${rust_version}"
echo "$tag" > pi_agent_tag.txt
echo "tag=pi-agent:$tag"

# Build args only change when one of the components was updated,
# so cached layers are reused otherwise.
DOCKER_BUILDKIT=1 $command build \
	--build-arg NODE_MAJOR="$node_major" \
	--build-arg PI_VERSION="$pi_version" \
	--build-arg PI_WEB_VERSION="$pi_web_version" \
	--build-arg RUST_VERSION="$rust_version" \
	--build-arg TARGET_ARCH="$target_arch" \
	-t pi-agent:latest \
	-t "pi-agent:$tag" .
