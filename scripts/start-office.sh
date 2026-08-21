#!/usr/bin/env bash
# start-office — Start the Claude3D: OpenClaw gateway + Studio app.
#
# Setup (once):
#   echo 'alias office="$HOME/Claude3D/scripts/start-office.sh"' >> ~/.bashrc
#   source ~/.bashrc
#
# Then just run:  office
#
# The gateway is left alone if it is already running (manually or via the
# systemd user service installed by scripts/install-gateway-service.sh).

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
OFFICE_DIR="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
LOG_DIR="/tmp/claude3d-logs"
mkdir -p "$LOG_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[office]${NC} $*"; }
warn() { echo -e "${YELLOW}[office]${NC} $*"; }
info() { echo -e "${BLUE}[office]${NC} $*"; }
err()  { echo -e "${RED}[office]${NC} $*"; }

GATEWAY_PORT="${GATEWAY_PORT:-18789}"
APP_PORT="${PORT:-3000}"

# ── Helpers ───────────────────────────────────────────────────────────────────

# True if anything is listening on the given port.
port_in_use() {
  ss -ltn "sport = :$1" 2>/dev/null | grep -q LISTEN
}

# First free port at or above the given one.
find_free_port() {
  local p=$1
  while port_in_use "$p"; do p=$((p + 1)); done
  echo "$p"
}

# True if our Studio app answers on the given port (its health route is unique).
office_responds_on() {
  curl -sf --max-time 2 "http://localhost:$1/api/health" 2>/dev/null | grep -q '"ok":true'
}

# ── 1. OpenClaw gateway (default :18789) ─────────────────────────────────────
if port_in_use "$GATEWAY_PORT"; then
  log "Gateway already listening on :$GATEWAY_PORT — reusing."
elif systemctl --user list-unit-files openclaw-gateway.service >/dev/null 2>&1 &&
     systemctl --user cat openclaw-gateway.service >/dev/null 2>&1; then
  log "Starting gateway via systemd user service..."
  systemctl --user start openclaw-gateway.service || true
  for _ in $(seq 1 20); do port_in_use "$GATEWAY_PORT" && break; sleep 0.5; done
  port_in_use "$GATEWAY_PORT" \
    && log "Gateway up on :$GATEWAY_PORT." \
    || warn "Gateway did not come up — check: journalctl --user -u openclaw-gateway -n 50"
elif command -v openclaw >/dev/null 2>&1; then
  log "Starting gateway on :$GATEWAY_PORT..."
  nohup openclaw gateway run --bind loopback --port "$GATEWAY_PORT" \
    > "$LOG_DIR/openclaw-gateway.log" 2>&1 &
  for _ in $(seq 1 30); do port_in_use "$GATEWAY_PORT" && break; sleep 0.5; done
  port_in_use "$GATEWAY_PORT" \
    && log "Gateway up on :$GATEWAY_PORT." \
    || warn "Gateway did not come up — check $LOG_DIR/openclaw-gateway.log"
else
  warn "openclaw not found on PATH — starting the app without a gateway."
  warn "Agents will be unavailable; the Demo backend still works."
fi

# ── 2. Studio app (default :3000) ────────────────────────────────────────────
if [ ! -d "$OFFICE_DIR/node_modules" ]; then
  log "Installing dependencies (first run)..."
  (cd "$OFFICE_DIR" && npm install --no-audit --no-fund)
fi

if office_responds_on "$APP_PORT"; then
  log "Office already running on :$APP_PORT — reusing."
else
  if port_in_use "$APP_PORT"; then
    APP_PORT=$(find_free_port $((APP_PORT + 1)))
    warn "Port ${PORT:-3000} is taken by something else → using :$APP_PORT."
  fi
  log "Starting office dev server on :$APP_PORT..."
  (cd "$OFFICE_DIR" && nohup env PORT="$APP_PORT" npm run dev \
    > "$LOG_DIR/office-dev.log" 2>&1 &)

  log "Waiting for the office to be ready..."
  ready=0
  for _ in $(seq 1 90); do
    if office_responds_on "$APP_PORT"; then ready=1; break; fi
    sleep 1
  done
  if [ "$ready" -eq 0 ]; then
    err "Timed out waiting for :$APP_PORT — check $LOG_DIR/office-dev.log"
    exit 1
  fi
fi

# ── 3. Open the browser ──────────────────────────────────────────────────────
OFFICE_URL="http://localhost:$APP_PORT/office"
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$OFFICE_URL" >/dev/null 2>&1 &
fi

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log " Office      →  $OFFICE_URL"
info " Gateway WS  →  ws://localhost:$GATEWAY_PORT"
info " Logs        →  $LOG_DIR/"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
