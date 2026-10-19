# Multi-stage build: one stage per component, each declaring ONLY the build args
# it consumes, and build.sh builds each one separately
# (`--target <stage> -t pi-agent-<stage>:latest`) so downstream stages can
# `FROM` / `COPY --from=` those images. Cached layers of a component that was
# not rebuilt therefore survive `podman image prune`.
#
# Two buildah behaviours drive this layout:
#  - layer caching is linear, so inside `runtime` the rarely-updated rust is
#    copied first and the frequently updated apps last;
#  - a build arg declared in a stage busts every layer of that stage, so
#    version args are never global and IMAGE_VERSION (new on every build) is
#    quarantined in `final`.

# ubuntu works best with lxc: systemd tty console and clean shutdown
FROM ubuntu:26.04 AS base

# build.sh passes the resolved versions; these defaults only make a plain
# `docker build .` work.
ARG NODE_MAJOR=24

USER root

RUN rm -f /etc/dpkg/dpkg.cfg.d/excludes

# Remove Ubuntu's fake man script diversion
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
    # pi's grep/find tools look for ripgrep and fd on PATH (Debian/Ubuntu ships fd as
    # "fdfind", which pi accepts) so it never downloads them into ~/.pi/agent/bin/
    ripgrep \
    fd-find \
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

# Node.js (NodeSource), installed by apt inside `base` so the dpkg database
# stays consistent; a Node major bump rebuilds everything (rare by design).
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y nodejs && \
    node --version && npm --version && \
    apt-get -y autoremove && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*

# --- Component stages (each declares only the args it consumes) ---

# Rust toolchain + musl target (for fully static binaries; the musl target
# bundles its own static libc, so no distro musl packages are needed)
FROM pi-agent-base:latest AS rust
ARG RUST_VERSION=1.99.0
ARG TARGET_ARCH=x86_64-unknown-linux-gnu
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

# Godot engine: real binary at /usr/local/lib/godot/godot, /usr/local/bin/godot
# is a wrapper that adds --headless when there is no display server.
# Intentionally no Godot MCP server: projects are plain files driven by the CLI.
FROM pi-agent-base:latest AS godot
ARG GODOT_VERSION=4.7.2
ARG TARGET_ARCH=x86_64-unknown-linux-gnu
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

# Godot export templates, version-pinned to the engine (Linux x86/arm32 +
# Windows x86 only, the rest of the .tpz is pruned). Godot expects them under
# ~/.local/share/godot/export_templates/, hence the symlinks: root's here,
# agent's is created by init-agent.sh at boot.
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

# Official Godot docs (reST) pinned to the engine's major.minor branch; only
# the .rst/.md text is kept (~35MB instead of ~400MB with .git and images).
RUN godot_doc_branch="${GODOT_VERSION%.*}" && \
    git clone --depth 1 --branch "${godot_doc_branch}" https://github.com/godotengine/godot-docs.git /tmp/godot-docs && \
    sed -n 's/^version = os.getenv("READTHEDOCS_VERSION", "\([0-9.]*\)").*/\1/p' /tmp/godot-docs/conf.py | grep -qx "${godot_doc_branch}" && \
    rm -rf /tmp/godot-docs/.git && \
    find /tmp/godot-docs -type f ! -name "*.rst" ! -name "*.md" -delete && \
    find /tmp/godot-docs -type d -empty -delete && \
    mv /tmp/godot-docs /usr/local/share/godot-docs && \
    test -f /usr/local/share/godot-docs/index.rst

# Playwright: the library + official test runner (global npm) and the browser
# binaries as image layers, so nothing is downloaded at runtime. Built on top of
# `godot` on purpose: the browser system libraries come in through
# `playwright install --with-deps` and apt packages cannot be COPYed between
# stages, so the stage that installs them must be in the assembly's base chain.
#
# Headless-only by design (no display is ever available here): Chromium *headless
# shell* + Firefox, no full Chromium build and no WebKit.
FROM pi-agent-godot:latest AS playwright
ARG PLAYWRIGHT_VERSION=1.64.1
# Browsers live in one shared, world-readable system directory instead of a
# per-user cache, and the variable is baked into the image config, so every
# process sees it (systemd, pi-web sessions, ssh shells). Do not set it to a
# writable path: `playwright install` at runtime would then re-download.
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/ms-playwright
# CJS `require("playwright")` then works from any working directory. (ESM
# `import` ignores NODE_PATH — `playwright-link` covers that, see below.)
ENV NODE_PATH=/usr/lib/node_modules
RUN apt-get update && \
    # One npm transaction for both packages: installed one after the other they
    # fight over the shared `playwright` bin link (EEXIST). @playwright/test
    # ships the superset CLI (it also knows `test`, `screenshot`, `pdf`, ...),
    # so point /usr/bin/playwright at it and keep the plain library importable
    # as `require("playwright")`.
    npm install -g playwright@${PLAYWRIGHT_VERSION} @playwright/test@${PLAYWRIGHT_VERSION} && \
    ln -sfn ../lib/node_modules/@playwright/test/cli.js /usr/bin/playwright && \
    playwright install --with-deps chromium-headless-shell firefox && \
    playwright --version && \
    playwright test --help >/dev/null && \
    ls -1 /usr/local/share/ms-playwright && \
    npm cache clean --force && \
    apt-get -y clean && \
    rm -rf /var/lib/apt/lists/* /root/.cache /root/.npm /var/tmp/* /tmp/*
# Kept after the expensive browser layer: editing the helper must not cost a
# browser re-download. It makes a project resolve the global install instead of
# npm-installing its own (which would drift from these browsers).
COPY --chmod=755 bin/playwright-link.sh /usr/local/bin/playwright-link
# PAM login shells (`ssh`, `su -`, `sudo`) start from a clean environment, so
# the image env alone is not enough: repeat both variables for PAM sessions.
RUN printf '%s\n' 'PLAYWRIGHT_BROWSERS_PATH=/usr/local/share/ms-playwright' \
                  'NODE_PATH=/usr/lib/node_modules' >> /etc/environment

# pi + pi-web, global npm (node-pty needs the build toolchain from `base`).
# Never hotpatch the installed pi-web dist/ in a running container: the plugin
# package revision is a whole-package sha256 checked by gateway and sessiond.
FROM pi-agent-base:latest AS apps
ARG PI_VERSION=1.2.0
ARG PI_WEB_VERSION=1.202610.2
ARG TARGET_ARCH=x86_64-unknown-linux-gnu
RUN case "${TARGET_ARCH}" in \
        x86_64*) esb_platform=linux-x64 ;; \
        aarch64*) esb_platform=linux-arm64 ;; \
        *) esb_platform=linux-x64 ;; \
    esac && \
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${PI_VERSION} && \
    npm install -g @jmfederico/pi-web@${PI_WEB_VERSION} --allow-scripts=node-pty && \
    # pi ships an npm-shrinkwrap.json pinning every esbuild platform binary,
    # which npm honors verbatim: keep only the native one
    for d in $(find /usr/lib/node_modules -type d -name "@esbuild"); do \
        for p in "$d"/*/; do \
            [ "$(basename "$p")" = "$esb_platform" ] || rm -rf "$p"; \
        done; \
    done && \
    rm -Rf /usr/lib/node_modules/@jmfederico/pi-web/dist/pi-packages/relays/ && \
    # Clean up build caches (npm cache + node-gyp headers downloaded for node-pty)
    npm cache clean --force && \
    rm -rf /root/.cache /root/.npm && \
    # Record the global npm bin symlinks: COPY dereferences symlinks, so the
    # assembly stage has to recreate them instead of copying them.
    mkdir -p /etc/pi-agent && \
    find /usr/bin -maxdepth 1 -type l -printf '%p\t%l\n' | grep node_modules > /etc/pi-agent/npm-bins.tsv && \
    cat /etc/pi-agent/npm-bins.tsv

# Assembly: start from the godot+playwright chain (biggest, least frequently
# rebuilt) and copy the others in, rarely-updated first.
FROM pi-agent-playwright:latest AS runtime
COPY --from=pi-agent-rust:latest /usr/local /usr/local
COPY --from=pi-agent-apps:latest /usr/lib/node_modules /usr/lib/node_modules
COPY --from=pi-agent-apps:latest /etc/pi-agent/npm-bins.tsv /etc/pi-agent/npm-bins.tsv
# Re-create the npm bin links and the export-templates symlink (COPY would
# dereference them).
RUN while IFS="$(printf '\t')" read -r link target; do ln -sfn "$target" "$link"; done < /etc/pi-agent/npm-bins.tsv && \
    mkdir -p /root/.local/share/godot && \
    ln -sfn /usr/local/share/godot/export_templates /root/.local/share/godot/export_templates && \
    # Smoke-test the assembled toolchain
    godot --version && rustc --version && cargo --version && node --version && npm --version && \
    command -v pi && command -v pi-web && \
    ls -l /usr/bin/pi /usr/bin/pi-web
COPY bin/playwright-smoke.js /tmp/playwright-smoke.js
RUN command -v playwright && playwright --version && \
    # As the unprivileged agent user: proves the shared browsers are readable
    # and launchable without a display, exactly like at runtime.
    su -s /bin/bash agent -c 'cd /tmp && node /tmp/playwright-smoke.js' && \
    rm -f /tmp/playwright-smoke.js

# Final stage: config + OCI metadata, the only part that changes every build.
FROM pi-agent-runtime:latest AS final

# Full component version tag, readable at runtime with `podman image inspect`.
# Overrides the version inherited from the base image; empty description/title
# clears Canonical's metadata from the ghcr.io page header.
ARG IMAGE_VERSION=node-24-pi-1.2.0-pi-web-1.202610.2-rust-1.99.0-godot-4.7.2-pw-1.64.1
LABEL org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.description="" \
      org.opencontainers.image.title=""

COPY systemd/pi-web-sessiond.service systemd/pi-web.service systemd/pi-home-init.service /etc/systemd/system/
COPY etc/pi-web/config.js /etc/pi-web/config.js
COPY --chmod=755 bin/init-agent.sh /usr/local/bin/init-agent
COPY etc/pi-agent/home/ /etc/pi-agent/home/

# Different ssh port, so it can coexist with a host ssh server on the same pasta network
RUN mkdir -p /etc/systemd/system/ssh.socket.d && \
    echo "[Socket]" > /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=" >> /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=0.0.0.0:2223" >> /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=[::]:2223" >> /etc/systemd/system/ssh.socket.d/listen.conf

RUN mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/agent && \
    touch /var/lib/systemd/linger/root && \
    npm config set logs-max 0 --global && \
    mkdir -p /opt/agent-home-skeleton && \
    cp -a /home/agent/. /opt/agent-home-skeleton/

COPY systemd/resize-tmp.service /etc/systemd/system/resize-tmp.service
RUN systemctl enable pi-home-init.service pi-web-sessiond.service pi-web.service resize-tmp.service


STOPSIGNAL SIGRTMIN+3

# Full systemd as entrypoint: logged timestamps, restart backoff, tty console on lxc
ENTRYPOINT ["/sbin/init"]
