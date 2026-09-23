┌──────────────────────────────────────────────────────────────┐
│  Proxmox Host                                                │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  LXC CONTAINER: Ubuntu 26.04                         │    │
│  │  (runs multiple quadlet containers)                  │    │
│  │                                                      │    │
│  │  ┌────────────────────────────┐  ┌──────────────┐    │    │
│  │  │ Quadlet: pi+pi-web         │  │ quadlet-2    │    │    │
│  │  │ Run as "agent" unprivileged│  │ quadlet-3    │    │    │
│  │  │  ┌───────────────────┐     │  │    ...       │    │    │
│  │  │  │ podman containers │     │  │              │    │    │
│  │  │  │(optional, created |     │  │              │    │    │
│  │  │  │ by pi agent)      │     │  │              │    │    │
│  │  │  └───────────────────┘     │  │              │    │    │
│  │  └────────────────────────────┘  └──────────────┘    │    │
│  └──────────────────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  LXC CONTAINER: llama-lxc (Ubuntu 26.04 based)       │    │
│  │  llama-swap + llama.cpp + stable-diffision.cpp       │    │
│  │  passes the /dev gpu device                          │    │
│  │  otherwise unprivileged                              │    │
│  └──────────────────────────────────────────────────────┘    │
│ Note: All containers run unprivileged (either LXC or podman) │
└──────────────────────────────────────────────────────────────┘