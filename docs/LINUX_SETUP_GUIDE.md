# Intel AI Playground - Linux Setup Guide

**Branch:** `nathsudi/linux-phase1`  
**Status:** POC Complete - Tested and Working  
**Last Updated:** April 21, 2026

This guide provides step-by-step instructions for running Intel AI Playground on Linux.

---

## Table of Contents
1. [What Works on Linux](#what-works-on-linux)
2. [Prerequisites](#prerequisites)
3. [Installation Steps](#installation-steps)
4. [Verification](#verification)
5. [Testing Inference](#testing-inference)
6. [Troubleshooting](#troubleshooting)
7. [Known Limitations](#known-limitations)

---

## What Works on Linux

✅ **Fully Functional:**
- Electron application with Vite dev server
- AI Backend (Flask) - Model management service
- LlamaCPP backend - Text inference (CPU)
- Intel GPU detection via lspci
- Model download and management
- Chat interface with streaming responses
- Python environment management via uv

⚠️ **Limited/Not Available:**
- OpenVINO backend (Phase 3 - needs Linux OVMS package)
- ComfyUI image generation (Phase 4 - needs Linux dependencies)
- GPU acceleration (needs Vulkan build)
- NPU support (future work)

---

## Prerequisites

### System Requirements
- **OS:** Ubuntu 24.04 LTS or newer (tested on Linux 6.17-intel)
- **Architecture:** x86_64
- **Node.js:** 22.12.0 or newer
- **Python:** 3.12+
- **RAM:** 8GB minimum, 16GB recommended
- **Disk:** 10GB free space (more for models)

### Required System Packages

```bash
sudo apt update
sudo apt install -y \
  git \
  curl \
  build-essential \
  python3 \
  python3-pip \
  python3-venv \
  pciutils \
  tar \
  gzip \
  p7zip-full
```

### Corporate Proxy Configuration (Intel Network)

If you're behind a corporate proxy, configure npm and git:

```bash
# Configure npm
npm config set proxy http://proxy-dmz.intel.com:911
npm config set https-proxy http://proxy-dmz.intel.com:912
npm config set strict-ssl false

# Configure git (if needed)
git config --global http.proxy http://proxy-dmz.intel.com:911
git config --global https.proxy http://proxy-dmz.intel.com:912

# Set environment variables (add to ~/.bashrc)
export HTTP_PROXY=http://proxy-dmz.intel.com:911
export HTTPS_PROXY=http://proxy-dmz.intel.com:912
export NO_PROXY=localhost,127.0.0.1
```

See `proxy-configuration.md` for detailed proxy troubleshooting.

---

## Installation Steps

### 1. Clone Repository and Checkout Branch

```bash
git clone <repository-url>
cd AI-Playground
git checkout nathsudi/linux-phase1
```

### 2. Install Node.js 22 (if needed)

Check your Node version:
```bash
node --version  # Should be v22.x.x or newer
```

If you need to install Node 22:
```bash
# Install nvm (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
source ~/.bashrc

# Install and use Node 22
nvm install 22
nvm use 22
node --version
```

### 3. Install Dependencies

```bash
cd WebUI
npm install
```

This will take 5-10 minutes depending on network speed. If you encounter timeout errors, verify proxy configuration.

### 4. Download External Resources

The application needs `uv` (Python package manager) and `7zip` binaries.

**Option A: Automatic (if network/proxy is configured):**
```bash
npm run fetch-external-resources
```

**Option B: Manual (if automatic fails):**
```bash
# Create directories
mkdir -p build/resources build/tmp

# Download uv (Python package manager)
curl -L -o build/tmp/uv.tar.gz \
  https://github.com/astral-sh/uv/releases/download/0.11.6/uv-x86_64-unknown-linux-gnu.tar.gz
tar -xzf build/tmp/uv.tar.gz -C build/tmp
mv build/tmp/uv-x86_64-unknown-linux-gnu/uv build/resources/uv
chmod +x build/resources/uv

# Download 7zip
curl -L -o build/tmp/7z.tar.xz \
  https://github.com/ip7z/7zip/releases/download/25.01/7z2501-linux-x64.tar.xz
tar -xf build/tmp/7z.tar.xz -C build/tmp 7zz
mv build/tmp/7zz build/resources/7zr
chmod +x build/resources/7zr

# Copy to parent directory (app looks in both locations)
mkdir -p ../../build/resources
cp build/resources/uv ../../build/resources/
cp build/resources/7zr ../../build/resources/
```

Verify binaries are executable:
```bash
./build/resources/uv --version  # Should show: uv 0.11.6
./build/resources/7zr --help     # Should show 7-Zip usage
```

### 5. Launch Application

**Option A — Convenience script (recommended):**

```bash
cd /path/to/AI-Playground
chmod +x start-ui.sh
./start-ui.sh
```

**Option B — Manual:**

```bash
cd WebUI
npm run dev
```

Expected output:
```
  Intel AI Playground - Linux
  ─────────────────────────────────────────────────────
  UI:           http://localhost:25413
  AI Backend:   http://localhost:59000

  Closing the window does NOT stop services.
  Press Ctrl+C here to fully quit.
  ─────────────────────────────────────────────────────

VITE v8.0.8  ready in ~500ms
➜ Local: http://127.0.0.1:25413/
```

Open **http://localhost:25413** in your browser.

> **Key behavior on Linux:**  
> Closing the Electron window (or the X11 session) does **not** stop the AI services.  
> Services (Flask AI backend, LlamaCPP, etc.) keep running until you press **Ctrl+C** in  
> the terminal. You can close and reopen the browser tab at any time without losing sessions.

**For Remote Access via SSH:**

If you're running on a remote Linux machine, create an SSH tunnel:
```bash
# On your local machine:
ssh -L 25413:localhost:25413 user@remote-host

# Then open in browser:
http://localhost:25413
```

---

## Verification

### 1. Check Application is Running

```bash
# Check Electron processes
ps aux | grep electron
# Should show multiple electron processes

# Check web server
curl http://127.0.0.1:25413
# Should return HTML page
```

### 2. Check AI Backend Service

```bash
# Check if AI Backend is healthy
curl http://127.0.0.1:59000/healthy
# Should return: {"health":"OK"}
```

### 3. Check Application Logs

```bash
# Monitor logs in real-time
tail -f /tmp/app-log.txt

# Or check for errors
grep -i error /tmp/app-log.txt | grep -v "MESA-INTEL"
```

### 4. Verify in Browser

1. Open `http://localhost:25413` in your browser
2. Navigate to **Settings → Services**
3. Verify **AI Backend** shows status: "Running"
4. Check **Hardware** tab to see detected Intel GPUs

---

## Testing Inference

### Install LlamaCPP Backend

1. **In the Browser UI:**
   - Go to **Settings → Services**
   - Find **"LlamaCPP Backend"**
   - Click **"Install"** button

2. **What Happens:**
   - Downloads `llama-b8708-bin-ubuntu-x64.tar.gz` (~2-3 MB)
   - Extracts to `/home/user/nathsudi/AI-Playground/LlamaCPP/`
   - Creates llama-server binary
   - Installation takes 1-2 minutes

3. **Expected Result:**
   - Status changes to "Installed" or "Running"
   - No errors in logs
   - Service ready for inference

### Download a Model

1. **Navigate to Models Section:**
   - Click **"Models"** in the sidebar
   - Click **"Browse Models"** or search

2. **Recommended Models for Testing:**
   - **TinyLlama-1.1B-Chat** (~600MB) - Fast, good for testing
   - **Llama-3.2-1B-Instruct** (~800MB) - Better quality
   - **Llama-3.2-3B-Instruct** (~2GB) - Production quality

3. **Select and Download:**
   - Choose **Q4_K_M** or **Q4_K_S** quantization (smaller, faster)
   - Click **"Download"**
   - Monitor progress in the UI

### Test Chat Interface

1. **Create Chat Session:**
   - Go to **Chat** section
   - Click **"New Chat"**

2. **Configure Backend:**
   - Select **Backend:** LlamaCPP
   - Select **Model:** Your downloaded model
   - Adjust temperature/parameters if desired

3. **Send Test Message:**
   ```
   Hello! Can you introduce yourself and tell me what you can do?
   ```

4. **Verify:**
   - ✅ Response starts streaming within 1-2 seconds
   - ✅ Text appears word-by-word (streaming)
   - ✅ Response is coherent and completes
   - ✅ No errors in console (F12)

---

## Troubleshooting

### Issue: Port 25413 Connection Refused

**Symptoms:** Browser shows "connection refused" or "cannot connect"

**Solutions:**
1. Check if dev server is running:
   ```bash
   netstat -tlnp | grep 25413
   # Should show: tcp ... 127.0.0.1:25413 ... LISTEN
   ```

2. Restart the application (Ctrl+C first, then):
   ```bash
   ./start-ui.sh
   ```

3. Check for port conflicts:
   ```bash
   lsof -i :25413
   # Kill conflicting process if needed
   ```

### Issue: npm install fails with ETIMEDOUT

**Symptoms:** `npm ERR! network request to ... failed`

**Solution:** Configure proxy (see Prerequisites section)

### Issue: "UV executable not found"

**Symptoms:** Services fail to install, logs show "UV not found"

**Solution:** Verify uv binary exists and is executable:
```bash
ls -la WebUI/build/resources/uv
ls -la build/resources/uv
chmod +x WebUI/build/resources/uv
chmod +x build/resources/uv
```

Re-download if missing (see Installation Step 4).

### Issue: AI Backend Fails to Start

**Symptoms:** AI Backend shows "Failed" status

**Solution:**
1. Check Python is available:
   ```bash
   python3 --version  # Should show 3.12+
   ```

2. Check logs:
   ```bash
   tail -100 /tmp/app-log.txt | grep "ai-backend"
   ```

3. Verify PIP_CONFIG_FILE fix is applied:
   ```bash
   grep "PIP_CONFIG_FILE" WebUI/electron/subprocesses/service.ts
   # Should show: process.platform === 'win32' ? 'nul' : '/dev/null'
   ```

### Issue: LlamaCPP Installation Hangs

**Symptoms:** Installation progress stuck at "Downloading..."

**Solution:**
1. Check network connectivity:
   ```bash
   curl -I https://github.com
   ```

2. Manual download and extract:
   ```bash
   cd LlamaCPP
   curl -L -o llama.tar.gz https://github.com/ggerganov/llama.cpp/releases/download/b8708/llama-b8708-bin-ubuntu-x64.tar.gz
   tar -xzf llama.tar.gz
   ```

### Issue: Model Download Fails

**Symptoms:** Download starts but fails with error

**Solution:**
1. Check disk space:
   ```bash
   df -h .
   # Need at least 5GB free
   ```

2. Check AI Backend is running:
   ```bash
   curl http://127.0.0.1:59000/healthy
   ```

3. Retry download from UI

### Issue: Blank Screen in Browser

**Symptoms:** Page loads but shows blank white screen

**Solution:**
1. Hard refresh: `Ctrl+Shift+R` or `Ctrl+F5`
2. Clear browser cache
3. Check browser console (F12) for JavaScript errors
4. Verify Vite build completed:
   ```bash
   tail -20 /tmp/app-log.txt | grep "VITE"
   # Should show: VITE v8.0.8  ready
   ```

### Issue: Electron Process Crashes on Startup

**Symptoms:** `npm run dev` starts but immediately exits

**Solution:**
1. Check X11 display is available:
   ```bash
   echo $DISPLAY  # Should show :0 or similar
   ```

2. Run with no-sandbox (if needed):
   ```bash
   # Edit WebUI/package.json, add --no-sandbox flag
   electron . --no-sandbox
   ```

---

## Known Limitations

### Expected Errors (Safe to Ignore)

#### 1. ComfyUI Installation Failed
```
error: The current Python platform is not compatible with the lockfile's 
supported environments: `sys_platform == 'win32'`, `sys_platform == 'darwin'`
```

**Status:** ❌ Out of scope for Phase 1  
**Reason:** ComfyUI's `uv.lock` only includes Windows/macOS dependencies  
**Impact:** Image generation not available  
**Workaround:** None for POC  
**Future:** Phase 4 work - add Linux dependencies to `comfyui-deps/pyproject.toml`

---

#### 2. OpenVINO Installation Failed
```
Command failed: tar -xf '/home/user/.../ovms.tar.gz'
gzip: stdin: not in gzip format
tar: Child returned status 1
```

**Status:** ❌ Out of scope for Phase 1  
**Reason:** Linux OVMS package not available at download URL  
**Impact:** Cannot use OpenVINO for inference  
**Workaround:** Use LlamaCPP backend instead  
**Future:** Phase 3 work - find correct Linux OVMS binary or use Docker

---

#### 3. Vulkan Warnings
```
MESA-INTEL: warning: Vulkan not yet supported on Intel(R) Graphics (PTL)
```

**Status:** ⚠️ Expected warning  
**Reason:** Vulkan support for Panther Lake GPUs still in development  
**Impact:** None - doesn't affect functionality  
**Workaround:** Not needed  
**Future:** Will resolve as Mesa drivers mature

---

#### 4. NVIDIA GPU Detection Fails
```
Failed to detect NVIDIA GPUs via nvidia-smi
Process error: spawn nvidia-smi ENOENT
```

**Status:** ℹ️ Normal on systems without NVIDIA GPU  
**Reason:** nvidia-smi not installed (Intel GPU system)  
**Impact:** None  
**Workaround:** Not needed (Intel GPUs detected via lspci)

---

### Current Limitations (By Design)

#### Performance
- **LlamaCPP using CPU build** - No GPU acceleration yet
  - Currently using `ubuntu-x64` (CPU-only)
  - Future: Switch to `linux-vulkan-x64` for GPU acceleration
  - Expected to be slower than Windows with GPU

#### Features Not Available
- **OpenVINO inference** - GPU/NPU acceleration not available
- **ComfyUI image generation** - Linux dependencies not configured
- **NPU utilization** - Requires driver and OpenVINO integration
- **Some model formats** - OpenVINO IR models not supported

#### User Experience
- **No Linux installer** - Running from source only
- **Manual dependency install** - No automated setup script
- **No driver wizard** - Assumes compute drivers pre-installed
- **No packaging** - No AppImage or .deb packages yet

---

## Next Steps

### Immediate (After Successful Testing)
1. Test inference with different model sizes
2. Benchmark performance vs Windows
3. Document any additional issues encountered

### Short Term (Phase 2)
1. Switch to Vulkan-enabled LlamaCPP build
2. Add Vulkan driver detection
3. Performance optimization

### Medium Term (Phase 3-4)
1. Implement OpenVINO Linux backend
2. Add ComfyUI XPU support for Linux
3. Integrate NPU support

### Long Term (Phase 5)
1. Create AppImage and .deb packages
2. Add to CI/CD pipeline
3. Production documentation
4. Driver installation wizard

---

## Additional Resources

- **Technical Implementation:** See `LINUX_IMPLEMENTATION.md`
- **POC Results:** See `LINUX_POC_RESULTS.md`
- **Proxy Troubleshooting:** See `proxy-configuration.md`
- **Main Documentation:** See repository README

---

## Support

For issues or questions:
1. Check this troubleshooting section
2. Review logs: `tail -f /tmp/app-log.txt`
3. Check known limitations above
4. Open an issue in the repository

---

**Document Version:** 1.0  
**For Branch:** nathsudi/linux-phase1  
**Tested On:** Linux 6.17-intel, Ubuntu 24.04 LTS
