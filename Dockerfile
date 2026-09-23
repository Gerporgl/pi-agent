# Use ubuntu as base, it works best with lxc and systemd tty console and shutdown
FROM ubuntu:26.04 

# Clear the OCI metadata inherited from the base image (the long Canonical
# description otherwise shows up in the ghcr.io page header)
LABEL org.opencontainers.image.description="" \
      org.opencontainers.image.title=""

# Versions passed as build args by build.sh (defaults are the current ones, so a plain `docker build .` still works)
ARG NODE_MAJOR=24
ARG PI_VERSION=0.85.1
ARG PI_WEB_VERSION=1.202609.0
ARG RUST_VERSION=1.98.1
# Godot is auto-tracked by build.sh; the two npm packages are pinned manually
ARG GODOT_VERSION=4.7.2
ARG GODOT_MCP_VERSION=0.1.1
ARG PI_MCP_ADAPTER_VERSION=2.34.0
ARG TARGET_ARCH=x86_64-unknown-linux-gnu

USER root

RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes

# 2. Forcefully remove Ubuntu's fake man script diversion
RUN if [ -f /usr/bin/man.REAL ] || dpkg-divert --list /usr/bin/man | grep -q "man.REAL"; then \
        rm -f /usr/bin/man && \
        dpkg-divert --remove /usr/bin/man; \
    fi


RUN cat /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update && \
    apt-get purge -y unminimize && \
    apt-get install -y --no-install-recommends \ 
    ca-certificates \
    software-properties-common && \
    apt-get install -y --reinstall -y \
    man-db manpages manpages-posix \
    coreutils && \
    apt-get install -y --no-install-recommends \
    curl \
    openssh-server \
    sudo \
    # For convenience, install nano
    nano \
    # Network tools such as ping and host command
    iputils-ping \
    bind9-host \
    # Full systemd init entrypoint
    init \
    # pi agent related and tools for the agent
    build-essential \
    ripgrep \
    dbus-user-session \
    git \
    cmake zip unzip jq yq \
    # Godot runtime deps: fontconfig is dlopened even in headless mode (fonts),
    # the vulkan loader is only needed when a Vulkan renderer is active
    libfontconfig1 \
    libvulkan1 \
    python3-pip \
    python3-venv \
    pkg-config  \
    ninja-build \
    libssl-dev \
    # iproute2 for the networkd-based network stack (better ipv6 and dhcp support on proxmox/lxc)
    iproute2 && \
    apt install -y podman && \
    # Install uv
    export UV_INSTALL_DIR="/usr/local/bin" && curl -LsSf https://astral.sh/uv/install.sh | sh && \
    uv python install && \
    apt-get purge -y packagekit && \
    apt-get -y autoremove && \
    apt-get -y clean  && \
    rm -rf \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/* \
    # Test binaries shipped with podman/buildah, only used by their own test suites
    /usr/libexec/buildah/tutorial /usr/libexec/buildah/imgtype /usr/libexec/buildah/copy \
    /usr/libexec/podman/podman-testing && \
    # Remove clutter messages on login
    rm /etc/update-motd.d/10* && rm /etc/update-motd.d/50* && rm /etc/update-motd.d/60* && \
    # Enable some service and remove a bunch of unwanted automatic timers
    # Updates will have to be run manually or with new containers builds
    systemctl enable systemd-networkd.service && \ 
    rm /etc/systemd/system/timers.target.wants/apt* && \
    rm /etc/systemd/system/timers.target.wants/dpkg* && \
    rm /etc/systemd/system/timers.target.wants/e2scrub* && \
    rm /etc/systemd/system/timers.target.wants/fstrim* && \
    rm /etc/systemd/system/timers.target.wants/motd* && \
    rm /usr/lib/systemd/system/apt-daily-upgrade.timer && \
    rm /usr/lib/systemd/system/apt-daily.timer && \
    rm /usr/lib/systemd/system/dpkg-db-backup.timer && \
    rm /usr/lib/systemd/system/e2scrub_all.timer && \
    rm /usr/lib/systemd/system/fstrim.timer && \
    rm /lib/systemd/system/motd-news.timer

# Rename the default ubuntu user to agent (keeping uid/gid 1000), rename the
# matching group, and drop the secondary groups that are irrelevant in a
# container (sudo, cdrom, floppy, adm, dialout, audio, dip, video, plugdev).
# Rootless podman only needs the subuid/subgid ranges, so those are kept (renamed).
RUN usermod -l agent -d /home/agent -m -c "Agent" ubuntu && \
    groupmod -n agent ubuntu && \
    usermod -G "" agent && \
    sed -i 's/^ubuntu:/agent:/' /etc/subuid /etc/subgid

RUN mkdir -p /home/agent/.ssh && chown agent:agent /home/agent/.ssh && \
    sed -i -e '2iTERM=xterm-color\\' /root/.profile && \
    cp /root/.profile /home/agent/.profile && \
    cp /root/.bashrc /home/agent/.bashrc


# Install latest stable Node.js system-wide (NodeSource), available globally to all users
RUN case "${TARGET_ARCH}" in \
        x86_64*) esb_platform=linux-x64 ;; \
        aarch64*) esb_platform=linux-arm64 ;; \
        *) esb_platform=linux-x64 ;; \
    esac && \
    curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y nodejs && \
    node --version && npm --version && \
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${PI_VERSION} && \
    mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/agent && \
    touch /var/lib/systemd/linger/root && \
    npm install -g @jmfederico/pi-web@${PI_WEB_VERSION} --allow-scripts=node-pty && \
    # pi-coding-agent ships an npm-shrinkwrap.json that pins esbuild binaries for
    # every platform, and npm honors a bundled shrinkwrap verbatim (no platform
    # filtering), so prune all esbuild platform packages except the native one
    for d in $(find /usr/lib/node_modules -type d -name "@esbuild"); do \
        for p in "$d"/*/; do \
            [ "$(basename "$p")" = "$esb_platform" ] || rm -rf "$p"; \
        done; \
    done && \
    npm config set logs-max 0 --global && \
    # Clean up build caches (npm cache + node-gyp headers downloaded for node-pty)
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm && \
    apt-get -y autoremove && \
    apt-get -y clean  && \
    rm -rf \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

# Install Rust toolchain system-wide from the official standalone package,
# including the musl target for building fully static, libc-independent binaries
# (the musl target is self-contained: it bundles its own static musl libc,
# so no distro musl packages are needed)
RUN curl -sSfLO "https://static.rust-lang.org/dist/rust-${RUST_VERSION}-${TARGET_ARCH}.tar.gz" && \
    curl -sSfLO "https://static.rust-lang.org/dist/rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl.tar.gz" && \
    tar -xzf "rust-${RUST_VERSION}-${TARGET_ARCH}.tar.gz" && \
    tar -xzf "rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl.tar.gz" && \
    # Skip the docs components (rust-docs is ~610MB of HTML, rust-docs-json is ~19MB)
    "./rust-${RUST_VERSION}-${TARGET_ARCH}/install.sh" --prefix=/usr/local --without=rust-docs,rust-docs-json-preview && \
    "./rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl/install.sh" --prefix=/usr/local && \
    rm -rf "rust-${RUST_VERSION}-${TARGET_ARCH}" "rust-${RUST_VERSION}-${TARGET_ARCH}.tar.gz" \
           "rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl" "rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl.tar.gz" && \
    rustc --version && cargo --version && \
    ls "/usr/local/lib/rustlib/${TARGET_ARCH%-gnu}-musl/lib" | grep -q '\.rlib$'

# Install Godot engine system-wide (headless-capable). The binary is nearly
# static; its runtime dlopens (fontconfig, vulkan) are covered by the apt layer.
# The real binary goes to /usr/local/lib/godot/godot; /usr/local/bin/godot is a
# wrapper (bin/godot-wrapper.sh) that auto-adds --headless when no display
# server is available, so MCP run_project and CI work on headless machines.
RUN case "${TARGET_ARCH}" in \
        x86_64*) godot_arch=x86_64 ;; \
        aarch64*) godot_arch=arm64 ;; \
        *) echo "ERROR: unsupported architecture for Godot: ${TARGET_ARCH}"; exit 1 ;; \
    esac && \
    curl -fsSLO "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}.zip" && \
    unzip -q "Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}.zip" && \
    mkdir -p /usr/local/lib/godot && \
    install -m 755 "Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}" /usr/local/lib/godot/godot && \
    rm -f "Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}" "Godot_v${GODOT_VERSION}-stable_linux.${godot_arch}.zip"
COPY --chmod=755 bin/godot-wrapper.sh /usr/local/bin/godot
RUN godot --version

# Godot export templates (system-wide, version-pinned to the engine), so
# Linux/Windows releases can be exported headlessly. Godot looks for them
# in <user home>/.local/share/godot/export_templates/<engine version>/, so
# per-user access is provided by symlinks (root here, agent via
# init-agent.sh on boot). Note: .tpz is a plain zip. Only the Linux x86/arm32
# and Windows x86 templates are kept; the Android/iOS/macOS/Web templates and
# the Windows ARM64 / Linux ARM64 ones are pruned to keep the image small.
RUN curl -fsSLO "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" && \
    mkdir -p /usr/local/share/godot/export_templates && \
    unzip -q "Godot_v${GODOT_VERSION}-stable_export_templates.tpz" -d /tmp/godot-templates && \
    test "$(tr -d '[:space:]' < /tmp/godot-templates/templates/version.txt)" = "${GODOT_VERSION}.stable" && \
    mv /tmp/godot-templates/templates "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable" && \
    rm -f "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable"/android_* \
          "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable"/ios* \
          "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable"/macos* \
          "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable"/web_* \
          "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable"/windows_*_arm64* \
          "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable"/linux_*arm64* && \
    chmod +x "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable"/* && \
    rm -rf /tmp/godot-templates "Godot_v${GODOT_VERSION}-stable_export_templates.tpz" && \
    test -f "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable/linux_release.x86_64" && \
    test -f "/usr/local/share/godot/export_templates/${GODOT_VERSION}.stable/windows_release_x86_64.exe"
RUN mkdir -p /root/.local/share/godot && \
    ln -s /usr/local/share/godot/export_templates /root/.local/share/godot/export_templates

# Official Godot documentation (reStructuredText), system-wide and pinned to
# the engine's major.minor: godot-docs keeps one branch per major.minor
# (e.g. "4.7"), cloned shallow at build time. Only the text files are kept —
# the .git metadata (~200MB) and the images/videos (~180MB) are useless to an
# AI agent, leaving ~35MB of reST. The agent learns where it lives from the
# godot SKILL.md.
RUN godot_doc_branch="${GODOT_VERSION%.*}" && \
    git clone --depth 1 --branch "${godot_doc_branch}" https://github.com/godotengine/godot-docs.git /tmp/godot-docs && \
    sed -n 's/^version = os.getenv("READTHEDOCS_VERSION", "\([0-9.]*\)").*/\1/p' /tmp/godot-docs/conf.py | grep -qx "${godot_doc_branch}" && \
    rm -rf /tmp/godot-docs/.git && \
    find /tmp/godot-docs -type f ! -name "*.rst" ! -name "*.md" -delete && \
    find /tmp/godot-docs -type d -empty -delete && \
    mv /tmp/godot-docs /usr/local/share/godot-docs && \
    test -f /usr/local/share/godot-docs/index.rst

# Install the Godot MCP server and the pi MCP adapter system-wide (global npm,
# shared by all users). pi loads the adapter from this global path via the
# "packages" entry that init-agent ingests into each user's pi settings.
RUN npm install -g @coding-solo/godot-mcp@${GODOT_MCP_VERSION} pi-mcp-adapter@${PI_MCP_ADAPTER_VERSION} && \
    command -v godot-mcp && \
    test -f /usr/lib/node_modules/pi-mcp-adapter/package.json && \
    npm cache clean --force && \
    rm -rf /root/.npm

# systemd service files, pi-web config, and the per-home pi config stub that
# init-agent ingests into /home/agent on every boot (kept as real files in the repo)
COPY systemd/pi-web-sessiond.service systemd/pi-web.service systemd/pi-home-init.service /etc/systemd/system/
COPY etc/pi-web/config.js /etc/pi-web/config.js
COPY --chmod=755 bin/init-agent.sh /usr/local/bin/init-agent
COPY etc/pi-agent/home/ /etc/pi-agent/home/

# Listen on different ssh port, so that it can coexists with another ssh server on the same pasta network
RUN mkdir -p /etc/systemd/system/ssh.socket.d && \
    echo "[Socket]" > /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=" >> /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=0.0.0.0:2223" >> /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=[::]:2223" >> /etc/systemd/system/ssh.socket.d/listen.conf

RUN mkdir -p /opt/agent-home-skeleton && \
    cp -a /home/agent/. /opt/agent-home-skeleton/

RUN systemctl enable pi-home-init.service pi-web-sessiond.service pi-web.service


STOPSIGNAL SIGRTMIN+3

# Use full systemd init, more convenient
# for managing logs with timestamps, auto restarts with exponential backoff, etc.
# Runs well on lxc and proxmox with full tty console support, can be nested
ENTRYPOINT ["/sbin/init"]
