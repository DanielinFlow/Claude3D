#!/usr/bin/env bash
# install-gateway-service — Run the OpenClaw gateway as a systemd user service,
# so it survives logout/reboot instead of living in a terminal.
#
#   ./scripts/install-gateway-service.sh            # install + start
#   ./scripts/install-gateway-service.sh --uninstall
#
# The unit runs `openclaw gateway run --bind loopback --port <port>` as your
# own user. Gateway auth/model configuration is untouched — this only changes
# how the process is supervised.

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GREEN}[gateway-service]${NC} $*"; }
warn() { echo -e "${YELLOW}[gateway-service]${NC} $*"; }
err()  { echo -e "${RED}[gateway-service]${NC} $*"; }

UNIT_NAME="openclaw-gateway.service"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_PATH="$UNIT_DIR/$UNIT_NAME"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"

command -v systemctl >/dev/null 2>&1 || { err "systemctl not found — this system does not use systemd."; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
  rm -f "$UNIT_PATH"
  systemctl --user daemon-reload 2>/dev/null || true
  log "Removed $UNIT_NAME."
  exit 0
fi


OPENCLAW_BIN="$(command -v openclaw || true)"
if [ -z "$OPENCLAW_BIN" ]; then
  err "openclaw not found on PATH. Install it first:  npm install -g openclaw"
  exit 1
fi
# systemd does not source your shell profile, so nvm's bin dir must be explicit.
NODE_BIN_DIR="$(dirname -- "$OPENCLAW_BIN")"

# A gateway already bound to the port would make the service fail to start.
if ss -ltn "sport = :$GATEWAY_PORT" 2>/dev/null | grep -q LISTEN; then
  if ! systemctl --user is-active --quiet "$UNIT_NAME" 2>/dev/null; then
    warn "Something is already listening on :$GATEWAY_PORT (a gateway you started by hand?)."
    warn "Stop it first (Ctrl+C in its terminal), then re-run this script."
    exit 1
  fi
fi

mkdir -p "$UNIT_DIR"
cat > "$UNIT_PATH" <<UNIT
[Unit]
Description=OpenClaw Gateway (Claude3D runtime)
Documentation=https://docs.openclaw.ai/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$OPENCLAW_BIN gateway run --bind loopback --port $GATEWAY_PORT
Environment=PATH=$NODE_BIN_DIR:/usr/local/bin:/usr/bin:/bin
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
UNIT

log "Wrote $UNIT_PATH"
systemctl --user daemon-reload
systemctl --user enable --now "$UNIT_NAME"

for _ in $(seq 1 30); do
  ss -ltn "sport = :$GATEWAY_PORT" 2>/dev/null | grep -q LISTEN && break
  sleep 0.5
done

if ss -ltn "sport = :$GATEWAY_PORT" 2>/dev/null | grep -q LISTEN; then
  log "Gateway is up on :$GATEWAY_PORT and enabled at login."
else
  err "Service started but nothing is listening on :$GATEWAY_PORT."
  err "Check:  journalctl --user -u $UNIT_NAME -n 50 --no-pager"
  exit 1
fi

cat <<TIPS

  Status   systemctl --user status $UNIT_NAME
  Logs     journalctl --user -u $UNIT_NAME -f
  Stop     systemctl --user stop $UNIT_NAME
  Remove   ./scripts/install-gateway-service.sh --uninstall

  To keep the gateway running when you are not logged in (e.g. after a
  reboot, before your first login), enable lingering once:

      sudo loginctl enable-linger $USER

TIPS
