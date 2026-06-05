# Intel AI Playground — Linux Guide

## Overview

Intel AI Playground runs locally on Ubuntu Linux with full Intel GPU acceleration. It supports
ALL Intel GPU hardware: Meteor Lake (MTL), Arrow Lake (ARL), Panther Lake (PTL), Lunar Lake (LNL),
Battlemage (BMG), Wildcat Lake (WCL), and Alchemist (ACM).

---

## Installation (.deb Package)

The `.deb` package handles all dependencies automatically.

### System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| GPU | Any Intel GPU (MTL/ARL/PTL/LNL/BMG/WCL/ACM) | Intel Arc or Core Ultra iGPU |
| Disk space | 15 GB free | 50 GB free (for models) |
| RAM | 16 GB | 32 GB+ |
| Network | Required for first run (downloads backends) | 100 Mbit+ |

### Install

```bash
sudo dpkg -i "AI Playground-3.1.0-alpha.deb"
sudo apt-get install -f    # installs all dependencies automatically
```

The `.deb` package:
- Installs the Electron app to `/opt/AI Playground/`
- Installs all required system libraries and build tools via `apt` dependencies
- Conditionally installs Intel GPU runtime (Level Zero, OpenCL ICD) if an Intel GPU is detected
- Sets up desktop integration (application menu icon)

> **Why `dpkg -i` instead of `apt install ./…`?**
> `apt` routes local installs through the `_apt` user sandbox, which cannot read files in
> `/home/`. Use `dpkg -i` to install directly from disk without sandboxing issues.

### First Launch

```bash
/opt/AI\ Playground/ai-playground
```

On first launch, the app:
1. Creates `~/.local/share/ai-playground/` (user data directory)
2. Copies backend scripts from `/opt/AI Playground/resources/`
3. Installs Python environments (venvs) for each backend (~7-12 GB)
4. Downloads required binaries (llama-server, OVMS)

**Expected first-run time:** 5-15 minutes.

### Upgrade

```bash
sudo dpkg -i "AI Playground-<new-version>.deb"
sudo apt-get install -f
```

Upgrades preserve user data (models, settings) in `~/.local/share/ai-playground/`.

### Remove

```bash
sudo apt remove ai-playground
```

User data in `~/.local/share/ai-playground/` is preserved. To fully remove:
```bash
rm -rf ~/.local/share/ai-playground ~/.config/ai-playground
```

---

## Development Setup

For contributors working on the source code:

### Prerequisites

- Node.js 22+ (via [nvm](https://github.com/nvm-sh/nvm))
- System packages (installed automatically by .deb, but needed for dev):
  ```bash
  sudo apt install -y \
    git curl unzip pciutils \
    build-essential pkg-config meson ninja-build cmake \
    python3 python3-dev \
    libcairo2-dev libgirepository1.0-dev libglib2.0-dev \
    libjpeg-dev zlib1g-dev libpng-dev libssl-dev libgl1 \
    ffmpeg libavformat-dev libavcodec-dev libavutil-dev libswscale-dev \
    xvfb libvulkan1 mesa-vulkan-drivers
  ```

### Clone & Run

```bash
git clone <repository-url>
cd AI-Playground/WebUI
npm install
npm run fetch-external-resources
npm run dev
```

For headless environments (SSH, no display):
```bash
npm run dev:headless
```

The application opens at **http://localhost:25413**

### Build the .deb

```bash
sudo apt install -y binutils    # needed for 'ar' tool
cd WebUI
npm run build:linux
```

Output: `build/electron/AI Playground-<version>.deb`

---

## Proxy Configuration

### For .deb Runtime

Set proxy environment variables before launching the app:

```bash
export HTTPS_PROXY=http://your-proxy:port
export HTTP_PROXY=http://your-proxy:port
/opt/AI\ Playground/ai-playground
```

For persistent configuration, add to `/etc/environment` or `~/.bashrc`.

The app automatically passes proxy settings to:
- Python package downloads (uv/pip)
- HuggingFace model downloads
- Backend-version checks

### For Development (npm install)

```bash
export HTTPS_PROXY=http://your-proxy:port
export ELECTRON_GET_USE_PROXY=true    # required for Electron binary download
npm install
```

---

## Disk Space Management

### Understanding Storage Usage

| Location | Contents | Size |
|----------|----------|------|
| `/opt/AI Playground/` | App binary + resources (read-only) | ~500 MB |
| `~/.local/share/ai-playground/` | Python venvs, backends, models, cache | 7-60+ GB |
| `~/.config/ai-playground/` | Logs, settings | < 50 MB |
| `/dev/shm/aipg-tmp/` | Temporary build files (cleaned after install) | 0-5 GB during install |

### Monitoring Usage

```bash
du -sh ~/.local/share/ai-playground/
du -sh ~/.local/share/ai-playground/.uv-cache/
du -sh ~/.local/share/ai-playground/*/. venv/ 2>/dev/null
```

### Reclaiming Space

```bash
# Clear UV package cache (safe — packages are already installed in venvs)
rm -rf ~/.local/share/ai-playground/.uv-cache

# Remove all backend venvs (will be reinstalled on next app launch)
rm -rf ~/.local/share/ai-playground/service/.venv
rm -rf ~/.local/share/ai-playground/OpenVINO/.venv
rm -rf ~/.local/share/ai-playground/ComfyUI/.venv

# Remove downloaded models
rm -rf ~/.local/share/ai-playground/models/
```

### Using a Different Partition

If your root filesystem is small, point data to a larger partition:

```bash
export XDG_DATA_HOME=/mnt/large-disk/.local/share
/opt/AI\ Playground/ai-playground
```

Or create a symlink:
```bash
mkdir -p /mnt/large-disk/ai-playground
ln -s /mnt/large-disk/ai-playground ~/.local/share/ai-playground
```

---

## Headless / Remote Access

### SSH Tunnel (Recommended)

```bash
ssh -L 25413:localhost:25413 user@remote-host
```

Then open **http://localhost:25413** in your local browser.

> Use `http://`, not `https://`. The server speaks plain HTTP.

### Headless Mode (No Display)

For servers without X11/Wayland:

```bash
xvfb-run /opt/AI\ Playground/ai-playground
```

Or for development:
```bash
npm run dev:headless
```

### Remote Console (KVM / VNC / iDRAC)

Open the browser **inside** the remote desktop session and visit `http://localhost:25413`.

---

## Troubleshooting

### Backend installation fails with ENOSPC (no space left on device)

**Cause:** Root filesystem is full. Backend installation (Python packages) needs ~10-15 GB free.

**Fix:**
```bash
# Check available space
df -h /

# Option 1: Free disk space
sudo apt autoremove && sudo apt clean
sudo du -sh /var/cache/apt /var/log /tmp | sort -rh

# Option 2: Use a larger partition for app data
export XDG_DATA_HOME=/mnt/large-disk/.local/share
/opt/AI\ Playground/ai-playground

# Option 3: Clear previous failed installation
rm -rf ~/.local/share/ai-playground/.uv-cache
rm -rf ~/.local/share/ai-playground/*/.venv
```

> The app uses `/dev/shm/` (RAM-backed) for temporary build files during installation,
> so the root filesystem only needs space for the final installed packages.

### White screen after launch

**Cause:** Intel GPU runtime not installed or GPU driver issue.

**Fix:**
```bash
# Check if Level Zero is installed
dpkg -s intel-level-zero-gpu 2>/dev/null || echo "Not installed"

# Reinstall GPU runtime
sudo apt install intel-level-zero-gpu intel-opencl-icd level-zero
```

### "UV executable not found" (dev mode)

```bash
cd WebUI
npm run fetch-external-resources
```

### Port 25413 already in use

```bash
# Find what's using the port
sudo lsof -i :25413
# Kill it
sudo kill $(sudo lsof -t -i :25413)
```

### ComfyUI fails with ModuleNotFoundError

```bash
# Stop the app
pkill -f "ai-playground\|AI Playground" || true
pkill -f "python" || true

# Wipe broken venv
rm -rf ~/.local/share/ai-playground/ComfyUI/.venv

# Relaunch — it will reinstall
/opt/AI\ Playground/ai-playground
```

### Check application logs

```bash
# View today's log
cat ~/.config/ai-playground/aip-$(date +%Y-%m-%d).log

# Follow logs in real-time
tail -f ~/.config/ai-playground/aip-*.log
```

### Verify backends are running

```bash
curl http://127.0.0.1:59000/healthy           # AI Backend
curl http://127.0.0.1:49000/system_stats      # ComfyUI
```

---

## Supported Hardware

| Architecture | Type | Device IDs | Status |
|-------------|------|-----------|--------|
| **BMG** (Battlemage) | Discrete GPU | 0xe202, 0xe20b, 0xe20c, 0xe20d, 0xe212 | Fully supported |
| **ACM** (Alchemist) | Discrete GPU | 0x4f80-0x4f87, 0x5690-0x5697, 0x56a0-0x56c2 | Fully supported |
| **PTL** (Panther Lake) | Integrated GPU | 0xb08f, 0xb090, 0xb0a0 | Fully supported |
| **ARL** (Arrow Lake) | Integrated GPU | 0x7d51, 0x7dd1 | Fully supported |
| **LNL** (Lunar Lake) | Integrated GPU | 0x6420, 0x64a0, 0x64b0 | Fully supported |
| **MTL** (Meteor Lake) | Integrated GPU | 0x7d40, 0x7d55, 0x7dd5, 0x7d45 | Fully supported |
| **WCL** (Wildcat Lake) | Integrated GPU | 0xfd80, 0xfd81 | Fully supported |

### iGPU vs dGPU Behavior Differences

| Feature | iGPU (MTL/ARL/PTL/LNL/WCL) | dGPU (BMG/ACM) |
|---------|----------------------------|----------------|
| Memory | Shared system RAM (up to 57 GB) | Dedicated VRAM (8-16 GB) |
| ComfyUI flags | No `--lowvram`, `--reserve-vram 2.0` | `--lowvram`, `--reserve-vram 6.0` |
| Level Zero config | `ZE_FLAT_DEVICE_HIERARCHY=COMPOSITE` | Standard |
| Max model size | Limited by system RAM | Limited by VRAM |

---

## Known Warnings (Safe to Ignore)

### Vulkan Warning
```
MESA-INTEL: warning: Vulkan not yet supported on Intel(R) Graphics (PTL)
```
Expected and harmless. AI workloads use Level Zero/SYCL directly. UI uses software rendering.

### NVIDIA Detection
```
Failed to detect NVIDIA GPUs via nvidia-smi
```
Normal on Intel GPU systems. Intel GPUs are detected via `lspci`.

---

## Additional Resources

- **Technical Changes**: See `CHANGELOG_LINUX.md` for detailed implementation notes
- **Architecture**: See `docs/arc42/arc42_doc.md` for system architecture
- **ComfyUI UV Migration**: See `docs/comfyui-uv-migration.md`
