#!/usr/bin/env bash
# ==============================================================================
# Web SSH Center - One-Command Installer for Linux / Ubuntu / Debian
# Repository: https://github.com/Lukas0923xcv/SSH.git
# ==============================================================================

set -e

COLOR_BLUE='\033[0;34m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_CYAN='\033[0;36m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_CYAN}"
cat << "EOF"
  __      __      ___.     _________ _________ ___ ___ 
 /  \    /  \ ____\_ |__  /   _____//   _____//   |   \
 \   \/\/   // __ \| __ \ \_____  \ \_____  \/    ~    \
  \        /\  ___/| \_\ \/        \/        \    Y    /
   \__/\  /  \___  >___  /_______  /_______  /\___|_  / 
        \/       \/    \/        \/        \/       \/  
EOF
echo -e "${COLOR_RESET}"
echo -e "${COLOR_GREEN}Starting Web SSH Center Installation...${COLOR_RESET}\n"

# 1. Verify sudo / root access
if [ "$EUID" -ne 0 ]; then
  SUDO="sudo"
  echo -e "${COLOR_YELLOW}[i] Running with sudo privileges...${COLOR_RESET}"
else
  SUDO=""
fi

# 2. Update package lists and check dependencies
echo -e "${COLOR_BLUE}[1/5] Checking system dependencies (git, curl)...${COLOR_RESET}"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq git curl ca-certificates gnupg >/dev/null

# 3. Check / Install Docker and Docker Compose
echo -e "${COLOR_BLUE}[2/5] Checking Docker & Docker Compose...${COLOR_RESET}"
if ! command -v docker &> /dev/null; then
  echo -e "${COLOR_YELLOW}[i] Docker is not installed. Installing Docker Engine...${COLOR_RESET}"

  if $SUDO apt-get install -y docker.io docker-compose-v2 >/dev/null 2>&1 || \
     $SUDO apt-get install -y docker.io docker-compose >/dev/null 2>&1; then
    echo -e "${COLOR_GREEN}[✓] Docker installed from package repository!${COLOR_RESET}"
  else
    # Fallback to official docker installation script
    curl -fsSL https://get.docker.com | $SUDO sh >/dev/null 2>&1
    echo -e "${COLOR_GREEN}[✓] Docker installed via official script!${COLOR_RESET}"
  fi
  $SUDO systemctl enable --now docker 2>/dev/null || true
else
  echo -e "${COLOR_GREEN}[✓] Docker is already installed: $(docker --version 2>/dev/null || echo 'Docker')${COLOR_RESET}"
fi

# Determine Docker Compose command
if docker compose version &>/dev/null; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
else
  $SUDO apt-get install -y docker-compose-v2 >/dev/null 2>&1 || true
  COMPOSE_CMD="docker compose"
fi

# 4. Clone or update repository
APP_DIR="/opt/webssh"
REPO_URL="https://github.com/Lukas0923xcv/SSH.git"

echo -e "${COLOR_BLUE}[3/5] Setting up application repository at ${APP_DIR}...${COLOR_RESET}"
$SUDO git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true
git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true

if [ -d "$APP_DIR/.git" ]; then
  echo -e "${COLOR_YELLOW}[i] Updating existing installation at ${APP_DIR}...${COLOR_RESET}"
  cd "$APP_DIR"
  $SUDO git fetch origin main
  $SUDO git reset --hard origin/main
elif [ -d ".git" ] && [ -f "docker-compose.yml" ]; then
  APP_DIR="$(pwd)"
  echo -e "${COLOR_YELLOW}[i] Using current directory: ${APP_DIR}${COLOR_RESET}"
else
  $SUDO mkdir -p "$APP_DIR"
  $SUDO git clone "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
fi

# 5. Prepare permissions and persistent storage
echo -e "${COLOR_BLUE}[4/5] Preparing persistent data directory and file permissions...${COLOR_RESET}"
cd "$APP_DIR"
$SUDO chmod +x launcher.sh install.sh 2>/dev/null || true
$SUDO mkdir -p "$APP_DIR/data"
$SUDO chmod 700 "$APP_DIR/data"
$SUDO touch "$APP_DIR/data/hosts.txt" "$APP_DIR/data/known_hosts" 2>/dev/null || true
$SUDO chmod 600 "$APP_DIR/data/hosts.txt" "$APP_DIR/data/known_hosts" 2>/dev/null || true

if [ ! -f "$APP_DIR/.env" ] && [ -f "$APP_DIR/.env.example" ]; then
  $SUDO cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  $SUDO chmod 600 "$APP_DIR/.env" 2>/dev/null || true
fi

# 6. Build and launch Docker Compose stack
echo -e "${COLOR_BLUE}[5/5] Building and launching Web SSH Center containers...${COLOR_RESET}"
cd "$APP_DIR"
$SUDO $COMPOSE_CMD down 2>/dev/null || true
$SUDO $COMPOSE_CMD up -d --build

# 7. Success Banner
echo -e "\n${COLOR_GREEN}========================================================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}  🎉 Web SSH Center is now installed and running!${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================================================${COLOR_RESET}"
echo -e "  🌐 Local Access:       ${COLOR_YELLOW}http://127.0.0.1:8888${COLOR_RESET} (or http://localhost:8888)"
echo -e "  🔒 Security Mode:      ${COLOR_CYAN}Bound to 127.0.0.1 (Protected from direct public IP scans)${COLOR_RESET}"
echo -e "  📁 Persistent Data:    ${COLOR_YELLOW}${APP_DIR}/data${COLOR_RESET}"
echo -e "  📊 View Logs:          ${COLOR_BLUE}cd ${APP_DIR} && ${COMPOSE_CMD} logs -f${COLOR_RESET}"
echo -e "  🛑 Stop Service:       ${COLOR_BLUE}cd ${APP_DIR} && ${COMPOSE_CMD} down${COLOR_RESET}"
echo -e "  🚀 Restart Service:    ${COLOR_BLUE}cd ${APP_DIR} && ${COMPOSE_CMD} restart${COLOR_RESET}"
echo -e "  🔄 Update:             ${COLOR_BLUE}curl -sSL https://raw.githubusercontent.com/Lukas0923xcv/SSH/main/install.sh | bash${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================================================${COLOR_RESET}"
echo -e "${COLOR_YELLOW}  ⚠️  Cloudflare Zero Trust Reminder:${COLOR_RESET}"
echo -e "  To access remotely, point your Cloudflare Tunnel to ${COLOR_CYAN}HTTP -> localhost:8888${COLOR_RESET}"
echo -e "  and protect your public hostname with a Cloudflare Access policy (MFA).\n"
