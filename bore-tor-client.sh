#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# bore-tor-client.sh — Pocket Lab iSH Tor-Bore Client
#
# Run this on iSH to connect to the Oracle VPS bore server through Tor.
# Replaces the old bore.pub connection that was getting hijacked.
#
# Usage:
#   chmod +x bore-tor-client.sh
#   ./bore-tor-client.sh
#
# First-time setup:
#   apk add tor bore
#   # Then edit ONION_ADDR and BORE_SECRET below with values from the VPS
# ─────────────────────────────────────────────────────────────────────────────

# ── Configuration (fill these from VPS setup output) ─────────────────────────
ONION_ADDR="${ONION_ADDR:-PASTE_YOUR_ONION_ADDRESS_HERE}"
BORE_SECRET="${BORE_SECRET:-PASTE_YOUR_SECRET_HERE}"
BORE_PORT="${BORE_PORT:-2200}"
SSH_TUNNEL_PORT="${SSH_TUNNEL_PORT:-2222}"
TOR_SOCKS="127.0.0.1:9050"

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo ""
echo "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo "${GREEN}║   Pocket Lab — Tor-Bore Client            ║${NC}"
echo "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# ── Check configuration ─────────────────────────────────────────────────────
if [ "$ONION_ADDR" = "PASTE_YOUR_ONION_ADDRESS_HERE" ]; then
  echo "${RED}[✗] Edit this script and set ONION_ADDR from VPS setup output${NC}"
  exit 1
fi
if [ "$BORE_SECRET" = "PASTE_YOUR_SECRET_HERE" ]; then
  echo "${RED}[✗] Edit this script and set BORE_SECRET from VPS setup output${NC}"
  exit 1
fi

# ── Ensure Tor is running ───────────────────────────────────────────────────
if ! pgrep -x tor >/dev/null 2>&1; then
  echo "${YELLOW}[!] Starting Tor...${NC}"
  tor &
  sleep 5

  # Wait for Tor to bootstrap
  TRIES=0
  while [ $TRIES -lt 30 ]; do
    if curl -sf --socks5 "$TOR_SOCKS" https://check.torproject.org/api/ip 2>/dev/null | grep -q "true"; then
      break
    fi
    sleep 2
    TRIES=$((TRIES + 1))
  done

  if [ $TRIES -ge 30 ]; then
    echo "${RED}[✗] Tor failed to connect. Check your network.${NC}"
    exit 1
  fi
  echo "${GREEN}[✓] Tor is connected${NC}"
else
  echo "${GREEN}[✓] Tor already running${NC}"
fi

# ── Ensure sshd is running ──────────────────────────────────────────────────
if ! pgrep -x sshd >/dev/null 2>&1 && ! pgrep -x dropbear >/dev/null 2>&1; then
  echo "${YELLOW}[!] Starting sshd...${NC}"
  if command -v sshd >/dev/null 2>&1; then
    /usr/sbin/sshd
  elif command -v dropbear >/dev/null 2>&1; then
    dropbear -R -p 22
  else
    echo "${RED}[✗] No SSH server found. Install openssh or dropbear.${NC}"
    exit 1
  fi
  echo "${GREEN}[✓] SSH server started${NC}"
else
  echo "${GREEN}[✓] SSH server already running${NC}"
fi

# ── Connect bore through Tor ────────────────────────────────────────────────
echo ""
echo "${GREEN}[→] Connecting bore to ${ONION_ADDR}:${BORE_PORT} via Tor...${NC}"
echo "${YELLOW}    Keep iSH in the foreground on iOS${NC}"
echo ""

# Use torsocks if available, otherwise ALL_PROXY
if command -v torsocks >/dev/null 2>&1; then
  exec torsocks bore local 22 \
    --to "${ONION_ADDR}:${BORE_PORT}" \
    --port "$SSH_TUNNEL_PORT" \
    --secret "$BORE_SECRET"
else
  exec env ALL_PROXY="socks5h://${TOR_SOCKS}" bore local 22 \
    --to "${ONION_ADDR}:${BORE_PORT}" \
    --port "$SSH_TUNNEL_PORT" \
    --secret "$BORE_SECRET"
fi
