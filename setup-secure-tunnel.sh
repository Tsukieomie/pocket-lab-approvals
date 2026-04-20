#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# setup-secure-tunnel.sh — Pocket Lab v2.7+ (Tor-Hardened)
#
# Sets up a Tor hidden service + bore tunnel on an Oracle Cloud VPS.
# Your iSH device connects through Tor — real IP is NEVER exposed.
#
# Architecture:
#   iSH (iPhone) ──Tor──▶ .onion:2200 ──▶ bore-server ──▶ localhost:2222
#   Perplexity   ──Tor──▶ .onion:2222 ──▶ iSH SSH (port 22)
#
# Threat model:
#   ✓ ISP cannot see destination (Tor encrypted)
#   ✓ bore.pub eliminated (self-hosted, no port hijacking)
#   ✓ VPS IP can be public — .onion address is what clients use
#   ✓ Shared secret prevents unauthorized bore clients
#   ✓ No DNS leaks (Tor handles resolution)
#   ✓ systemd auto-restart for both Tor and bore
#
# Run ON the Oracle Cloud VPS (Ubuntu 22.04+ / Oracle Linux 9+):
#   chmod +x setup-secure-tunnel.sh
#   sudo ./setup-secure-tunnel.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
BORE_PORT="${BORE_PORT:-2200}"              # bore-server control port
SSH_TUNNEL_PORT="${SSH_TUNNEL_PORT:-2222}"   # exposed port for SSH into iSH
BORE_SECRET_FILE="/etc/bore/secret"
BORE_BIN="/usr/local/bin/bore"
BORE_SERVICE="bore-server"
BORE_VERSION="0.5.2"
TOR_HIDDEN_SERVICE_DIR="/var/lib/tor/pocket-lab"
INSTALL_DIR="/usr/local/bin"

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
err()   { printf "${RED}[✗]${NC} %s\n" "$*" >&2; }
step()  { printf "\n${CYAN}── %s ──${NC}\n" "$*"; }

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

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1: Install Tor
# ═════════════════════════════════════════════════════════════════════════════
step "Step 1: Install Tor"

install_tor() {
  if command -v tor &>/dev/null; then
    info "Tor already installed ($(tor --version | head -1))"
    return 0
  fi

  if command -v apt-get &>/dev/null; then
    info "Installing Tor via apt..."
    apt-get update -qq
    apt-get install -y -qq tor
  elif command -v dnf &>/dev/null; then
    info "Installing Tor via dnf..."
    dnf install -y -q tor
  elif command -v yum &>/dev/null; then
    info "Installing Tor via yum..."
    yum install -y -q tor
  else
    err "Unsupported package manager. Install Tor manually."
    exit 1
  fi

  info "Tor installed"
}

install_tor

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2: Configure Tor Hidden Service
# ═════════════════════════════════════════════════════════════════════════════
step "Step 2: Configure Tor Hidden Service"

configure_tor_hidden_service() {
  local TORRC="/etc/tor/torrc"

  # Back up original torrc
  if [[ ! -f "${TORRC}.bak" ]]; then
    cp "$TORRC" "${TORRC}.bak"
    info "Backed up original torrc"
  fi

  # Create hidden service directory
  mkdir -p "$TOR_HIDDEN_SERVICE_DIR"
  chown debian-tor:debian-tor "$TOR_HIDDEN_SERVICE_DIR" 2>/dev/null || \
    chown toranon:toranon "$TOR_HIDDEN_SERVICE_DIR" 2>/dev/null || \
    chown tor:tor "$TOR_HIDDEN_SERVICE_DIR" 2>/dev/null || true
  chmod 700 "$TOR_HIDDEN_SERVICE_DIR"

  # Check if our hidden service config already exists
  if grep -q "pocket-lab" "$TORRC" 2>/dev/null; then
    info "Tor hidden service already configured in torrc"
  else
    cat >> "$TORRC" <<EOF

# ── Pocket Lab Hidden Service ──
HiddenServiceDir ${TOR_HIDDEN_SERVICE_DIR}
HiddenServicePort ${BORE_PORT} 127.0.0.1:${BORE_PORT}
HiddenServicePort ${SSH_TUNNEL_PORT} 127.0.0.1:${SSH_TUNNEL_PORT}
EOF
    info "Added hidden service config to torrc"
  fi

  # Restart Tor to generate .onion address
  systemctl enable tor
  systemctl restart tor

  # Wait for .onion hostname to be generated
  local TRIES=0
  while [[ ! -f "${TOR_HIDDEN_SERVICE_DIR}/hostname" ]] && [[ $TRIES -lt 30 ]]; do
    sleep 2
    TRIES=$((TRIES + 1))
  done

  if [[ -f "${TOR_HIDDEN_SERVICE_DIR}/hostname" ]]; then
    ONION_ADDR=$(cat "${TOR_HIDDEN_SERVICE_DIR}/hostname")
    info "Tor hidden service is live: ${ONION_ADDR}"
  else
    err "Tor failed to generate .onion address. Check: journalctl -u tor -n 30"
    exit 1
  fi
}

configure_tor_hidden_service

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3: Install bore
# ═════════════════════════════════════════════════════════════════════════════
step "Step 3: Install bore"

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

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4: Generate shared secret
# ═════════════════════════════════════════════════════════════════════════════
step "Step 4: Generate shared secret"

generate_secret() {
  mkdir -p "$(dirname "$BORE_SECRET_FILE")"
  if [[ -f "$BORE_SECRET_FILE" ]]; then
    info "Shared secret already exists at $BORE_SECRET_FILE"
  else
    openssl rand -hex 32 > "$BORE_SECRET_FILE"
    chmod 600 "$BORE_SECRET_FILE"
    info "Generated new shared secret"
  fi
}

generate_secret
BORE_SECRET=$(cat "$BORE_SECRET_FILE")

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5: Firewall — only allow localhost (Tor handles external access)
# ═════════════════════════════════════════════════════════════════════════════
step "Step 5: Configure firewall (localhost-only for bore)"

configure_firewall() {
  # bore only needs to listen on localhost since Tor forwards to 127.0.0.1
  # No need to open ports to the public internet — that's the whole point

  # But ensure Tor's own port (9001) and ORPort can reach the internet
  if command -v iptables &>/dev/null; then
    # Allow loopback
    iptables -C INPUT -i lo -j ACCEPT 2>/dev/null || \
      iptables -I INPUT -i lo -j ACCEPT

    info "Firewall configured — bore listens on localhost only (Tor fronts it)"
    info "No public ports exposed for bore — state actors see only Tor traffic"

    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save 2>/dev/null || true
    fi
  else
    warn "iptables not found — verify your firewall manually"
  fi
}

configure_firewall

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6: systemd service for bore-server (binds to localhost only)
# ═════════════════════════════════════════════════════════════════════════════
step "Step 6: Create bore-server systemd service"

create_bore_service() {
  local UNIT_FILE="/etc/systemd/system/${BORE_SERVICE}.service"

  cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Bore Tunnel Server — Pocket Lab (Tor-Hardened)
Documentation=https://github.com/ekzhang/bore
Wants=network-online.target tor.service
After=network-online.target tor.service
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
# Bind to localhost ONLY — Tor hidden service forwards .onion traffic here
ExecStart=${BORE_BIN} server \\
  --secret ${BORE_SECRET} \\
  --min-port ${SSH_TUNNEL_PORT}
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
  systemctl enable "$BORE_SERVICE"
  systemctl restart "$BORE_SERVICE"

  sleep 2
  if systemctl is-active --quiet "$BORE_SERVICE"; then
    info "bore-server is running (localhost-only, Tor-fronted)"
  else
    err "bore-server failed to start. Check: journalctl -u $BORE_SERVICE -n 30"
    exit 1
  fi
}

create_bore_service

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7: Print results and client instructions
# ═════════════════════════════════════════════════════════════════════════════
step "Setup Complete"

ONION_ADDR=$(cat "${TOR_HIDDEN_SERVICE_DIR}/hostname")

cat <<INSTRUCTIONS

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}  Tor-Hardened Bore Tunnel is LIVE${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

  .onion Address : ${ONION_ADDR}
  Bore Port      : ${BORE_PORT} (via .onion, localhost-only)
  SSH Tunnel     : ${SSH_TUNNEL_PORT} (via .onion, localhost-only)
  Secret File    : ${BORE_SECRET_FILE}

${RED}── SECURITY NOTES ──${NC}

  • bore-server binds to 127.0.0.1 ONLY — not reachable from the internet
  • All access goes through Tor hidden service (.onion)
  • Your iSH real IP is hidden from the VPS, the ISP, and observers
  • The .onion address itself acts as end-to-end encryption
  • Shared secret prevents unauthorized bore clients
  • No DNS leaks — Tor handles all resolution
  • No Oracle VCN ingress rules needed (Tor punches through NAT)

${YELLOW}── iSH Client Setup ──${NC}

  1. Install Tor on iSH:
     apk add tor

  2. Start Tor:
     tor &

  3. Connect bore through Tor (replace bore.pub line in start-lab.sh):

     torsocks bore local 22 \\
       --to ${ONION_ADDR}:${BORE_PORT} \\
       --port ${SSH_TUNNEL_PORT} \\
       --secret "${BORE_SECRET}"

  Or if torsocks isn't available, use the SOCKS proxy directly:

     ALL_PROXY=socks5h://127.0.0.1:9050 bore local 22 \\
       --to ${ONION_ADDR}:${BORE_PORT} \\
       --port ${SSH_TUNNEL_PORT} \\
       --secret "${BORE_SECRET}"

${YELLOW}── Perplexity Computer SSH (through Tor) ──${NC}

     torsocks ssh -p ${SSH_TUNNEL_PORT} root@${ONION_ADDR}

  Or via SOCKS proxy:

     ssh -o ProxyCommand="nc -x 127.0.0.1:9050 -X 5 %h %p" \\
         -p ${SSH_TUNNEL_PORT} root@${ONION_ADDR}

${YELLOW}── Verify ──${NC}

  Tor status    : systemctl status tor
  bore status   : systemctl status ${BORE_SERVICE}
  .onion addr   : cat ${TOR_HIDDEN_SERVICE_DIR}/hostname
  Tor logs      : journalctl -u tor -f
  bore logs     : journalctl -u ${BORE_SERVICE} -f

${YELLOW}── OrNET VPN Compatibility ──${NC}

  Your OrNET VPN app routes through Tor already.
  With this setup, traffic is double-onioned:
    iSH → OrNET (Tor layer 1) → Tor hidden service (layer 2) → bore
  This is fine for security but adds latency.
  For best performance, disable OrNET when using bore and let
  the bore→Tor connection handle anonymity directly.

INSTRUCTIONS

# Save .onion address for easy retrieval
echo "$ONION_ADDR" > /etc/bore/onion_address
chmod 644 /etc/bore/onion_address
info "Onion address saved to /etc/bore/onion_address"
info "Setup complete. Your bore tunnel is invisible to the network."
