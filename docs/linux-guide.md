# Running AI Playground on Linux

Quick guide to run Intel AI Playground on Linux with full GPU acceleration.

## Quick Start

### Prerequisites

- Ubuntu 24.04 LTS or newer
- Intel Arc BMG, LNL, or PTL-H iGPU
- Node.js 22 (via nvm — see install steps below)
- Python 3.12+

Install required packages:
```bash
sudo apt update
sudo apt install -y \
  git curl unzip jq pciutils tar gzip p7zip-full \
  build-essential pkg-config meson ninja-build cmake \
  python3 python3-pip python3-venv python3-dev \
  libcairo2-dev libgirepository1.0-dev libglib2.0-dev \
  libjpeg-dev zlib1g-dev libpng-dev libtiff-dev libwebp-dev \
  ffmpeg libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
  libssl-dev libgl1
```

> **Why so many `-dev` packages?** uv builds several Python wheels from source on first run
> (`pycairo`, `llvmlite`, `numpy`, image/video libs). They each need the matching system
> headers (`pkg-config cairo`, `Python.h`, libav*, etc.).
> Install them in one go and the rest of the bring-up is unattended.

Install Node.js 22 via nvm:
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 22
nvm use 22
```

### Installation

1. **Clone and enter the repository:**
```bash
git clone <repository-url>
cd AI-Playground
```

2. **Install Node.js dependencies:**
```bash
cd WebUI
npm install
```

If you are behind a corporate proxy, set **both** of these before running `npm install`:
```bash
export HTTPS_PROXY=http://your-proxy:port
export ELECTRON_GET_USE_PROXY=true   # required — Electron's binary downloader ignores HTTPS_PROXY without this
npm install
```

> **Tip:** Add both lines to `~/.bashrc` or `/etc/environment` so every terminal session picks them up automatically.

3. **Download external resources:**
```bash
npm run fetch-external-resources
```

4. **Launch the application:**
```bash
npm run dev
```

For headless environments (VNC, remote server without a display):
```bash
npm run dev:headless
```

The application will open at **http://localhost:25413**

---

## Building and Installing the .deb Package

To produce a Debian package for distribution or installation on another machine:

### Build prerequisites

The build machine needs `binutils` for the `ar` tool that fpm uses to assemble the `.deb`:

```bash
sudo apt install -y binutils
```

> **If the build fails with `ar failed (exit code 1)`** check two things first:
> 1. `which ar` — if missing, install `binutils` above.
> 2. `df -h` — if the disk is full (ENOSPC), free space before rebuilding.

```bash
cd WebUI
npm run build:linux
```

The `.deb` is written to `build/electron/AI Playground-<version>.deb`.

### Installing the .deb

**Use `dpkg -i`, not `apt install`, for local `.deb` files:**

```bash
cd build/electron
sudo dpkg -i "AI Playground-3.1.0-alpha.deb"
sudo apt-get install -f          # pulls in any missing dependencies
```

> **Why not `sudo apt install ./...deb`?**
> `apt` routes even local file installs through its sandboxed `_apt` helper, which
> runs as the `_apt` user and cannot read files inside your home directory (`/home/…`).
> This produces the error:
> ```
> N: Download is performed unsandboxed as root as file '…' couldn't be accessed by user '_apt'.
>    - pkgAcquire::Run (13: Permission denied)
> ```
> `dpkg -i` installs directly from disk without any sandboxing and is always the
> correct tool for installing local packages.

### Reinstalling / upgrading

```bash
sudo dpkg -i "AI Playground-3.1.0-alpha.deb"   # dpkg handles upgrades too
sudo apt-get install -f
```

### Removing

```bash
sudo apt remove ai-playground
```

---

## Proxy Configuration

If you're behind a corporate proxy, two environment variables are required:

| Variable | Purpose |
|---|---|
| `HTTPS_PROXY` | Routes all npm registry and tool downloads through your proxy |
| `ELECTRON_GET_USE_PROXY=true` | **Required** — Electron's binary downloader (`@electron/get`) uses its own HTTP client and ignores `HTTPS_PROXY` unless this flag is set |

For a persistent setup, add both to `/etc/environment` or `~/.bashrc`:

```bash
export HTTPS_PROXY=http://your-proxy:port
export ELECTRON_GET_USE_PROXY=true
```

For npm registry SSL issues on strict corporate firewalls:

```bash
npm config set strict-ssl false
```

---

## Troubleshooting

### npm install fails with timeout or ETIMEDOUT

The Electron binary downloader (`@electron/get`) does **not** automatically use `HTTPS_PROXY`. You must set `ELECTRON_GET_USE_PROXY=true`:

```bash
export HTTPS_PROXY=http://your-proxy:port
export ELECTRON_GET_USE_PROXY=true
npm install
```

For a permanent fix, add both lines to `~/.bashrc` or `/etc/environment`.

### `apt install ./…deb` fails with "Permission denied" for `_apt`

`apt` sandboxes local file installs using the `_apt` user, which cannot access your home
directory. Use `dpkg -i` instead:

```bash
sudo dpkg -i "AI Playground-3.1.0-alpha.deb"
sudo apt-get install -f
```

### "UV executable not found"
```bash
cd WebUI
npm run fetch-external-resources
```

### Port 25413 connection refused
Check if the dev server is running:
```bash
netstat -tlnp | grep 25413
```

### Check application logs
```bash
tail -f /tmp/app-log.txt
```

### Verify AI Backend is running
```bash
curl http://127.0.0.1:59000/healthy
# Should return: {"health":"OK"}
```

### Verify ComfyUI GPU detection
```bash
# Check ComfyUI is using XPU
curl http://127.0.0.1:49000/system_stats
# Should show: "type": "xpu" and GPU device info
```

### Check GPU memory allocation
```bash
# View ComfyUI memory settings
ps aux | grep ComfyUI
# Should show: --reserve-vram 2.0 (without --lowvram on Linux)
```

---

## Remote Access (SSH)

If running on a remote Linux server, create an SSH tunnel:
```bash
ssh -L 25413:localhost:25413 -L 59000:localhost:59000 user@remote-host
```

Then open **http://localhost:25413** in your local browser.

> ⚠️ **Use `http://`, not `https://`.** The dev server speaks plain HTTP.
> An `https://` URL will produce a blank page or `ERR_SSL_PROTOCOL_ERROR`.

### Remote-console access (KVM / VNC / iDRAC / vSphere)

When you connect over a remote console, your laptop's `localhost` is **not** the
remote machine. You have two options:

1. **Open the browser inside the remote desktop session you see over the KVM**
   and visit `http://localhost:25413`. This is the simplest path.
2. **SSH-tunnel as shown above** and use your laptop's local browser.

The dev server binds to `127.0.0.1` only (see
`WebUI/package.json → debug.env.VITE_DEV_SERVER_HOSTNAME`). Exposing it on
`0.0.0.0` is possible but discouraged — Vite has no authentication.

---

## Recovery: ComfyUI fails with `ModuleNotFoundError` after install

Symptom in the UI:

```
=== Environment Mismatch Warning ===
Environment mismatch detected. The virtual environment at .../ComfyUI/.venv
exists but doesn't match the expected lockfile state.

ModuleNotFoundError: No module named 'yaml'    (or torch, av, etc.)
```

Meaning: `uv sync` aborted partway through (usually a missing system header —
see prerequisites above) leaving a half-built venv. The app detects the
mismatch but still tries to start the backend, hence the second traceback.

**Fix in one shot:**

```bash
cd <repo-root>
# 1. stop everything
kill $(cat /tmp/aipg-electron.pid) 2>/dev/null; pkill -f electron || true
pkill -f "AI-Playground/.*python" || true
# 2. install the apt prereqs from the top of this guide
# 3. wipe the broken venv + markers
rm -rf ComfyUI/.venv comfyui-deps/.venv
find ComfyUI -maxdepth 3 -name '.aipg-comfyui-revision*' -delete
[ -f ComfyUI/pyproject.toml.aipg-upstream ] && \
  mv -f ComfyUI/pyproject.toml.aipg-upstream ComfyUI/pyproject.toml
# 4. clear uv's failed build cache so it actually retries the build
rm -rf ~/.cache/uv/sdists-v9/pypi/pycairo ~/.cache/uv/builds-v0
# 5. relaunch — installer runs from a clean slate
npm run dev
```

To debug a recurring failure, run `uv sync` directly so you see the real
error instead of the truncated UI message:

```bash
cd ComfyUI
../build/resources/uv sync --extra "$(jq -r .variant aipg-variant.json)"
```

---

## Linux-Specific Behavior

### Window Close Behavior
On Linux, closing the Electron window **stops all backend services** (matching Windows behavior). To restart, run `npm run dev` again.

---

## Known Warnings (Safe to Ignore)

### Vulkan Warning
```
MESA-INTEL: warning: Vulkan not yet supported on Intel(R) Graphics (PTL)
```
**Status**: Expected and harmless. AI workloads use Level Zero/SYCL directly, not Vulkan. Only affects Electron UI rendering (uses software rasterizer instead).

### NVIDIA Detection
```
Failed to detect NVIDIA GPUs via nvidia-smi
```
**Status**: Normal on Intel GPU systems. Intel GPUs are detected via `lspci`.

---

## Additional Resources

- **Technical Changes**: See `CHANGELOG_LINUX.md` at repository root for detailed implementation notes
- **Original Proposal**: See `linux-porting-proposal.md` for the full porting plan
- **Memory Fixes**: CHANGELOG documents XPU memory management and Level Zero configuration
