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

UV_BIN="$WEBUI_DIR/build/resources/uv"
if [ ! -x "$UV_BIN" ]; then
  echo "INFO: uv binary not found — fetching external resources..."
  cd "$WEBUI_DIR" && npm run fetch-external-resources
fi

# ── display check ───────────────────────────────────────────────────────────
if [[ "$*" != *"--headless"* ]] && [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "WARNING: No display detected (DISPLAY/WAYLAND_DISPLAY not set)."
  echo "         On WSL2, WSLg usually sets DISPLAY automatically."
  echo "         On headless servers, use: ./start-ui.sh --headless"
  echo "         Or set: export DISPLAY=:0 before running this script."
fi

# ── cleanup on exit ─────────────────────────────────────────────────────────
# Store the PID so users can kill the stack from another terminal if needed.
PID_FILE="/tmp/aipg-electron.pid"

cleanup() {
  echo ""
  echo "  Shutting down AI Playground..."
  # kill the npm child if it is still running
  if [ -n "${NPM_PID:-}" ] && kill -0 "$NPM_PID" 2>/dev/null; then
    kill "$NPM_PID" 2>/dev/null || true
    wait "$NPM_PID" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "  Done. Goodbye."
}
trap cleanup INT TERM EXIT

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

if [[ "$*" == *"--headless"* ]]; then
  # No display required — Electron is hidden; use browser to access the UI.
  ELECTRON_NO_ATTACH_CONSOLE=1 npm run dev -- --no-sandbox &
else
  npm run dev &
fi

NPM_PID=$!
echo $NPM_PID > "$PID_FILE"
wait "$NPM_PID"
