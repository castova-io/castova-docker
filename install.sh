#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Castova Installer
# Usage: curl -sSL https://get.castova.net | bash
# Or:    git clone https://github.com/castova-io/castova-docker /opt/castova
#        cd /opt/castova && bash install.sh
# =============================================================================

VERSION="0.1.0"
INSTALL_DIR="/opt/castova"
DOCKER_REPO="https://github.com/castova-io/castova-docker.git"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

log()    { echo -e "${GREEN}[castova]${RESET} $*"; }
warn()   { echo -e "${YELLOW}[castova]${RESET} $*"; }
die()    { echo -e "${RED}[castova] ERROR:${RESET} $*" >&2; exit 1; }
header() { echo -e "\n${BOLD}${BLUE}━━━ $* ━━━${RESET}\n"; }

# =============================================================================
# Banner
# =============================================================================
print_banner() {
  echo -e "${BOLD}${BLUE}"
  echo "  ██████╗ █████╗ ███████╗████████╗ ██████╗ ██║   ██║ █████╗"
  echo " ██╔════╝██╔══██╗██╔════╝╚══██╔══╝██╔═══██╗██║   ██║██╔══██╗"
  echo " ██║     ███████║███████╗   ██║   ██║   ██║██║   ██║███████║"
  echo " ██║     ██╔══██║╚════██║   ██║   ██║   ██║╚██╗ ██╔╝██╔══██║"
  echo " ╚██████╗██║  ██║███████║   ██║   ╚██████╔╝ ╚████╔╝ ██║  ██║"
  echo "  ╚═════╝╚═╝  ╚═╝╚══════╝   ╚═╝    ╚═════╝   ╚═══╝  ╚═╝  ╚═╝"
  echo -e "  Installer v${VERSION}${RESET}"
  echo ""
}

# =============================================================================
# OS Detection
# =============================================================================
detect_os() {
  header "Checking system"
  [ "$(id -u)" -ne 0 ] && die "Must be run as root. Try: sudo bash install.sh"

  [ ! -f /etc/os-release ] && die "Cannot detect OS. Supported: Ubuntu 22.04+, Debian 12+"
  # shellcheck source=/dev/null
  . /etc/os-release
  case "$ID" in
    ubuntu|debian) ;;
    *) die "Unsupported OS: $PRETTY_NAME. Supported: Ubuntu 22.04+, Debian 12+" ;;
  esac
  log "OS: $PRETTY_NAME ✓"
  log "Arch: $(uname -m) ✓"
}

# =============================================================================
# Dependencies
# =============================================================================
install_dependencies() {
  header "Installing dependencies"
  export DEBIAN_FRONTEND=noninteractive

  # Wait for any background apt lock
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    [ $waited -eq 0 ] && log "Waiting for apt lock to be released..."
    waited=1
    sleep 3
  done

  log "Updating package lists..."
  apt-get update -qq

  log "Installing base packages..."
  apt-get install -y -qq \
    curl git ufw ca-certificates gnupg lsb-release \
    rclone fuse3 ffmpeg liquidsoap openssl

  # Docker
  if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
  else
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    log "Docker installed: $(docker --version)"
  fi

  # Node.js 22
  if node --version 2>/dev/null | grep -q 'v22'; then
    log "Node.js already installed: $(node --version)"
  else
    log "Installing Node.js 22..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null
    apt-get install -y -qq nodejs
    log "Node.js installed: $(node --version)"
  fi
}

# =============================================================================
# Firewall
# =============================================================================
configure_firewall() {
  header "Configuring firewall"
  local rules=(
    "22/tcp"     # SSH
    "80/tcp"     # HTTP
    "443/tcp"    # HTTPS
    "443/udp"    # HTTPS/QUIC
    "8000/tcp"   # Icecast
    "1883/tcp"   # MQTT
    "7880/tcp"   # LiveKit WS
    "7881/tcp"   # LiveKit RTC TCP
    "7881/udp"   # LiveKit RTC UDP
    "3478/tcp"   # TURN/STUN
    "3478/udp"
    "5349/tcp"   # TURNS (TLS)
    "5349/udp"
    "50200:50300/udp"   # LiveKit WebRTC media
    "49152:65535/udp"   # TURN relay
  )
  for rule in "${rules[@]}"; do
    ufw allow "$rule" >/dev/null
  done
  echo y | ufw enable >/dev/null
  log "Firewall configured."
}

# =============================================================================
# Clone / Update castova-docker
# =============================================================================
setup_files() {
  header "Setting up Castova files"

  if [ -d "$INSTALL_DIR/.git" ]; then
    log "Updating existing installation..."
    cd "$INSTALL_DIR"
    git pull
  elif [ "$(pwd)" = "$INSTALL_DIR" ] && [ -f "docker-compose.yml" ]; then
    # Already running from within the cloned repo (manual install)
    log "Running from existing repo at $INSTALL_DIR"
  else
    log "Cloning castova-docker..."
    git clone "$DOCKER_REPO" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi

  cd "$INSTALL_DIR"

  # Create required directories
  mkdir -p livekit coturn mosquitto
  mkdir -p /opt/castova/media
  mkdir -p /opt/castova/scripts
  mkdir -p /opt/castova/agent/assets
  log "Directories ready."
}

# =============================================================================
# Configuration wizard
# =============================================================================
configuration_wizard() {
  header "Configuration wizard"

  echo "This wizard will configure your Castova installation."
  echo "All secrets are generated automatically."
  echo ""

  # Panel domain
  while true; do
    read -rp "Panel domain (e.g. panel.example.com): " PANEL_DOMAIN
    [ -n "$PANEL_DOMAIN" ] && break
    warn "Domain is required."
  done

  # Admin email
  while true; do
    read -rp "Admin email address: " ADMIN_EMAIL
    [[ "$ADMIN_EMAIL" == *@* ]] && break
    warn "Please enter a valid email address."
  done

  # Admin password
  while true; do
    read -rsp "Admin password (min 8 characters): " ADMIN_PASSWORD
    echo
    [ ${#ADMIN_PASSWORD} -ge 8 ] && break
    warn "Password must be at least 8 characters."
  done

  # Optional: Anthropic API key
  echo ""
  read -rp "Anthropic API key for AI features (press Enter to skip): " ANTHROPIC_API_KEY

  # License key
  read -rp "License key (press Enter for Free tier): " LICENSE_KEY

  echo ""
  log "Generating secrets..."

  # Generate all secrets
  JWT_SECRET=$(openssl rand -hex 32)
  POSTGRES_PASSWORD=$(openssl rand -hex 24)
  LIVEKIT_API_KEY="castova-$(openssl rand -hex 6)"
  LIVEKIT_API_SECRET=$(openssl rand -hex 32)
  BRIDGE_SECRET=$(openssl rand -hex 24)
  TURN_SECRET=$(openssl rand -hex 24)
  STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)

  log "Configuration complete."
}

# =============================================================================
# Write .env
# =============================================================================
write_env() {
  header "Writing configuration files"
  cd "$INSTALL_DIR"

  cat > .env << EOF
# Castova — generated by installer on $(date)
# DO NOT SHARE THIS FILE — it contains secrets.

PANEL_DOMAIN=${PANEL_DOMAIN}
NODE_ENV=production

# Database
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_URL=postgresql://castova:${POSTGRES_PASSWORD}@postgres:5432/castova

# Redis
REDIS_URL=redis://redis:6379

# MQTT
MQTT_URL=mqtt://mosquitto:1883

# Auth
JWT_SECRET=${JWT_SECRET}

# LiveKit (Castova Studio)
LIVEKIT_API_KEY=${LIVEKIT_API_KEY}
LIVEKIT_API_SECRET=${LIVEKIT_API_SECRET}
LIVEKIT_URL=wss://${PANEL_DOMAIN}:7880

# Studio bridge
BRIDGE_SECRET=${BRIDGE_SECRET}

# TURN server
TURN_SECRET=${TURN_SECRET}

# Storage encryption
STORAGE_ENCRYPTION_KEY=${STORAGE_ENCRYPTION_KEY}

# AI features (optional)
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}

# Licensing (fill in when ready)
KEYGEN_ACCOUNT_ID=
KEYGEN_PRODUCT_TOKEN=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
EOF

  log ".env written."

  # Caddyfile
  cat > Caddyfile << EOF
${PANEL_DOMAIN} {
  reverse_proxy panel:3000
}
EOF
  log "Caddyfile written."

  # LiveKit config
  mkdir -p livekit
  cat > livekit/livekit.yaml << EOF
port: 7880
rtc:
  tcp_port: 7881
  port_range_start: 50200
  port_range_end: 50300
  use_external_ip: true
redis:
  address: redis:6379
keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}
logging:
  level: info
room:
  auto_create: true
  empty_timeout: 300
EOF
  log "livekit/livekit.yaml written."

  # Coturn config
  mkdir -p coturn
  local PUBLIC_IP
  PUBLIC_IP=$(curl -4 -fsSL --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
  cat > coturn/turnserver.conf << EOF
listening-port=3478
tls-listening-port=5349
min-port=49152
max-port=65535
external-ip=${PUBLIC_IP}
fingerprint
use-auth-secret
static-auth-secret=${TURN_SECRET}
realm=${PANEL_DOMAIN}
credential-lifetime=3600
log-file=stdout
no-stdout-log=false
no-tlsv1
no-tlsv1_1
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
EOF
  log "coturn/turnserver.conf written (public IP: ${PUBLIC_IP:-unknown})."

  # Mosquitto config
  mkdir -p mosquitto
  cat > mosquitto/mosquitto.conf << EOF
listener 1883
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest stdout
EOF
  log "mosquitto/mosquitto.conf written."
}

# =============================================================================
# Pull images and start
# =============================================================================
start_services() {
  header "Starting Castova"
  cd "$INSTALL_DIR"

  log "Pulling Docker images (this may take a few minutes)..."
  docker compose pull 2>&1 | grep -E 'Pulling|Pull complete|already' || true

  log "Starting services..."
  docker compose up -d

  log "Waiting for panel to be healthy..."
  local attempts=0
  until curl -sfL http://localhost:3000/healthz >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ $attempts -ge 40 ]; then
      warn "Panel health check timed out after 120s."
      warn "Check logs with: docker compose logs panel"
      return
    fi
    sleep 3
  done
  log "Panel is up and healthy!"
}

# =============================================================================
# Create first admin user
# =============================================================================
create_admin() {
  header "Creating admin account"

  local RESPONSE
  RESPONSE=$(curl -sfL -X POST http://localhost:3000/api/auth/register \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" 2>&1 || true)

  if echo "$RESPONSE" | grep -q '"token"'; then
    log "Admin account created: ${ADMIN_EMAIL}"
  elif echo "$RESPONSE" | grep -q 'closed\|already'; then
    log "Admin account already exists — skipping."
  else
    warn "Could not create admin account automatically."
    warn "Visit https://${PANEL_DOMAIN} to complete setup via the web UI."
  fi
}

# =============================================================================
# Activate license (if provided)
# =============================================================================
activate_license() {
  if [ -z "${LICENSE_KEY:-}" ]; then
    return
  fi
  header "Activating license"
  local RESPONSE
  RESPONSE=$(curl -sfL -X POST http://localhost:3000/api/license/activate \
    -H 'Content-Type: application/json' \
    -d "{\"key\":\"${LICENSE_KEY}\"}" 2>&1 || true)
  if echo "$RESPONSE" | grep -q '"ok"\|"tier"'; then
    log "License activated."
  else
    warn "License activation failed. You can activate it later via the panel."
  fi
}

# =============================================================================
# Summary
# =============================================================================
print_summary() {
  echo ""
  echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${GREEN}║      Castova installed successfully!     ║${RESET}"
  echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════╝${RESET}"
  echo ""
  echo -e "  ${BOLD}Panel URL:${RESET}    https://${PANEL_DOMAIN}"
  echo -e "  ${BOLD}Admin:${RESET}        ${ADMIN_EMAIL}"
  echo -e "  ${BOLD}Install dir:${RESET}  ${INSTALL_DIR}"
  echo ""
  echo -e "  ${BOLD}Useful commands:${RESET}"
  echo "    docker compose ps                   # Container status"
  echo "    docker compose logs -f panel        # Panel logs"
  echo "    docker compose logs -f              # All logs"
  echo ""
  echo -e "  ${BOLD}To update:${RESET}"
  echo "    cd ${INSTALL_DIR} && git pull && docker compose pull && docker compose up -d --force-recreate"
  echo ""
  echo -e "  ${BOLD}Documentation:${RESET}  https://castova.net/docs"
  echo -e "  ${BOLD}Support:${RESET}        https://castova.net/support"
  echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
  print_banner
  detect_os
  install_dependencies
  configure_firewall
  setup_files
  configuration_wizard
  write_env
  start_services
  create_admin
  activate_license
  print_summary
}

main
