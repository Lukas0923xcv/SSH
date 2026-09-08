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

## 🔒 Cloudflare Zero Trust Setup Guide

This project is built specifically to be accessed through a Cloudflare Zero Trust Tunnel with an authentication policy.

### Step 1: Create a Tunnel in Cloudflare
In the [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/):
1. Navigate to **Networks** > **Tunnels** and click **Create a tunnel** (select `Cloudflared`).
2. Choose your deployment method:

#### Method A: Run Cloudflare Tunnel on Host Machine (Recommended)
Follow the dashboard instructions to install `cloudflared` on the host VM, then configure the **Public Hostname**:
* **Subdomain / Domain:** e.g., `ssh.yourdomain.com`
* **Service Type:** `HTTP`
* **URL:** `localhost:8888` (or `127.0.0.1:8888`)

#### Method B: Run Cloudflare Tunnel Inside Docker
1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Paste your Tunnel Token into `.env`:
   ```env
   TUNNEL_TOKEN=eyJhIjoi...
   ```
3. Launch with the tunnel profile:
   ```bash
   docker compose --profile tunnel up -d --build
   ```
4. In the Cloudflare Tunnel Public Hostname configuration, point the service to:
   * **Service Type:** `HTTP`
   * **URL:** `nginx:8888`

---

### Step 2: Protect with Cloudflare Access (Required for Security!)
A Cloudflare Tunnel exposes the web service through Cloudflare's network, but **Access Applications** provide the authentication gatekeeper:
1. In Cloudflare Zero Trust, go to **Access** > **Applications** > **Add an application** > **Self-hosted**.
2. Set the **Application Domain** to match your tunnel hostname (e.g. `ssh.yourdomain.com`).
3. Add an **Access Policy** (e.g. "Allow" rule restricted to your email address, Google/GitHub SSO, or email OTP).
4. Save the application. Now, anyone attempting to access your SSH bastion must authenticate through Cloudflare before reaching the terminal!

---

## 🛠️ Post-Install & Usage Details
- **Local Port Binding:** Port `8888` is bound to `127.0.0.1` by default. This ensures the web terminal is never exposed directly on your server's public IP, preventing anyone from bypassing Cloudflare Access.
- **Custom Ports:** Targets in the launcher can be specified as `user@host` or `user@host:port`.
- **SSH Keys:** You can place an optional `.ssh/` folder inside `./data` (`./data/.ssh/id_*`) to persist custom SSH keys.
- **Host Key Verification:** Verified remote host keys are saved to `./data/known_hosts` so they persist across container rebuilds.

