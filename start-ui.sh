#!/usr/bin/env bash
# Intel AI Playground - Linux startup script
#
# Usage:
#   ./start-ui.sh             # Start normally (requires a display)
#   ./start-ui.sh --headless  # Start without a window; connect via browser
#
# After startup, open http://localhost:25413 in your browser.
#
# Window behaviour on Linux:
#   Closing the Electron window does NOT stop the AI services.
#   The services (Flask backend, LlamaCPP, etc.) keep running so you can
#   reconnect via http://localhost:25413 at any time without re-running
#   this script.
#
# To fully stop everything, press Ctrl+C in this terminal or run:
#   kill $(cat /tmp/aipg-electron.pid 2>/dev/null)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEBUI_DIR="$SCRIPT_DIR/WebUI"

# ── prerequisites ───────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "ERROR: node not found. Install Node.js 22+ (https://nodejs.org) and try again."
  exit 1
fi

NODE_MAJOR=$(node -e "process.stdout.write(String(process.versions.node.split('.')[0]))")
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "ERROR: Node.js 22+ required (found $(node --version))."
  echo "       Run: nvm install 22 && nvm use 22"
  exit 1
fi

if [ ! -d "$WEBUI_DIR/node_modules" ]; then
  echo "INFO: node_modules not found — running npm install..."
  cd "$WEBUI_DIR" && npm install --legacy-peer-deps
fi

UV_BIN="$SCRIPT_DIR/build/resources/uv"
if [ ! -x "$UV_BIN" ]; then
  echo "INFO: uv binary not found — fetching external resources..."
  cd "$WEBUI_DIR" && npm run fetch-external-resources
fi

# ── display check and auto-fix ────────────────────────────────────────────
# If DISPLAY is not set or has wrong format, try to detect VNC display
if [[ "$*" != *"--headless"* ]]; then
  if [ -z "${DISPLAY:-}" ] || [[ "${DISPLAY}" == localhost:* ]]; then
    # Check if Xvfb or VNC is running on :1
    if pgrep -f "Xvfb :1" >/dev/null || pgrep -f "x11vnc.*:1" >/dev/null; then
      export DISPLAY=:1
      echo "  Auto-detected VNC display, using DISPLAY=:1"
    elif pgrep -f "Xvfb :0" >/dev/null; then
      export DISPLAY=:0
      echo "  Auto-detected X display, using DISPLAY=:0"
    elif [ -z "${DISPLAY:-}" ]; then
      echo "WARNING: No display detected (DISPLAY not set)."
      echo "         On headless servers, use: ./start-ui.sh --headless"
      echo "         Or set: export DISPLAY=:1 before running this script."
    fi
  fi
fi

# ── cleanup on exit ─────────────────────────────────────────────────────────
# Store the PID so users can kill the stack from another terminal if needed.
PID_FILE="/tmp/aipg-electron.pid"

# Kill any previous instance of this app (electron + python backends)
_kill_previous() {
  echo "  Checking for previous instances..."

  # Kill all processes from this repo
  local killed=0

  # Kill electron processes from this directory
  if pkill -f "${SCRIPT_DIR}/WebUI/node_modules/electron" 2>/dev/null; then
    killed=1
  fi

  # Kill backend services
  pkill -f "${SCRIPT_DIR}/service.*web_api\.py" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/ComfyUI.*main\.py" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/LlamaCPP.*llama-server" 2>/dev/null || true

  # Kill npm processes in WebUI directory
  pkill -f "npm.*${SCRIPT_DIR}/WebUI" 2>/dev/null || true

  if [ $killed -eq 1 ]; then
    echo "  Stopped previous instance, waiting for cleanup..."
    sleep 2
  fi

  rm -f "$PID_FILE"
}
_kill_previous

# Cleanup function only for INT/TERM signals, NOT for normal exit
cleanup_on_signal() {
  echo ""
  echo "  Interrupted! Shutting down AI Playground..."
  # Kill all spawned subprocesses
  pkill -f "${SCRIPT_DIR}/WebUI/node_modules/electron" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/service.*web_api\.py" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/ComfyUI.*main\.py" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/LlamaCPP.*llama-server" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo "  Done. Goodbye."
  exit 1
}
# Only trap signals, NOT normal exit (since we run in background)
trap cleanup_on_signal INT TERM

# ── launch ──────────────────────────────────────────────────────────────────
cd "$WEBUI_DIR"

echo ""
echo "  ╔════════════════════════════════════════════════╗"
echo "  ║       Intel AI Playground — Linux              ║"
echo "  ╠════════════════════════════════════════════════╣"
echo "  ║  UI:          http://localhost:25413           ║"
echo "  ║  AI Backend:  http://localhost:59000           ║"
echo "  ╠════════════════════════════════════════════════╣"
echo "  ║  Closing the window keeps services running.   ║"
echo "  ║  Reconnect: http://localhost:25413             ║"
echo "  ║  Full quit: Ctrl+C in this terminal            ║"
echo "  ╚════════════════════════════════════════════════╝"
echo ""

# Start in background and detach
if [[ "$*" == *"--headless"* ]]; then
  # No display required — Electron is hidden; use browser to access the UI.
  ELECTRON_NO_ATTACH_CONSOLE=1 nohup npm run dev -- --no-sandbox > /tmp/aipg-ui.log 2>&1 &
else
  nohup npm run dev > /tmp/aipg-ui.log 2>&1 &
fi

NPM_PID=$!
echo $NPM_PID > "$PID_FILE"
disown

# Wait for services to start
echo "  Starting services..."
sleep 5

# Check if UI is accessible
for i in {1..30}; do
  if curl -s --max-time 1 http://localhost:25413 >/dev/null 2>&1; then
    echo ""
    echo "  ✓ AI Playground started successfully!"
    echo ""
    echo "  Access the UI:"
    echo "    • VNC:     Connect to your VNC viewer (display :1)"
    echo "    • Browser: http://localhost:25413"
    echo ""
    echo "  Logs: tail -f /tmp/aipg-ui.log"
    echo ""
    echo "  To stop: pkill -f 'npm run dev'"
    echo ""
    exit 0
  fi
  sleep 1
done

echo ""
echo "  ⚠ UI didn't respond within 30s. Check logs:"
echo "    tail -f /tmp/aipg-ui.log"
echo ""
exit 1
