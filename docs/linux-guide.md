# Running AI Playground on Linux

Quick guide to run Intel AI Playground on Linux with full GPU acceleration.

## Quick Start

### Prerequisites

- Ubuntu 24.04 LTS or newer
- Intel Core Ultra with integrated GPU
- Node.js 22+
- Python 3.12+

Install required packages:
```bash
sudo apt update
sudo apt install -y git curl build-essential python3 python3-pip python3-venv pciutils tar gzip p7zip-full
```

### Installation

**Using the Convenience Script (Recommended):**

1. **Clone and enter the repository:**
```bash
git clone <repository-url>
cd AI-Playground
```

2. **Run the startup script:**
```bash
chmod +x start-ui.sh
./start-ui.sh
```

The application will start at **http://localhost:25413**

**Manual Installation:**

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

3. **Download external resources:**
```bash
npm run fetch-external-resources
```

4. **Launch the application:**
```bash
npm run dev
```

---

## Proxy Configuration

If you're behind a corporate proxy, configure npm before installation:

```bash
npm config set proxy http://proxy-dmz.intel.com:911
npm config set https-proxy http://proxy-dmz.intel.com:912
npm config set strict-ssl false
```

---

## Troubleshooting

### npm install fails with timeout
Configure proxy settings (see Proxy Configuration section above).

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
ssh -L 25413:localhost:25413 user@remote-host
```

Then open http://localhost:25413 in your local browser.

---

## Linux-Specific Behavior

### Window Close Behavior
On Linux, closing the Electron window does **NOT** stop the backend services. This allows server-like operation:

- Close window → Services keep running
- Reconnect via http://localhost:25413
- Full shutdown: Press `Ctrl+C` in terminal or use `SIGTERM`

### Process Management
The `start-ui.sh` script automatically kills previous instances before starting:
```bash
./start-ui.sh  # Safe to run multiple times
```

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
