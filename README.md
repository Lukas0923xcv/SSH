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
- **Web Terminal:** Accessible locally at `http://<HOST-IP>:8888`
- **Reverse Proxy / Cloudflare Tunnel:** Point your public hostname (e.g. `ssh.example.com`) to `http://localhost:8888`

> [!WARNING]
> **Security Notice:** Do not expose port `8888` directly to the open internet without an authentication layer (such as Cloudflare Access, HTTP basic auth, or VPN), as terminal access is unauthenticated by default.
