#!/usr/bin/env bash
# AI Playground - WSL2 Environment Setup
#
# Run this ONCE inside WSL2 (Ubuntu 22.04 or 24.04).
#
# HOW TO GET HERE:
#   1. Reboot PC after "wsl --install" completes
#   2. After reboot: wsl --install -d Ubuntu-24.04
#   3. Open a new terminal and type: wsl
#   4. Inside WSL:
#        cd "/mnt/c/Users/gunjangu/New folder/AI-Playground"
#        bash scripts/wsl-setup.sh

set -e
echo ""
echo "======================================================="
echo "  AI Playground -- WSL2 Linux Environment Setup"
echo "======================================================="
echo ""

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# -----------------------------------------------------------------------
# Corporate proxy / IPv6 fix
# Many corporate networks block IPv6 and require an HTTP proxy.
# -----------------------------------------------------------------------
echo "> Checking network configuration..."

# Disable IPv6 -- most corporate networks route only IPv4 through the proxy.
# Without this, apt and curl try IPv6 first and time out for minutes.
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1    >/dev/null 2>&1 || true
sudo sysctl -w net.ipv6.conf.default.disable_ipv6=1 >/dev/null 2>&1 || true

# Try to inherit Windows proxy settings if no proxy is already set
if [ -z "${http_proxy:-}" ] && [ -z "${HTTP_PROXY:-}" ]; then
  WIN_PROXY=$(powershell.exe -NoProfile -Command \
    "(Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue).ProxyServer" \
    2>/dev/null | tr -d '\r\n' || true)
  if [ -n "$WIN_PROXY" ] && [ "$WIN_PROXY" != "0" ]; then
    PROXY_ADDR=$(echo "$WIN_PROXY" | grep -oP '(?<=http=)[^;]+' 2>/dev/null || echo "$WIN_PROXY")
    if [[ "$PROXY_ADDR" != http* ]]; then
      PROXY_ADDR="http://$PROXY_ADDR"
    fi
    export http_proxy="$PROXY_ADDR"
    export https_proxy="$PROXY_ADDR"
    export HTTP_PROXY="$PROXY_ADDR"
    export HTTPS_PROXY="$PROXY_ADDR"
    echo "  Using Windows proxy: $PROXY_ADDR"
  fi
fi

# Quick connectivity test
if curl -s --max-time 5 --connect-timeout 3 -4 https://example.com -o /dev/null 2>&1; then
  echo "  [OK] Internet reachable"
else
  echo "  [WARN] Cannot reach the internet."
  echo "         If on a corporate network, make sure VPN is connected, or set:"
  echo "           export http_proxy=http://your-proxy:port"
  echo "         and re-run this script."
  echo "         Continuing anyway -- some steps may fail."
fi

# -----------------------------------------------------------------------
# System packages
# Use -o Acquire::ForceIPv4=true to skip broken IPv6 apt mirrors
# -----------------------------------------------------------------------
echo ""
echo "> Installing system packages..."
sudo apt-get -o Acquire::ForceIPv4=true update -qq 2>&1 | grep -v "^W:" || true
sudo apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends \
  build-essential \
  cmake \
  curl \
  git \
  libdbus-1-3 \
  libgtk-3-0t64 \
  libnss3 \
  libasound2t64 \
  pciutils \
  python3-dev \
  libvulkan1 \
  mesa-vulkan-drivers \
  vulkan-tools \
  libssl-dev \
  pkg-config \
  libglib2.0-dev \
  libx11-xcb1 \
  libxcb-dri3-0 \
  2>/dev/null || true
echo "  [OK] System packages installed"

# -----------------------------------------------------------------------
# Node.js 22
# Strategy 1: NodeSource apt repo (works when GitHub is blocked)
# Strategy 2: nvm via curl
# Strategy 3: snap
# -----------------------------------------------------------------------
export NVM_DIR="$HOME/.nvm"
CURRENT_MAJOR=0
if command -v node &>/dev/null; then
  CURRENT_MAJOR=$(node -e "process.stdout.write(process.versions.node.split('.')[0])")
fi

if [ "$CURRENT_MAJOR" -lt 22 ]; then
  echo ""
  echo "> Installing Node.js 22..."

  NODE_INSTALLED=false

  # Strategy 1: NodeSource apt repository
  if curl -s --max-time 15 --connect-timeout 10 -4 \
       https://deb.nodesource.com/setup_22.x -o /tmp/nodesource-setup.sh 2>/dev/null; then
    echo "  Using NodeSource apt repository..."
    sudo bash /tmp/nodesource-setup.sh >/dev/null 2>&1 || true
    if sudo apt-get -o Acquire::ForceIPv4=true install -y nodejs 2>/dev/null; then
      NODE_INSTALLED=true
    fi
  fi

  # Strategy 2: nvm via curl (slower, may be blocked on restricted networks)
  if [ "$NODE_INSTALLED" = false ]; then
    echo "  Trying nvm installer..."
    if [ ! -d "$NVM_DIR" ]; then
      curl --connect-timeout 30 --max-time 120 -4 \
        -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh \
        | bash 2>/dev/null || true
    fi
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh" 2>/dev/null || true
    if command -v nvm &>/dev/null; then
      nvm install 22 && nvm use 22 && nvm alias default 22 && NODE_INSTALLED=true
    fi
  fi

  # Strategy 3: snap
  if [ "$NODE_INSTALLED" = false ]; then
    echo "  Trying snap install..."
    sudo snap install node --channel=22/stable --classic 2>/dev/null && NODE_INSTALLED=true || true
  fi

  if command -v node &>/dev/null; then
    echo "  [OK] Node.js $(node --version) installed"
  else
    echo "  [ERROR] Node.js installation failed."
    echo "    Manual option: download node-v22 tarball from https://nodejs.org/dist/v22.0.0/"
    exit 1
  fi
else
  source "$NVM_DIR/nvm.sh" 2>/dev/null || true
  echo "  [OK] Node.js $(node --version) already installed"
fi

# Ensure NVM loads in future shells
if [ -d "$NVM_DIR" ] && ! grep -q 'nvm.sh' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'PROFILE'

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
PROFILE
fi

# -----------------------------------------------------------------------
# Vulkan check
# -----------------------------------------------------------------------
echo ""
echo "> Checking Vulkan (GPU acceleration for LlamaCPP)..."
if vulkaninfo --summary 2>/dev/null | grep -q "GPU"; then
  echo "  [OK] Vulkan GPU detected -- LlamaCPP will use linux-vulkan-x64 (GPU build)"
else
  echo "  [INFO] No Vulkan GPU -- LlamaCPP will use ubuntu-x64 (CPU-only build)"
  echo "         This is normal for WSL2 without GPU passthrough."
fi

# -----------------------------------------------------------------------
# uv (Python package manager)
# -----------------------------------------------------------------------
echo ""
echo "> Installing uv (Python package manager)..."
if ! command -v uv &>/dev/null; then
  curl --connect-timeout 30 --max-time 120 -4 -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null || {
    echo "  [WARN] uv installer failed; trying cargo..."
    command -v cargo &>/dev/null && cargo install uv 2>/dev/null || true
  }
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

if command -v uv &>/dev/null; then
  echo "  [OK] uv $(uv --version)"
else
  echo "  [ERROR] uv installation failed. Check network/proxy settings."
  exit 1
fi

# -----------------------------------------------------------------------
# Regenerate uv.lock files to include Linux platform markers
# -----------------------------------------------------------------------
echo ""
echo "> Regenerating uv.lock files with Linux platform support..."

echo "  comfyui-deps/uv.lock..."
cd "$REPO_ROOT/comfyui-deps"
uv lock 2>&1 | grep -E "^(Resolved|Updated|error|warning)" || true
echo "  [OK] comfyui-deps/uv.lock updated"

echo "  service/uv.lock..."
cd "$REPO_ROOT/service"
uv lock 2>&1 | grep -E "^(Resolved|Updated|error|warning)" || true
echo "  [OK] service/uv.lock updated"

# -----------------------------------------------------------------------
# npm install (Linux Electron binaries)
# The Windows node_modules won't work in WSL -- install separately.
# -----------------------------------------------------------------------
echo ""
echo "> Installing npm dependencies for Linux..."
echo "  (Installs Linux Electron binaries -- separate from Windows node_modules)"
cd "$REPO_ROOT/WebUI"
npm install --legacy-peer-deps 2>&1 | tail -5
echo "  [OK] npm dependencies installed"

# -----------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------
echo ""
echo "======================================================="
echo "  Setup complete! To start AI Playground:"
echo ""
echo "  From WSL terminal:"
echo "    cd \"$REPO_ROOT\""
echo "    bash start-ui.sh"
echo ""
echo "  From Windows PowerShell:"
echo "    .\\wsl-start.ps1"
echo ""
echo "  Then open: http://localhost:25413"
echo "  Press Ctrl+C in the WSL terminal to stop all services."
echo "======================================================="
echo ""
