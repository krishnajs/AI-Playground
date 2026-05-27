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

# ── proxy propagation ───────────────────────────────────────────────────────
# Electron's postinstall (@electron/get + got) does NOT pick up the npm proxy
# nor the lowercase `https_proxy` env var reliably. Forward whatever the user
# has set so corporate proxies (e.g. Intel's proxy-dmz) keep working.
if [ -n "${https_proxy:-${HTTPS_PROXY:-}}" ]; then
  export HTTPS_PROXY="${https_proxy:-$HTTPS_PROXY}"
  export HTTP_PROXY="${http_proxy:-${HTTP_PROXY:-$HTTPS_PROXY}}"
  export GLOBAL_AGENT_HTTPS_PROXY="$HTTPS_PROXY"
  export GLOBAL_AGENT_HTTP_PROXY="$HTTP_PROXY"
  export GLOBAL_AGENT_NO_PROXY="${no_proxy:-${NO_PROXY:-localhost,127.0.0.1}}"
  echo "INFO: forwarding HTTPS_PROXY=$HTTPS_PROXY to child processes"
fi

# ── electron binary cache (works around @electron/get ignoring proxies) ─────
# Electron's postinstall (`node install.js`) uses `@electron/get` → `got`,
# which does NOT honor HTTPS_PROXY env vars reliably. The reliable workaround
# is to pre-extract the electron binary and point the installer at it via
# ELECTRON_OVERRIDE_DIST_PATH — the postinstall then skips the network call
# entirely. The pinned electron version is read from WebUI/package.json.
ELECTRON_VERSION=$(node -e "console.log(require('$WEBUI_DIR/package.json').devDependencies.electron.replace(/^[^\d]*/, ''))" 2>/dev/null || echo "")
if [ -n "$ELECTRON_VERSION" ]; then
  ELECTRON_DIST_DIR="$HOME/.cache/electron/electron-v${ELECTRON_VERSION}-linux-x64"
  ELECTRON_ZIP="$HOME/.cache/electron/electron-v${ELECTRON_VERSION}-linux-x64.zip"
  if [ ! -x "$ELECTRON_DIST_DIR/electron" ] && [ -f "$ELECTRON_ZIP" ]; then
    echo "INFO: extracting cached electron zip → $ELECTRON_DIST_DIR"
    mkdir -p "$ELECTRON_DIST_DIR"
    (cd "$ELECTRON_DIST_DIR" && unzip -oq "$ELECTRON_ZIP")
  fi
  if [ ! -x "$ELECTRON_DIST_DIR/electron" ] && command -v curl >/dev/null 2>&1; then
    echo "INFO: downloading electron v${ELECTRON_VERSION} via curl (honors HTTPS_PROXY)"
    mkdir -p "$(dirname "$ELECTRON_ZIP")" "$ELECTRON_DIST_DIR"
    if curl -fL --retry 3 --connect-timeout 30 \
        "https://github.com/electron/electron/releases/download/v${ELECTRON_VERSION}/electron-v${ELECTRON_VERSION}-linux-x64.zip" \
        -o "$ELECTRON_ZIP"; then
      (cd "$ELECTRON_DIST_DIR" && unzip -oq "$ELECTRON_ZIP")
    else
      echo "WARN: curl download of electron failed; postinstall will retry"
      rm -f "$ELECTRON_ZIP"
    fi
  fi
  if [ -x "$ELECTRON_DIST_DIR/electron" ]; then
    export ELECTRON_OVERRIDE_DIST_PATH="$ELECTRON_DIST_DIR"
    export ELECTRON_SKIP_BINARY_DOWNLOAD=1
    echo "INFO: ELECTRON_OVERRIDE_DIST_PATH=$ELECTRON_OVERRIDE_DIST_PATH"
  fi
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

  # Kill electron processes launched for this repo (cached electron path)
  if pkill -f "${HOME}/.cache/electron/electron-v.*-linux-x64/electron \\. --no-sandbox" 2>/dev/null; then
    killed=1
  fi

  # Kill vite/dev launcher processes for this repo
  if pkill -f "${SCRIPT_DIR}/WebUI/node_modules/.bin/vite" 2>/dev/null; then
    killed=1
  fi
  if pkill -f "${SCRIPT_DIR}/WebUI/node_modules/.bin/cross-env" 2>/dev/null; then
    killed=1
  fi
  if pkill -f "xvfb-run -a --server-args=-screen 0 1280x800x24 npm run dev" 2>/dev/null; then
    killed=1
  fi
  if pkill -f "npm run dev" 2>/dev/null; then
    killed=1
  fi

  # Kill backend services
  pkill -f "${SCRIPT_DIR}/service.*web_api\.py" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/ComfyUI.*main\.py" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/LlamaCPP.*llama-server" 2>/dev/null || true

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
  pkill -f "${HOME}/.cache/electron/electron-v.*-linux-x64/electron \\. --no-sandbox" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/WebUI/node_modules/.bin/vite" 2>/dev/null || true
  pkill -f "${SCRIPT_DIR}/WebUI/node_modules/.bin/cross-env" 2>/dev/null || true
  pkill -f "xvfb-run -a --server-args=-screen 0 1280x800x24 npm run dev" 2>/dev/null || true
  pkill -f "npm run dev" 2>/dev/null || true
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
  # NOTE: --no-sandbox is applied to electron via vite.config.mts (Linux branch),
  # NOT passed to vite here (vite would reject it as an unknown option).
  # Electron still needs an X server even when its window is hidden, because
  # the renderer initializes ozone/X11. xvfb-run provides a virtual display.
  if command -v xvfb-run >/dev/null 2>&1; then
    ELECTRON_NO_ATTACH_CONSOLE=1 nohup xvfb-run -a --server-args="-screen 0 1280x800x24" \
      npm run dev > /tmp/aipg-ui.log 2>&1 &
  else
    echo "WARNING: xvfb-run not found — electron will fail without a display."
    echo "         Install it with: sudo apt install xvfb"
    ELECTRON_NO_ATTACH_CONSOLE=1 nohup npm run dev > /tmp/aipg-ui.log 2>&1 &
  fi
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
