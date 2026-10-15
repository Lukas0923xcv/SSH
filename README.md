# Web SSH Center

A simple browser-based SSH terminal launcher designed to run behind a Cloudflare Zero Trust tunnel.

Built with Docker, `ttyd`, and Nginx. It gives you an interactive menu to connect to your servers, save favorites with nicknames, and access your SSH boxes from any browser without exposing raw SSH ports or opening port forwardings.

## Features

- **Quick menu**: Connect by typing `user@host` or pick from your saved list.
- **Visible versioning**: Current application version is displayed in the web UI terminal banner and window title.
- **Custom ports**: Supports `user@host:2222` and bracketed IPv6 `[::1]:2222`.
- **Saved hosts**: Bookmark servers with custom friendly names with atomic, race-free storage.
- **Safe by default**: Listens on `127.0.0.1:8888` locally by default with Cross-Site WebSocket Hijacking (CSWSH) protection, DNS rebinding mitigation, and strict security headers, preventing direct internet scanning from bypassing Cloudflare Access and MFA.
- **Security hardened**: Strict input sanitization preventing argument and terminal escape injection, per-IP connection limits and session caps (`-m 10`), hashed known hosts (`HashKnownHosts`), command-line escape disabled (`EnableEscapeCommandline=no`), unprivileged execution, and build context isolation (`.dockerignore`).
- **Persistent storage**: Saved hosts, verified `known_hosts`, and SSH keys are stored in `./data`.

---

## Quick Start (One-Command Install)

Run this single command on your Ubuntu / Debian / Linux server:

```bash
curl -sSL https://raw.githubusercontent.com/Lukas0923xcv/SSH/main/install.sh | bash
```

The installer will automatically install Docker (if needed), clone the repo to `/opt/webssh`, configure secure permissions, and launch the Web SSH stack.

The web terminal will start locally at `http://127.0.0.1:8888`.

<details>
<summary>Manual Installation</summary>

```bash
# 1. Install Docker (if not installed yet)
curl -fsSL https://get.docker.com | sh

# 2. Clone and launch
git clone https://github.com/Lukas0923xcv/SSH.git /opt/webssh
cd /opt/webssh
mkdir -p data
chmod 700 data
chmod +x launcher.sh
docker compose up -d --build
```
</details>

---

## Connecting with Cloudflare Zero Trust

Because the web terminal doesn't have built-in logins, **you should always put it behind a Cloudflare Tunnel with an Access policy** (Google/GitHub login, email pin, MFA, etc.).

### Option 1: Host Cloudflare Tunnel (Recommended)
If `cloudflared` is installed on your host machine or another device on your network:
1. In your Cloudflare Zero Trust dashboard, go to **Networks > Tunnels**.
2. Add a Public Hostname (e.g. `ssh.yourdomain.com`).
3. Set the service to **HTTP** -> `localhost:8888` (or `http://<your-lan-ip>:8888`, e.g. `http://192.168.1.50:8888`).

### Option 2: Docker Cloudflare Tunnel
If you prefer running `cloudflared` in Docker alongside the stack:
1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```
2. Put your tunnel token in `.env`:
   ```env
   TUNNEL_TOKEN=eyJhIjoi...
   ```
3. Start the stack with the tunnel profile:
   ```bash
   docker compose --profile tunnel up -d --build
   ```
4. In the Cloudflare Tunnel dashboard, you can point your hostname to **HTTP** -> `localhost:8888` or your LAN IP.

### Don't forget an Access Policy!
In the Zero Trust dashboard under **Access > Applications**, create an application for your hostname (e.g. `ssh.yourdomain.com`) and add an Allow rule for your email. This ensures only you can reach the terminal.

---

## Tips & Custom Keys

- **SSH Keys:** If you want to use private keys instead of typing passwords, create a `.ssh` directory in `data/` (`./data/.ssh/`) and drop your keys there (e.g. `id_ed25519`). The container will pick them up automatically.
- **Saved Hosts:** Your list is stored in plain text at `data/hosts.txt`. You can edit or back it up whenever you want.

---

## Updating

To update an existing installation to the latest version, run:

```bash
curl -sSL https://raw.githubusercontent.com/Lukas0923xcv/SSH/main/install.sh | bash
```

Or manually:

```bash
cd /opt/webssh
git pull
chmod +x launcher.sh
docker compose down
docker compose up -d --build
```

---

## Security Hardening (v1.3.2)

Web SSH Center incorporates multi-layered security controls against common web-to-terminal attack vectors:
- **CSWSH & DNS Rebinding Protection**: Nginx dynamically checks the `Origin` header against Host headers on verified local/private addresses or verified Cloudflare Tunnels (via `CF-Ray`), preventing cross-origin hijacking and DNS-rebinding exploits.
- **Input Sanitization**: Terminal launcher inputs are verified against a strict character whitelist, preventing command substitution, shell escapes, or flag injection.
- **DoS & Session Limits**: Per-IP connection limits in Nginx (`limit_conn 10`) and session caps in `ttyd` (`-m 10`) mitigate denial-of-service and memory exhaustion.
- **Strict Content Security Policy**: CSP enforces `connect-src 'self'`, restricting WebSocket and HTTP connections exclusively to origin.

---
 
## Development & AI Guidelines
 
This repository enforces automated AI guidelines documented in [`AGENTS.md`](file:///AGENTS.md) and [`GEMINI.md`](file:///GEMINI.md).
Whenever modifications, features, or security patches are introduced, the canonical version must be incremented in [`VERSION`](file:///VERSION) following Semantic Versioning.

