# Use ubuntu as base, it works best with lxc and systemd tty console and shutdown
FROM ubuntu:26.04 

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
    podman \
    uidmap \
    nftables \
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
    # Install uv
    export UV_INSTALL_DIR="/usr/local/bin" && curl -LsSf https://astral.sh/uv/install.sh | sh && \
    uv python install && \
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
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    node --version && npm --version && \
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent && \
    mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/ubuntu && \
    touch /var/lib/systemd/linger/root && \
    npm install -g @jmfederico/pi-web --allow-scripts=node-pty && \
    apt-get -y autoremove && \
    apt-get -y clean  && \
    rm -rf \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /tmp/*

RUN cat << 'EOF' > /etc/systemd/system/pi-web-sessiond.service
[Unit]
Description=Pi Web UI Session Daemon
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/usr/bin/pi-web-sessiond
Environment=HOME=/home/ubuntu
Environment=NODE_ENV=production
Environment=PI_WEB_DATA_DIR=/home/ubuntu/.pi-web
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

RUN mkdir -p /etc/pi-web && echo '{"host": "0.0.0.0"}' > /etc/pi-web/config.js
RUN cat << 'EOF' > /etc/systemd/system/pi-web.service
[Unit]
Description=Pi Web UI Gateway (System-wide)
After=network.target

[Service]
Type=simple
# Force the service to execute as the unprivileged ubuntu user
User=ubuntu
Group=ubuntu
WorkingDirectory=/home/ubuntu

ExecStart=/usr/bin/pi-web-server

Environment=HOME=/home/ubuntu
Environment=NODE_ENV=production
Environment=PI_WEB_DATA_DIR=/home/ubuntu/.pi-web
Environment=PI_WEB_CONFIG=/etc/pi-web/config.js

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

RUN npm config set logs-max 0 --global

RUN mkdir -p /opt/ubuntu_skeleton && \
    cp -a /home/ubuntu/. /opt/ubuntu_skeleton/

RUN cat << 'EOF' > /etc/systemd/system/pi-home-init.service
[Unit]
Description=Initialize empty unprivileged home volume mount
Before=multi-user.target pi-web-sessiond.service
DefaultDependencies=no

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'if [ -z "$(ls -A /home/ubuntu | grep -v lost+found)" ]; then echo "Empty host volume detected. Seeding skeleton files..."; cp -a /opt/ubuntu_skeleton/. /home/ubuntu/; chown -R ubuntu:ubuntu /home/ubuntu; fi'

[Install]
WantedBy=sysinit.target
EOF

RUN systemctl enable pi-home-init.service pi-web-sessiond.service pi-web.service


STOPSIGNAL SIGRTMIN+3

# Use full systemd init, more convenient
# for managing logs with timestamps, auto restarts with exponential backoff, etc.
# Runs well on lxc and proxmox with full tty console support, can be nested
ENTRYPOINT ["/sbin/init"]
