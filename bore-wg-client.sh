#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# bore-wg-client.sh — Pocket Lab iSH WireGuard-Bore Client
#
# Run this on iSH AFTER enabling WireGuard on your iPhone.
# The WireGuard iOS app handles the encrypted tunnel — this script
# just connects bore through it.
#
# Usage:
#   chmod +x bore-wg-client.sh
#   ./bore-wg-client.sh
# ─────────────────────────────────────────────────────────────────────────────

# ── Configuration ────────────────────────────────────────────────────────────
WG_SERVER_IP="${WG_SERVER_IP:-10.0.0.1}"
BORE_PORT="${BORE_PORT:-2200}"
SSH_TUNNEL_PORT="${SSH_TUNNEL_PORT:-2222}"
BORE_SECRET="${BORE_SECRET:-PASTE_YOUR_SECRET_HERE}"

# ── Colors ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo ""
echo "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo "${GREEN}║   Pocket Lab — WireGuard Bore Client      ║${NC}"
echo "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# ── Check configuration ─────────────────────────────────────────────────────
if [ "$BORE_SECRET" = "PASTE_YOUR_SECRET_HERE" ]; then
  echo "${RED}[✗] Edit this script and set BORE_SECRET from VPS setup output${NC}"
  echo "    Or set it via env: BORE_SECRET=xxx ./bore-wg-client.sh"
  exit 1
fi

# ── Check WireGuard connectivity ────────────────────────────────────────────
echo "${YELLOW}[→] Checking WireGuard tunnel to ${WG_SERVER_IP}...${NC}"

if ping -c 1 -W 3 "$WG_SERVER_IP" >/dev/null 2>&1; then
  echo "${GREEN}[✓] WireGuard tunnel is active${NC}"
else
  echo "${RED}[✗] Cannot reach ${WG_SERVER_IP}${NC}"
  echo ""
  echo "    Make sure WireGuard is ON in the iOS WireGuard app."
  echo "    Open WireGuard app → toggle Pocket Lab tunnel ON"
  echo ""
  exit 1
fi

# ── Ensure sshd is running ──────────────────────────────────────────────────
if ! pgrep -x sshd >/dev/null 2>&1 && ! pgrep -x dropbear >/dev/null 2>&1; then
  echo "${YELLOW}[!] Starting sshd...${NC}"
  if command -v sshd >/dev/null 2>&1; then
    /usr/sbin/sshd
  elif command -v dropbear >/dev/null 2>&1; then
    dropbear -R -p 22
  else
    echo "${RED}[✗] No SSH server found. Run: apk add openssh${NC}"
    exit 1
  fi
  echo "${GREEN}[✓] SSH server started on port 22${NC}"
else
  echo "${GREEN}[✓] SSH server already running${NC}"
fi

# ── Connect bore through WireGuard ──────────────────────────────────────────
echo ""
echo "${GREEN}[→] Connecting bore to ${WG_SERVER_IP}:${BORE_PORT}...${NC}"
echo "${GREEN}    SSH will be available at VPS_PUBLIC_IP:${SSH_TUNNEL_PORT}${NC}"
echo "${YELLOW}    WireGuard keeps tunnel alive even if iSH is backgrounded${NC}"
echo ""

exec bore local 22 \
  --to "${WG_SERVER_IP}:${BORE_PORT}" \
  --port "$SSH_TUNNEL_PORT" \
  --secret "$BORE_SECRET"
