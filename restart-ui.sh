#!/usr/bin/env bash
# Restart AI Playground on VNC display :1
#
# Usage:
#   ./restart-ui.sh           # stop + start
#   ./restart-ui.sh stop      # stop only
#   ./restart-ui.sh start     # start only (no stop first)
#   ./restart-ui.sh status    # show process + port status
#   ./restart-ui.sh logs      # tail the app log
#
# Requires:
#   - VNC server running on :1 (start with: vncserver :1)
#   - Node 22 via nvm

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_DIR="$SCRIPT_DIR/WebUI"
LOG_FILE="/tmp/app-log.txt"
DISPLAY_NUM=":1"

# Proxy config (respects /etc/environment but exports for child processes).
# Remove or comment out these lines if you don't need a proxy.
export http_proxy="${http_proxy:-http://proxy-dmz.intel.com:911}"
export https_proxy="${https_proxy:-http://proxy-dmz.intel.com:911}"
export HTTP_PROXY="${HTTP_PROXY:-$http_proxy}"
export HTTPS_PROXY="${HTTPS_PROXY:-$https_proxy}"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.0/8,*.intel.com}"
export no_proxy="${no_proxy:-$NO_PROXY}"

# Load nvm so `node` / `npm` are available in this shell.
if [ -s "$HOME/.nvm/nvm.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1
  nvm use 22 >/dev/null 2>&1 || true
fi

stop_app() {
  echo "Stopping AI Playground processes..."
  pkill -f "electron \."           2>/dev/null || true
  pkill -f "electron --type"       2>/dev/null || true
  pkill -f "node_modules/.bin/vite" 2>/dev/null || true
  pkill -f "cross-env.*vite"       2>/dev/null || true
  pkill -f "xvfb-run"              2>/dev/null || true

  # Wait up to 5s for graceful shutdown.
  for _ in 1 2 3 4 5; do
    if ! pgrep -f "electron \.|cross-env.*vite|node_modules/.bin/vite" >/dev/null; then
      break
    fi
    sleep 1
  done

  # Hard kill if anything survived.
  pkill -9 -f "electron \."           2>/dev/null || true
  pkill -9 -f "node_modules/.bin/vite" 2>/dev/null || true

  echo "Stopped."
}

start_app() {
  if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: node not found. Run: nvm install 22 && nvm use 22"
    exit 1
  fi

  # Check VNC is running on :1; if not, start it.
  if ! pgrep -f "Xtigervnc $DISPLAY_NUM" >/dev/null; then
    echo "VNC display $DISPLAY_NUM not running — starting vncserver..."
    vncserver "$DISPLAY_NUM" -geometry 1600x900 -depth 24 -localhost no >/dev/null 2>&1 || {
      echo "WARNING: could not start vncserver automatically. Run: vncserver $DISPLAY_NUM"
    }
  fi

  echo "Starting AI Playground on DISPLAY=$DISPLAY_NUM..."
  rm -f "$LOG_FILE"

  cd "$SCRIPT_DIR"
  # Launch via `sg render` so the spawned services have access to /dev/dri/renderD*
  # without requiring a logout/login after the user was added to the render group.
  if id -nG | grep -qw render; then
    DISPLAY="$DISPLAY_NUM" nohup bash -c "cd '$WEBUI_DIR' && npm run dev" \
      > "$LOG_FILE" 2>&1 &
  else
    DISPLAY="$DISPLAY_NUM" nohup sg render -c "cd '$WEBUI_DIR' && npm run dev" \
      > "$LOG_FILE" 2>&1 &
  fi
  disown

  # Wait up to 45s for the UI port to come up.
  for i in $(seq 1 45); do
    sleep 1
    if curl -s --max-time 1 -o /dev/null -w '%{http_code}' http://127.0.0.1:25413 \
         | grep -q '^200$'; then
      echo "UI ready at http://127.0.0.1:25413  (after ${i}s)"
      echo "VNC:  connect to <host>:5901  (password: aipg1234)"
      echo "Log:  tail -f $LOG_FILE"
      return 0
    fi
  done

  echo "WARNING: UI did not respond within 45s. Check: tail $LOG_FILE"
  return 1
}

show_status() {
  echo "=== Processes ==="
  pgrep -af "Xtigervnc|electron \.|vite|xfce4-session" 2>/dev/null || echo "none"
  echo ""
  echo "=== Listening ports ==="
  ss -tlnp 2>/dev/null | grep LISTEN \
    | grep -E ":25413|:29222|:5901|:59000|:39000|:29000|:49000" \
    || echo "no app ports open"
  echo ""
  echo "=== HTTP ==="
  curl -s --max-time 2 -o /dev/null -w "UI (25413):      %{http_code}\n" http://127.0.0.1:25413
  curl -s --max-time 2 -o /dev/null -w "AI Backend (59000): %{http_code}\n" http://127.0.0.1:59000/healthy
  curl -s --max-time 2 -o /dev/null -w "LlamaCPP (39000):   %{http_code}\n" http://127.0.0.1:39000/health
}

case "${1:-restart}" in
  stop)    stop_app ;;
  start)   start_app ;;
  status)  show_status ;;
  logs)    tail -f "$LOG_FILE" ;;
  restart|"") stop_app; sleep 2; start_app ;;
  *)       echo "Usage: $0 {restart|stop|start|status|logs}"; exit 1 ;;
esac
