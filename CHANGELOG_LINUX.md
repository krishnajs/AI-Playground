# Linux Support Changelog

This document tracks technical changes made for Intel AI Playground Linux support on top of the linux-poc branch.

---

## Changes on top of linux-poc Branch

### Platform Tested
- **Hardware**: Intel Panther Lake (Device ID: 0xB08F)
- **Kernel**: Linux 6.17-intel
- **Date**: 2026-05-04

---

## 1. XPU Memory Management Fix for Panther Lake iGPU

**File**: `WebUI/electron/subprocesses/comfyUIBackendService.ts` (lines 800-812)

**Problem**: 
XPU out-of-memory errors when running large models (e.g., Flux) on Panther Lake iGPU with shared memory. The `--lowvram` flag causes piecemeal model loading that fragments the SYCL USM memory pool, leading to OOM on large single allocations (attention tensors).

**Solution**:
```typescript
// On Linux XPU, remove --lowvram and use smaller reserve instead
const effectiveParams =
  process.platform === 'linux' && this.comfyUiVariant === 'xpu'
    ? this.comfyUiParametersString
        .replace(/--lowvram\b/g, '')
        .replace(/--reserve-vram\s+\S+/g, '--reserve-vram 2.0')
        .trim()
    : this.comfyUiParametersString
```

**Result**: 
- Panther Lake iGPU: 62.4 GB VRAM available, 2.0 GB reserved
- Enables large model inference without fragmentation

---

## 2. Level Zero Composite Device Hierarchy

**File**: `WebUI/electron/subprocesses/comfyUIBackendService.ts` (lines 785-788)

**Problem**:
Level Zero cannot allocate large contiguous USM memory blocks with flat device hierarchy on iGPU configurations.

**Solution**:
```typescript
// Use composite device hierarchy for large contiguous USM allocations
envVars.ZE_FLAT_DEVICE_HIERARCHY = 'COMPOSITE'
```

**Verification**:
```bash
$ cat /proc/$(pgrep -f "ComfyUI")/environ | tr '\0' '\n' | grep ZE_FLAT
ZE_FLAT_DEVICE_HIERARCHY=COMPOSITE
```

**Impact**: Fixes XPU memory allocation for large models on Panther Lake iGPU.

---

## 3. Electron Hardware Acceleration Fix for Linux

**File**: `WebUI/electron/main.ts` (lines 170-179)

**Problem**:
Electron crashes on headless Linux (Xvfb/VNC) with "GPU process isn't usable" error when trying to use hardware acceleration.

**Solution**:
```typescript
// Disable Chromium GPU acceleration on Linux
// Note: Does NOT affect AI compute (uses Level Zero/SYCL directly)
if (process.platform === 'linux') {
  app.disableHardwareAcceleration()
  app.commandLine.appendSwitch('disable-gpu')
  app.commandLine.appendSwitch('disable-software-rasterizer', 'false')
  app.commandLine.appendSwitch('no-sandbox')
}
```

**Impact**: Electron UI works on headless Linux servers with software rendering.

---

## 4. Linux Window Behavior - Keep Services Running

**File**: `WebUI/electron/main.ts` (lines 644-662)

**Problem**:
On Linux, users expect services to keep running when closing the window (server-like behavior), unlike Windows desktop behavior.

**Solution**:
```typescript
app.on('window-all-closed', async () => {
  if (process.platform === 'linux') {
    appLogger.info(
      'Window closed — AI services continue running. Open http://localhost:25413 to reconnect.',
      'electron-backend',
    )
    win = null
    return  // Don't quit, keep services running
  }
  if (process.platform !== 'darwin') {
    await shutdownServicesAndQuit()
  }
})
```

**Behavior**:
- Close window → Services keep running
- Reconnect via http://localhost:25413
- Full shutdown: Ctrl+C or SIGTERM

---

## 5. Intel GPU Detection via lspci

**File**: `WebUI/electron/subprocesses/hardwareDiscovery.ts` (lines 74-120)

**Problem**:
`xpu-smi.exe` is Windows-only; Linux needs different GPU detection method.

**Solution**:
```typescript
async function detectIntelGpusViaLspci(): Promise<GpuHardwareDevice[]> {
  const out = await spawnProcessAsync('lspci', ['-nn'], ...)
  // Parse: "00:02.0 VGA compatible controller [0300]: Intel Corporation Device [8086:b08f]"
  const deviceMatch = line.match(/\[8086:([0-9a-fA-F]{4})\]/)
  
  devices.push({
    device: 'INTEL_GPU_LSPCI',
    name: name,
    gpuDeviceId: `0x${deviceMatch[1].toUpperCase()}`,
  })
}
```

**Panther Lake Detection**:
```
[electron-backend]: Detected 8 Intel GPU(s) via lspci
gpuDeviceId: "0xB08F" (Panther Lake)
```

---

## 6. ComfyUI Workflow Parameter Fix

**File**: `WebUI/src/assets/js/tools/comfyUi.ts` (line 8)

**Problem**:
`batchSize` parameter was required but not always provided by workflows.

**Solution**:
```typescript
batchSize: z.number().optional()  // Changed from z.number()
```

**Impact**: More flexible ComfyUI workflow handling, no errors on missing batchSize.

---

## 7. Startup Script with Auto-Kill

**File**: `start-ui.sh` (lines 60-76)

**Problem**:
Running multiple instances causes port conflicts.

**Solution**:
```bash
_kill_previous() {
  pkill -f "${SCRIPT_DIR}/WebUI/node_modules/electron" || true
  pkill -f "${SCRIPT_DIR}/service.*web_api\.py" || true
  pkill -f "${SCRIPT_DIR}/ComfyUI.*main\.py" || true
  pkill -f "${SCRIPT_DIR}/LlamaCPP.*llama-server" || true
  sleep 1
}
_kill_previous  # Called before starting
```

**Impact**: Safe to run `./start-ui.sh` multiple times - auto-cleans previous session.

---

## Verification on Panther Lake

### System Configuration
```
Device: Intel Panther Lake (0xB08F)
Tiles: 8x GPU tiles detected
Kernel: Linux 6.17-intel
VRAM: 62.4 GB total, 55.4 GB free
Reserved: 2.0 GB
```

### ComfyUI Status
```json
{
  "system": {
    "pytorch_version": "2.11.0+xpu",
    "comfyui_version": "0.17.0"
  },
  "devices": [{
    "name": "xpu:0 Intel(R) Graphics [0xb08f]",
    "type": "xpu",
    "vram_total": 62473207808
  }]
}
```

### Environment Variables Active
```
ZE_FLAT_DEVICE_HIERARCHY=COMPOSITE
ONEAPI_DEVICE_SELECTOR=level_zero:1
SYCL_ENABLE_DEFAULT_CONTEXTS=1
```

### Process Verification
```bash
$ ps aux | grep ComfyUI
python main.py --port 49000 --reserve-vram 2.0
# Note: --lowvram flag removed on Linux XPU
```

---

## Known Behavior

### Expected Warnings
```
MESA-INTEL: warning: Vulkan not yet supported on Intel(R) Graphics (PTL)
```
**Status**: Expected and non-blocking. AI workloads use Level Zero/SYCL, not Vulkan. Only affects Electron's UI rendering (already using software rasterizer).

---

## Technical Summary

### Memory Fixes
1. Remove `--lowvram` on Linux XPU to prevent USM fragmentation
2. Use `ZE_FLAT_DEVICE_HIERARCHY=COMPOSITE` for large allocations
3. Reduce `--reserve-vram` from 6.0 to 2.0 GB on Linux

### Platform Detection
1. Use `lspci` for Intel GPU detection on Linux
2. Platform-specific behavior for window close events
3. Disable Electron GPU acceleration on Linux

### Compatibility
- ✅ Panther Lake (0xB08F) - Verified working
- ✅ ComfyUI 0.17.0 with PyTorch 2.11.0+xpu

---

**Last Updated**: 2026-05-04  
**Status**: Production-ready for Panther Lake iGPU
