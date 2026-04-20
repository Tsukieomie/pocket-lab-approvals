#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-secure-tunnel.sh — Pocket Lab v2.7+
#
# Sets up a persistent, secure bore tunnel on an Oracle Cloud VPS so the iSH
# device can connect reliably without the bore.pub port-hijacking problem.
#
# Run this ON the Oracle Cloud VPS (Ubuntu 22.04+ / Oracle Linux 9+).
#
# What it does:
#   1. Installs bore (server mode) if not present
#   2. Generates a shared secret for tunnel authentication
#   3. Opens the required ports in iptables + Oracle VCN reminder
#   4. Creates a systemd service that auto-restarts bore-server
#   5. Drops a client snippet you paste into iSH's start-lab.sh
#
# Usage:
#   chmod +x setup-secure-tunnel.sh
#   sudo ./setup-secure-tunnel.sh
#
# Prerequisites:
#   - Oracle Cloud VPS with a public IP
#   - SSH access to the VPS (already set up if you can run this)
#   - Oracle VCN security list must allow inbound TCP on BORE_PORT + SSH_PORT
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
BORE_PORT="${BORE_PORT:-2200}"          # port bore-server listens on for clients
SSH_TUNNEL_PORT="${SSH_TUNNEL_PORT:-2222}"  # port exposed for SSH into iSH
BORE_SECRET_FILE="/etc/bore/secret"
BORE_BIN="/usr/local/bin/bore"
SERVICE_NAME="bore-server"
BORE_VERSION="0.5.2"                   # pin a known-good release
INSTALL_DIR="/usr/local/bin"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()   { printf "${RED}[✗]${NC} %s\n" "$*" >&2; }

# ── Root check ───────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  err "This script must be run as root (use sudo)."
  exit 1
fi

# ── Detect architecture ─────────────────────────────────────────────────────
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  BORE_ARCH="x86_64-unknown-linux-musl" ;;
  aarch64) BORE_ARCH="aarch64-unknown-linux-musl" ;;
  *)       err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# ── Step 1: Install bore ────────────────────────────────────────────────────
install_bore() {
  if [[ -x "$BORE_BIN" ]]; then
    CURRENT=$("$BORE_BIN" --version 2>/dev/null | awk '{print $2}' || echo "unknown")
    info "bore already installed (version $CURRENT)"
    return 0
  fi

  info "Installing bore v${BORE_VERSION} for ${ARCH}..."
  TMPDIR=$(mktemp -d)
  TARBALL="bore-v${BORE_VERSION}-${BORE_ARCH}.tar.gz"
  URL="https://github.com/ekzhang/bore/releases/download/v${BORE_VERSION}/${TARBALL}"

  curl -fSL --retry 3 "$URL" -o "${TMPDIR}/${TARBALL}"
  tar -xzf "${TMPDIR}/${TARBALL}" -C "${TMPDIR}"
  install -m 755 "${TMPDIR}/bore" "$INSTALL_DIR/bore"
  rm -rf "$TMPDIR"
  info "bore installed to $INSTALL_DIR/bore"
}

install_bore

# ── Step 2: Generate shared secret ──────────────────────────────────────────
generate_secret() {
  mkdir -p "$(dirname "$BORE_SECRET_FILE")"
  if [[ -f "$BORE_SECRET_FILE" ]]; then
    info "Shared secret already exists at $BORE_SECRET_FILE"
  else
    openssl rand -hex 32 > "$BORE_SECRET_FILE"
    chmod 600 "$BORE_SECRET_FILE"
    info "Generated new shared secret at $BORE_SECRET_FILE"
  fi
}

generate_secret
BORE_SECRET=$(cat "$BORE_SECRET_FILE")

# ── Step 3: Firewall (iptables) ──────────────────────────────────────────────
configure_firewall() {
  info "Configuring iptables..."

  # Allow bore control port
  if ! iptables -C INPUT -p tcp --dport "$BORE_PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport "$BORE_PORT" -j ACCEPT
    info "Opened port $BORE_PORT (bore control)"
  fi

  # Allow SSH tunnel port
  if ! iptables -C INPUT -p tcp --dport "$SSH_TUNNEL_PORT" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport "$SSH_TUNNEL_PORT" -j ACCEPT
    info "Opened port $SSH_TUNNEL_PORT (SSH tunnel)"
  fi

  # Persist rules
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save 2>/dev/null || true
    info "iptables rules saved via netfilter-persistent"
  else
    warn "Install iptables-persistent to survive reboots: apt install -y iptables-persistent"
  fi
}

configure_firewall

# ── Step 4: systemd service ──────────────────────────────────────────────────
create_service() {
  local UNIT_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Bore Tunnel Server — Pocket Lab
Documentation=https://github.com/ekzhang/bore
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
ExecStart=${BORE_BIN} server --secret ${BORE_SECRET} --min-port ${SSH_TUNNEL_PORT}
Restart=always
RestartSec=5
Environment=RUST_LOG=info

# Hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=/

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl restart "$SERVICE_NAME"

  # Brief pause then check status
  sleep 2
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    info "systemd service '$SERVICE_NAME' is running"
  else
    err "Service failed to start. Check: journalctl -u $SERVICE_NAME -n 30"
    exit 1
  fi
}

create_service

# ── Step 5: Print client instructions ────────────────────────────────────────
VPS_IP=$(curl -s --max-time 5 ifconfig.me || echo "<YOUR_VPS_PUBLIC_IP>")

cat <<INSTRUCTIONS

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}  Bore tunnel server is live!${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

  VPS Public IP : ${VPS_IP}
  Bore Port     : ${BORE_PORT}
  SSH Tunnel    : ${SSH_TUNNEL_PORT}
  Secret File   : ${BORE_SECRET_FILE}

${YELLOW}── Oracle VCN Security List (manual step) ──${NC}

  Add these Ingress Rules in your VCN subnet's Security List:

  ┌──────────┬──────────┬───────────────┬──────────────────┐
  │ Protocol │ Src Port │ Dst Port      │ Source CIDR      │
  ├──────────┼──────────┼───────────────┼──────────────────┤
  │ TCP      │ All      │ ${BORE_PORT}          │ 0.0.0.0/0        │
  │ TCP      │ All      │ ${SSH_TUNNEL_PORT}          │ 0.0.0.0/0        │
  └──────────┴──────────┴───────────────┴──────────────────┘

${YELLOW}── iSH Client Command (paste into start-lab.sh) ──${NC}

  Replace the existing bore.pub line in /root/start-lab.sh with:

    bore local 22 --to ${VPS_IP}:${BORE_PORT} \\
      --port ${SSH_TUNNEL_PORT} \\
      --secret "${BORE_SECRET}"

  Then from anywhere, SSH into your iSH device:

    ssh -p ${SSH_TUNNEL_PORT} root@${VPS_IP}

${YELLOW}── Verify ──${NC}

  On VPS  : systemctl status ${SERVICE_NAME}
  Logs    : journalctl -u ${SERVICE_NAME} -f
  Test    : bore local 22 --to ${VPS_IP}:${BORE_PORT} --port ${SSH_TUNNEL_PORT} --secret "\$(cat ${BORE_SECRET_FILE})"

${GREEN}── Pocket Lab SSH via Oracle VPS (replaces bore.pub:40188) ──${NC}

  Perplexity Computer will use this going forward:
    ssh -o StrictHostKeyChecking=accept-new -p ${SSH_TUNNEL_PORT} root@${VPS_IP}

INSTRUCTIONS

info "Setup complete. Don't forget the Oracle VCN ingress rules above!"
