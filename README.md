# Web SSH Center

A simple browser-based SSH terminal launcher designed to run behind a Cloudflare Zero Trust tunnel.

Built with Docker, `ttyd`, and Nginx. It gives you an interactive menu to connect to your servers, save favorites with nicknames, and access your SSH boxes from any browser without exposing raw SSH ports or opening port forwardings.

## Features

- **Quick menu**: Connect by typing `user@host` or pick from your saved list.
- **Custom ports**: Supports `user@host:2222` and bracketed IPv6 `[::1]:2222`.
- **Saved hosts**: Bookmark servers with custom friendly names.
- **Safe by default**: Only listens on `127.0.0.1:8888` locally, with Cross-Site WebSocket Hijacking (CSWSH) protection and security headers.
- **Security hardened**: Input sanitization preventing argument and terminal escape injection, hashed known hosts (`HashKnownHosts`), and unprivileged non-root execution.
- **Persistent storage**: Saved hosts, verified `known_hosts`, and SSH keys are stored in `./data`.

---

## Quick Start

### 1. Install Docker (optional, if not installed yet)

```bash
curl -fsSL https://get.docker.com | sh
```

### 2. Clone and launch

```bash
git clone https://github.com/Lukas0923xcv/SSH.git /opt/webssh
cd /opt/webssh
mkdir -p data
chmod +x launcher.sh
docker compose up -d --build
```

The web terminal will start locally at `http://127.0.0.1:8888`.

---

## Connecting with Cloudflare Zero Trust

Because the web terminal doesn't have built-in logins, **you should always put it behind a Cloudflare Tunnel with an Access policy** (Google/GitHub login, email pin, etc.).

### Option 1: Host Cloudflare Tunnel (Recommended)
If `cloudflared` is installed on your host machine:
1. In your Cloudflare Zero Trust dashboard, go to **Networks > Tunnels**.
2. Add a Public Hostname (e.g. `ssh.yourdomain.com`).
3. Set the service to **HTTP** -> `localhost:8888`.

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
4. In the Cloudflare Tunnel dashboard, point your hostname to **HTTP** -> `nginx:8888`.

### Don't forget an Access Policy!
In the Zero Trust dashboard under **Access > Applications**, create an application for your hostname (e.g. `ssh.yourdomain.com`) and add an Allow rule for your email. This ensures only you can reach the terminal.

---

## Tips & Custom Keys

- **SSH Keys:** If you want to use private keys instead of typing passwords, create a `.ssh` directory in `data/` (`./data/.ssh/`) and drop your keys there (e.g. `id_ed25519`). The container will pick them up automatically.
- **Saved Hosts:** Your list is stored in plain text at `data/hosts.txt`. You can edit or back it up whenever you want.

---

## Updating

To pull the latest changes and restart:

```bash
cd /opt/webssh
git pull
chmod +x launcher.sh
docker compose up -d --build
```

*(Or `docker compose --profile tunnel up -d --build` if you use the in-Docker tunnel).*
Your saved hosts and keys in `./data` won't be touched.

