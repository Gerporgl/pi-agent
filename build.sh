#!/bin/bash

set -e

# Options:
#   --build-ghcr  skip the build if the tag already exists on ghcr.io
#                 (deletes the version .txt files so callers detect the skip)
#   --force       with --build-ghcr, build anyway
BUILD_GHCR=0
FORCE=0
for arg in "$@"; do
	case "$arg" in
		--build-ghcr) BUILD_GHCR=1 ;;
		--force) FORCE=1 ;;
		*) echo "ERROR: unknown option: $arg (usage: ./build.sh [--build-ghcr] [--force])"; exit 1 ;;
	esac
done

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

# Major version of the latest stable LTS Node.js release (e.g. 24)
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

# Latest stable Godot release (GitHub tags the newest stable as "latest")
godot_version=$(curl -fsS https://api.github.com/repos/godotengine/godot/releases/latest \
	| jq -r .tag_name | sed 's/-stable$//')

# Latest published Playwright version (@playwright/test is kept in step with it)
playwright_version=$(curl -fsS "https://registry.npmjs.org/playwright" \
	| jq -r '."dist-tags".latest')

# Target triple matching the architecture we are building for
case "$(uname -m)" in
	x86_64)  target_arch="x86_64-unknown-linux-gnu" ;;
	aarch64) target_arch="aarch64-unknown-linux-gnu" ;;
	*) echo "ERROR: unsupported architecture: $(uname -m)"; exit 1 ;;
esac

if [[ ! "$node_major" =~ ^[0-9]+$ ]] || [[ -z "$pi_version" || "$pi_version" == "null" ]] || [[ -z "$pi_web_version" || "$pi_web_version" == "null" ]] || [[ ! "$rust_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$godot_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$playwright_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "ERROR: Unable to get the latest versions! (node_major=$node_major pi_version=$pi_version pi_web_version=$pi_web_version rust_version=$rust_version godot_version=$godot_version playwright_version=$playwright_version)"
	exit 1
fi

echo "node_major=$node_major"
echo "pi_version=$pi_version"
echo "pi_web_version=$pi_web_version"
echo "rust_version=$rust_version"
echo "godot_version=$godot_version"
echo "playwright_version=$playwright_version"
echo "target_arch=$target_arch"

tag="node-${node_major}-pi-${pi_version}-pi-web-${pi_web_version}-rust-${rust_version}-godot-${godot_version}-pw-${playwright_version}"
echo "tag=pi-agent:$tag"

# Never re-push a same-tag image with different content: skip the build when
# this exact tag is already published on ghcr.io
if [ "$BUILD_GHCR" == "1" ] && [ "$FORCE" != "1" ]; then
	# ghcr.io package owner, from the git origin remote
	owner=$(git remote get-url origin 2>/dev/null \
		| sed -E 's|^git@github\.com:|https://github.com/|' \
		| sed -E 's|https?://github\.com/([^/]+)/.*$|\1|')
	if [ -z "$owner" ]; then
		echo "ERROR: cannot determine ghcr.io owner from git origin remote"
		exit 1
	fi
	owner=$(echo "$owner" | tr 'A-Z' 'a-z')
	token=$(curl -fsS "https://ghcr.io/token?scope=repository:$owner/pi-agent:pull" | jq -r .token)
	if curl -fsS -o /dev/null -H "Authorization: Bearer $token" \
			 -H "Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json" \
			 "https://ghcr.io/v2/$owner/pi-agent/manifests/$tag"; then
		echo "Tag ghcr.io/$owner/pi-agent:$tag already exists on ghcr.io, skipping build"
		rm -f node_version.txt pi_version.txt pi_web_version.txt rust_version.txt godot_version.txt playwright_version.txt pi_agent_tag.txt
		exit 0
	fi
fi

# Store the versions and the tag in .txt files for later use
echo "$node_major" > node_version.txt
echo "$pi_version" > pi_version.txt
echo "$pi_web_version" > pi_web_version.txt
echo "$rust_version" > rust_version.txt
echo "$godot_version" > godot_version.txt
echo "$playwright_version" > playwright_version.txt
echo "$tag" > pi_agent_tag.txt

# --- Build one stage at a time, each tagged :latest ---
# The Dockerfile refers to those images (FROM / COPY --from= pi-agent-<stage>:latest),
# so prune cannot throw away the cached layers of a component that was not rebuilt.
build_stage() {
	local stage=$1 image=$2
	shift 2
	echo "--- build stage $stage -> $image:latest ---"
	DOCKER_BUILDKIT=1 $command build \
		--target "$stage" \
		"$@" \
		-t "$image:latest" \
		.
}

build_stage base pi-agent-base \
	--build-arg NODE_MAJOR="$node_major"

build_stage rust pi-agent-rust \
	--build-arg RUST_VERSION="$rust_version" \
	--build-arg TARGET_ARCH="$target_arch"

build_stage godot pi-agent-godot \
	--build-arg GODOT_VERSION="$godot_version" \
	--build-arg TARGET_ARCH="$target_arch"

# Built on top of godot (its apt browser deps have to be in the assembly base)
build_stage playwright pi-agent-playwright \
	--build-arg PLAYWRIGHT_VERSION="$playwright_version"

build_stage apps pi-agent-apps \
	--build-arg PI_VERSION="$pi_version" \
	--build-arg PI_WEB_VERSION="$pi_web_version" \
	--build-arg TARGET_ARCH="$target_arch"

# Assembly: copies from the already tagged rust/apps images
build_stage runtime pi-agent-runtime

build_stage final pi-agent \
	--build-arg IMAGE_VERSION="$tag" \
	-t "pi-agent:$tag"
