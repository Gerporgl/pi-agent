# Use ubuntu as base, it works best with lxc and systemd tty console and shutdown
FROM ubuntu:26.04 

# Versions passed as build args by build.sh (defaults are the current ones, so a plain `docker build .` still works)
ARG NODE_MAJOR=24
ARG PI_VERSION=0.85.1
ARG PI_WEB_VERSION=1.202609.0
ARG RUST_VERSION=1.98.1
ARG TARGET_ARCH=x86_64-unknown-linux-gnu

USER root

RUN sed -i 's|http://archive.ubuntu.com|http://mirror.csclub.uwaterloo.ca|g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's|http://security.ubuntu.com|http://mirror.csclub.uwaterloo.ca|g' /etc/apt/sources.list.d/ubuntu.sources && \
    cat /etc/apt/sources.list.d/ubuntu.sources && \
    apt-get update && \
    apt-get remove -y unminimize && \
    apt-get install -y --no-install-recommends \ 
    ca-certificates \
    software-properties-common && \
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
    /tmp/* && \
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
    rm /lib/systemd/system/motd-news.timer && \
    mkdir -p /home/ubuntu/.ssh && chown ubuntu:ubuntu /home/ubuntu/.ssh && \
    sed -i -e '2iTERM=xterm-color\\' /root/.profile && \
    cp /root/.profile /home/ubuntu/.profile && \
    cp /root/.bashrc /home/ubuntu/.bashrc 


# Install latest stable Node.js system-wide (NodeSource), available globally to all users
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get install -y nodejs && \
    node --version && npm --version && \
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent@${PI_VERSION} && \
    mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/ubuntu && \
    touch /var/lib/systemd/linger/root && \
    npm install -g @jmfederico/pi-web@${PI_WEB_VERSION} --allow-scripts=node-pty && \
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
    "./rust-${RUST_VERSION}-${TARGET_ARCH}/install.sh" --prefix=/usr/local && \
    "./rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl/install.sh" --prefix=/usr/local && \
    rm -rf "rust-${RUST_VERSION}-${TARGET_ARCH}" "rust-${RUST_VERSION}-${TARGET_ARCH}.tar.gz" \
           "rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl" "rust-std-${RUST_VERSION}-${TARGET_ARCH%-gnu}-musl.tar.gz" && \
    rustc --version && cargo --version && \
    ls "/usr/local/lib/rustlib/${TARGET_ARCH%-gnu}-musl/lib" | grep -q '\.rlib$'

# systemd service files and pi-web config, kept as real files in the repo
COPY systemd/pi-web-sessiond.service systemd/pi-web.service systemd/pi-home-init.service /etc/systemd/system/
COPY etc/pi-web/config.js /etc/pi-web/config.js
COPY --chmod=755 bin/init-ubuntu.sh /usr/local/bin/init-ubuntu

# Listen on different ssh port, so that it can coexists with another ssh server on the same pasta network
RUN mkdir -p /etc/systemd/system/ssh.socket.d && \
    echo "[Socket]" > /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=" >> /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=0.0.0.0:2223" >> /etc/systemd/system/ssh.socket.d/listen.conf && \
    echo "ListenStream=[::]:2223" >> /etc/systemd/system/ssh.socket.d/listen.conf

RUN npm config set logs-max 0 --global

RUN mkdir -p /opt/ubuntu_skeleton && \
    cp -a /home/ubuntu/. /opt/ubuntu_skeleton/

RUN systemctl enable pi-home-init.service pi-web-sessiond.service pi-web.service


STOPSIGNAL SIGRTMIN+3

# Use full systemd init, more convenient
# for managing logs with timestamps, auto restarts with exponential backoff, etc.
# Runs well on lxc and proxmox with full tty console support, can be nested
ENTRYPOINT ["/sbin/init"]
