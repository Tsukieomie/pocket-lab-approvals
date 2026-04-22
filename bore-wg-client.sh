#!/bin/sh
# ─────────────────────────────────────────────────────────────────────────────
# bore-client.sh — Pocket Lab iSH Bore Client (bore.pub)
#
# Connects iSH SSH to bore.pub so Perplexity Computer can reach it.
#
# Usage:
#   chmod +x bore-client.sh
#   ./bore-client.sh
# ─────────────────────────────────────────────────────────────────────────────

BORE_HOST="${BORE_HOST:-bore.pub}"
BORE_SECRET="${BORE_SECRET:-}"
SSH_PORT="${SSH_PORT:-2222}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo ""
echo "${GREEN}╔═══════════════════════════════════════════╗${NC}"
echo "${GREEN}║      Pocket Lab — bore.pub Client         ║${NC}"
echo "${GREEN}╚═══════════════════════════════════════════╝${NC}"
echo ""

# Ensure sshd is running
if ! pgrep -x sshd >/dev/null 2>&1 && ! pgrep -x dropbear >/dev/null 2>&1; then
  echo "${YELLOW}[!] Starting sshd...${NC}"
  if command -v dropbear >/dev/null 2>&1; then
    dropbear -R -p "$SSH_PORT"
  elif command -v sshd >/dev/null 2>&1; then
    /usr/sbin/sshd
  else
    echo "${RED}[✗] No SSH server found. Run: apk add openssh${NC}"
    exit 1
  fi
  echo "${GREEN}[✓] SSH server started${NC}"
else
  echo "${GREEN}[✓] SSH server already running${NC}"
fi

# Build bore args
BORE_ARGS="local $SSH_PORT --to $BORE_HOST"
[ -n "$BORE_SECRET" ] && BORE_ARGS="$BORE_ARGS --secret $BORE_SECRET"

echo "${GREEN}[→] Connecting to ${BORE_HOST}...${NC}"
echo "${YELLOW}    Tell Perplexity Computer the port it prints below${NC}"
echo ""

exec bore $BORE_ARGS
