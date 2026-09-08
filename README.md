# Web SSH Center

A lightweight, web-based SSH bastion built with Docker, `ttyd`, and an interactive bash launcher script.

## Features
- Interactive terminal connection menu
- Saved hosts with custom friendly nicknames
- Line-precise host deletion/forgetting
- Designed to run behind a Cloudflare Zero Trust Tunnel

---

## ⚡ 1-Line Deployment

### Option A: Fresh VM (Blank system, no Docker)
Run this on a clean Debian/Ubuntu host to install `curl`, official Docker CE, Git, set up the project, and launch the container:

```bash
apt update && apt install -y curl git && curl -fsSL https://get.docker.com | sh && git clone https://github.com/Lukas0923xcv/SSH.git /opt/webssh && cd /opt/webssh && mkdir -p data && chmod +x launcher.sh && docker compose up -d --build
```

### Option B: Docker Already Installed
Run this if Docker and Docker Compose are already present on the machine:

```bash
git clone https://github.com/Lukas0923xcv/SSH.git /opt/webssh && cd /opt/webssh && mkdir -p data && chmod +x launcher.sh && docker compose up -d --build
```

---

## Post-Install
- **Local Access:** Accessible on the host at `http://127.0.0.1:8888` (bound to localhost by default for security).
- **Reverse Proxy / Cloudflare Tunnel:** Point your tunnel or public hostname (e.g. `ssh.example.com`) to `http://localhost:8888`.
- **Custom Ports:** Targets can be specified as `user@host` or `user@host:port`.
- **SSH Keys:** You can place an optional `.ssh/` folder inside `./data` (`./data/.ssh/id_*`) to persist custom SSH keys.

> [!WARNING]
> **Security Notice:** Port `8888` is bound to `127.0.0.1` by default to ensure it cannot be accessed directly over the public internet. Always route web access through an authenticated proxy (such as Cloudflare Zero Trust Access, Authentik/Authelia, or a VPN), as the web terminal itself is unauthenticated.
