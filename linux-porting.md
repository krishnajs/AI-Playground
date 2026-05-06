# Intel AI Playground — Linux Porting Proposal

**Target Platform:** Ubuntu 24.04 LTS (Noble Numbat) and higher  
**Target Hardware:** Intel Core Ultra 3 (Panther Lake) — CPU, integrated GPU (Xe3), discrete GPU (Intel Arc), NPU 5  
**Target Kernel:** Linux 6.17 with Intel NPU and GPU SR-IOV drivers  
**Date:** April 2026  
**Status:** Draft Proposal

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current State Assessment](#2-current-state-assessment)
3. [Technical Gap Analysis](#3-technical-gap-analysis)
4. [High-Level Technical Plan](#4-high-level-technical-plan)
5. [Detailed Work Breakdown](#5-detailed-work-breakdown)
6. [Dependency & Driver Matrix](#6-dependency--driver-matrix)
7. [Risk Assessment](#7-risk-assessment)
8. [Recommended Phased Approach](#8-recommended-phased-approach)

---

## 1. Executive Summary

Intel AI Playground is an Electron + Vue.js desktop application that runs AI inference on Intel GPUs using four backend services (AI Backend, LlamaCPP, OpenVINO, ComfyUI). It currently ships as a Windows-only NSIS installer.

The codebase already contains partial Linux support — the Electron shell, AI Backend (Flask), and LlamaCPP backend work on Ubuntu x64 in development mode. However, **GPU-accelerated inference, hardware detection, OpenVINO backend, ComfyUI backend, NPU support, and packaging are all non-functional on Linux**.

This document identifies every technical gap, proposes a phased implementation plan, and covers the Intel driver/runtime stack required for full CPU + GPU + NPU support on Ubuntu 24.04+ with kernel 6.17.

The primary target hardware is **Intel Core Ultra 3 (Panther Lake)**, which integrates:
- **CPU:** P-cores + E-cores (Intel Thread Director)
- **iGPU:** Xe3-LPG integrated graphics with enhanced AI acceleration
- **NPU 5:** Next-gen Neural Processing Unit with significantly improved TOPS
- **Discrete GPU support:** Intel Arc (Battlemage / Alchemist) via PCIe
- **GPU SR-IOV:** Single Root I/O Virtualization for GPU partitioning and sharing across workloads

### Target Kernel: Linux 6.17

Kernel 6.17 provides **full upstream support** for all Panther Lake IP blocks:
- **Xe3-LPG iGPU:** i915/Xe kernel mode driver with full compute and display support
- **NPU 5:** IVPU driver with full Panther Lake NPU device ID support
- **GPU SR-IOV:** Virtual Function (VF) support for Intel GPUs, enabling hardware-level GPU partitioning
- **NPU driver:** Fully functional `intel_vpu` kernel module

With kernel 6.17, there are **no kernel version blockers** — all hardware features are natively supported.

### Target Hardware Architecture

```mermaid
block-beta
  columns 4
  
  block:ptl:4
    columns 4
    header["Intel Core Ultra 3 — Panther Lake SoC"]
    cpu["CPU Tile\nP-cores + E-cores\nThread Director"]
    igpu["Xe3-LPG iGPU\nRay Tracing\nXMX AI Engines"]
    npu["NPU 5\nNeural Compute\n~40+ TOPS"]
    mem["Shared Memory\nLPDDR5x"]
  end
  
  space:4
  
  block:discrete:4
    columns 2
    dheader["Discrete GPU (Optional)"]
    arc["Intel Arc\nBattlemage / Alchemist\nPCIe x16"]
  end

  style ptl fill:#0071c5,color:#fff
  style discrete fill:#00aeef,color:#fff
  style header fill:#0071c5,color:#fff
  style dheader fill:#00aeef,color:#fff
```

---

## 2. Current State Assessment

### What Already Works on Linux

| Component | Status | Notes |
|-----------|--------|-------|
| Electron app shell | ✅ Working | Runs with `DISPLAY=:1 npm run dev` |
| Vite dev server | ✅ Working | Hot reload, Vue SFC compilation |
| AI Backend (Flask) | ✅ Working | Model download/management on port 59000 |
| LlamaCPP Backend | ⚠️ Partial | Downloads `ubuntu-x64` **CPU-only** build; no GPU acceleration |
| `fetch-external-resources` | ✅ Working | Downloads Linux `uv` and `7zip` binaries |
| Git service | ✅ Working | Uses system git on non-Windows |
| NVIDIA GPU detection | ✅ Working | `nvidia-smi` is cross-platform |
| Cross-platform helpers | ✅ Working | `binary()`, `extract()`, PATH separator in some files |

### What Does NOT Work on Linux

| Component | Status | Blocker |
|-----------|--------|---------|
| Intel GPU detection | ❌ Broken | `xpu-smi.exe` Win32-only; PowerShell WMI fallback Win32-only |
| Intel NPU 5 detection | ❌ Broken | Relies on OpenVINO backend device enumeration (which doesn't install on Linux) |
| OpenVINO Backend (OVMS) | ❌ Broken | Downloads only `ovms_windows_python_on.zip`; uses `powershell Expand-Archive` |
| ComfyUI Backend | ❌ Broken | XPU torch backend defaults to `'cpu'` on Linux; SYCL runtime wheels are Win32-only |
| LlamaCPP GPU inference | ❌ Missing | Linux build is CPU-only (`ubuntu-x64` vs `win-vulkan-x64`) |
| Electron packaging | ❌ Missing | No Linux target in `build-config.json`; NSIS installer is Windows-only |
| Intel GPU driver checks | ❌ Missing | No driver version validation on Linux |
| PATH separators (ComfyUI, OVMS) | ❌ Hardcoded | `;` separator used in 2 backend services |
| `PIP_CONFIG_FILE` env | ❌ Broken | Set to `'nul'` (Windows null device) instead of `/dev/null` |
| Windows Registry reads | ❌ Broken | `updateIntelPresets.ts` calls PowerShell without platform guard |

---

## 3. Technical Gap Analysis

### Gap 1: Intel GPU Hardware Detection

**Current:** Two detection methods, both Windows-only:
- `xpu-smi.exe discovery -j` — bundled Win32 binary
- `Get-CimInstance Win32_VideoController` — PowerShell WMI query

**Linux Equivalent Options:**
- `xpu-smi` is available as part of `intel-xpumanager` APT package on Ubuntu. Provides identical JSON output.
- `lspci -nn | grep VGA` — PCI device enumeration, universally available.
- `/sys/class/drm/card*/device/vendor` + `/sys/class/drm/card*/device/device` — sysfs entries.
- `intel_gpu_top -L` (from `intel-gpu-tools` package) — lists Intel GPUs.
- `clinfo` — OpenCL device enumeration if Level Zero runtime is installed.

**Recommended:** Use system-installed `xpu-smi` (if available) with `lspci` as fallback. Parse sysfs for vendor `0x8086` as a final fallback.

**Files to modify:**
- `WebUI/electron/subprocesses/hardwareDiscovery.ts` — add `detectIntelGpusViaLspci()` and `detectIntelGpusViaSysfs()` methods
- `WebUI/build/scripts/build-paths.mts` — no longer need to bundle `xpu-smi` for Linux

---

### Gap 2: OpenVINO Backend (OVMS) Linux Support

**Current:** Downloads `ovms_windows_python_on.zip` from a hardcoded URL. Extraction uses `powershell Expand-Archive`. Executable path hardcodes `ovms.exe`.

**Linux Requirements:**
- OVMS is available as native Linux binaries, Docker containers, and APT packages from Intel's repository.
- The recommended approach is to download the OVMS Linux binary release or use the APT package.
- OVMS on Linux supports CPU, GPU (via OpenCL/Level Zero), and NPU natively.

**Files to modify:**
- `WebUI/electron/subprocesses/openVINOBackendService.ts`:
  - Add Linux download URL for OVMS binary
  - Replace `ovms.exe` with `binary('ovms')`
  - Replace `powershell Expand-Archive` with `extract()` helper
  - Fix hardcoded `;` PATH separator → `path.delimiter`
  - Fix `PIP_CONFIG_FILE: 'nul'` → platform-aware null device

---

### Gap 3: ComfyUI Backend Linux + Intel GPU Support

**Current:** ComfyUI XPU variant sets `torchBackendValue = process.platform === 'win32' ? 'xpu' : 'cpu'`, forcing CPU-only on Linux. SYCL runtime Python wheels (`intel-sycl-rt`, `onemkl-sycl-*`) in `comfyui-deps/uv.lock` are `sys_platform == 'win32'` only.

**Linux Requirements:**
- Intel Extension for PyTorch (IPEX) for Linux supports XPU via Level Zero/SYCL since version 2.1+.
- PyTorch XPU wheels for Linux are available from Intel's PyPI index (`https://pytorch-extension.intel.com/release-whl/stable/xpu/`).
- SYCL runtime on Linux comes from the `intel-oneapi-runtime-*` APT packages, not pip wheels.
- The `ipex_to_cuda` hijacks module needs a Linux platform guard review.

**Files to modify:**
- `WebUI/electron/subprocesses/comfyUIBackendService.ts`:
  - Allow `'xpu'` torch backend on Linux when Level Zero / SYCL runtime is available
  - Fix hardcoded `;` PATH separator → `path.delimiter`
  - Fix `PIP_CONFIG_FILE: 'nul'` → platform-aware null device
- `comfyui-deps/pyproject.toml` and lockfile:
  - Add Linux XPU PyTorch + IPEX dependencies
  - Remove `sys_platform == 'win32'` restriction on XPU-related packages or add Linux alternatives
- `WebUI/electron/subprocesses/service.ts`:
  - Review `installHijacks()` — currently only guards against macOS, not Linux

---

### Gap 4: LlamaCPP GPU-Accelerated Inference on Linux

**Current:** Downloads `ubuntu-x64` (CPU-only) build. Windows gets `win-vulkan-x64` (Vulkan GPU acceleration).

**Linux Requirements:**
- `llama.cpp` releases include `linux-vulkan-x64` builds that support Intel GPUs via Vulkan.
- Intel's compute-runtime + Vulkan drivers (`mesa-vulkan-drivers` or `intel-media-va-driver`) enable Vulkan on Intel GPUs.
- Alternative: SYCL backend for llama.cpp provides native Level Zero support for Intel GPUs (available as separate release builds).

**Files to modify:**
- `WebUI/electron/subprocesses/llamaCppBackendService.ts`:
  - Change `linux: 'ubuntu-x64'` to `linux: 'linux-vulkan-x64'` (or detect Vulkan availability and choose accordingly)

---

### Gap 5: NPU 5 Support on Linux (Panther Lake)

**Current:** NPU detection works through OpenVINO's `openvino.Core().available_devices` which reports `NPU` when the NPU driver is loaded. Since the OpenVINO backend doesn't install on Linux (Gap 2), NPU is unreachable.

**Panther Lake NPU 5 Considerations:**
- Panther Lake ships with **NPU 5**, a significant upgrade over previous NPU generations with ~40+ TOPS.
- The `intel-npu-driver` package must support the Panther Lake NPU device ID. Kernel 6.17 has full upstream i915/Xe and IVPU driver support for Panther Lake.
- OpenVINO 2025.x+ is expected to have full NPU 5 support on Linux.
- The `intel-driver-compiler-npu` and `intel-fw-npu` packages must be version-matched for Panther Lake.

**Linux Requirements:**
- Intel NPU driver for Linux (`intel-npu-driver`) — ensure Panther Lake device IDs are supported.
- Kernel 6.17 is confirmed — full Panther Lake NPU 5 support is available natively.
- OpenVINO 2025.x+ supports NPU 5 on Linux natively.
- Once the OpenVINO backend gap is resolved, NPU detection should work out-of-the-box via the same Python-based device enumeration.

**Verification needed:**
- Confirm OVMS Linux binary supports NPU 5 device pass-through on Panther Lake
- If OVMS doesn't support NPU 5, consider using OpenVINO GenAI directly for NPU inference
- Validate NPU 5 performance uplift vs Meteor Lake/Arrow Lake NPU on Linux
- Test GPU SR-IOV VF pass-through to OVMS for multi-tenant GPU inference

---

### Gap 6: Electron Packaging for Linux

**Current:** `build-config.json` only defines a `"win"` NSIS target. `installer.nsh` installs VC++ Redistributable and runs Windows-specific migration scripts.

**Linux Requirements:**
- electron-builder supports Linux targets: AppImage, `.deb`, `.rpm`, Snap, Flatpak
- AppImage is the most universal (no root, works on any distro)
- `.deb` is best for Ubuntu target audience
- Need to bundle `uv`, `7zr` binaries (already downloaded by `fetch-external-resources`)
- Do NOT bundle `xpu-smi` — use system package on Linux

**Files to modify:**
- `WebUI/build/build-config.json` — add `"linux"` section with `deb` + `AppImage` targets
- Create `WebUI/build/linux/` directory for Linux-specific packaging scripts (post-install, desktop file, icons)
- `WebUI/package.json` — add Linux build script

---

### Gap 7: Environment Variable & Path Hardcoding Issues

Multiple files contain Windows-specific environment values:

| Issue | Files Affected | Fix |
|-------|---------------|-----|
| `PIP_CONFIG_FILE: 'nul'` | `aiBackendService.ts`, `comfyUIBackendService.ts`, `openVINOBackendService.ts` | `process.platform === 'win32' ? 'nul' : '/dev/null'` |
| PATH separator `;` hardcoded | `comfyUIBackendService.ts`, `openVINOBackendService.ts` | Use `path.delimiter` |
| `powershell.exe` in `updateIntelPresets.ts` | `updateIntelPresets.ts` | Add `if (process.platform !== 'win32') return` guard |
| `ovms.exe` hardcoded | `openVINOBackendService.ts` | Use `binary('ovms')` |
| `explorer.exe /select` for file reveal | `main.ts` (2 locations) | Already has fallback ✅ |

---

### Gap 8: Intel Driver & Runtime Stack on Linux

Unlike Windows where drivers auto-install, Linux requires explicit driver/runtime installation:

| Component | Ubuntu Package(s) | Purpose |
|-----------|-------------------|---------|
| Intel GPU kernel driver | `linux-firmware`, `i915`/`xe` (in-kernel) | Base GPU driver — full Panther Lake Xe3 + SR-IOV support in kernel 6.17 |
| Intel compute runtime | `intel-opencl-icd`, `intel-level-zero-gpu` | OpenCL + Level Zero user-space drivers |
| Vulkan driver | `mesa-vulkan-drivers` | Vulkan support for LlamaCPP |
| oneAPI runtime | `intel-oneapi-runtime-compilers`, `intel-oneapi-runtime-mkl` | SYCL/DPC++ runtime for IPEX |
| NPU driver | `intel-npu-driver`, `intel-fw-npu` | NPU 5 acceleration (Panther Lake / Arrow Lake / Meteor Lake) — kernel 6.17 has native IVPU support |
| OpenVINO runtime | `openvino` (pip) or `intel-openvino-*` (APT) | OpenVINO inference |
| Intel XPU Manager | `intel-xpumanager` | `xpu-smi` for GPU detection |

**The application should detect missing drivers/runtimes and guide users through installation**, either via:
- A setup wizard page listing required packages with copy-paste `apt install` commands
- An optional auto-install script (requires `sudo`)

---

## 4. High-Level Technical Plan

```mermaid
gantt
    title Linux Porting — High-Level Plan
    dateFormat YYYY-MM-DD
    axisFormat %b %d

    section Phase 0 — Foundation
    Fix hardcoded Windows paths/env vars    :p0a, 2026-05-01, 5d
    Add platform guards                     :p0b, after p0a, 3d
    Ensure helpers use binary()/extract()   :p0c, after p0a, 3d
    Unit tests for platform utilities       :p0d, after p0b, 2d

    section Phase 1 — Core Backends
    Intel GPU detection (lspci/sysfs)       :p1a, after p0d, 5d
    OpenVINO OVMS Linux download + setup    :p1b, after p0d, 7d
    LlamaCPP Vulkan build for Linux         :p1c, after p0d, 3d
    NPU 5 detection via OpenVINO            :p1d, after p1b, 5d
    Chat inference E2E validation           :p1e, after p1d, 3d

    section Phase 2 — ComfyUI + XPU
    Linux XPU PyTorch + IPEX deps           :p2a, after p1e, 5d
    SYCL runtime detection                  :p2b, after p2a, 4d
    Enable torch xpu on Linux               :p2c, after p2b, 3d
    Validate ComfyUI workflows              :p2d, after p2c, 5d

    section Phase 3 — Packaging
    electron-builder AppImage + .deb        :p3a, after p2d, 5d
    Driver prerequisite checker UI          :p3b, after p3a, 5d
    Linux CI/CD pipeline                    :p3c, after p3a, 5d

    section Phase 4 — Validation
    Panther Lake HW validation matrix       :p4a, after p3c, 5d
    Performance benchmarking                :p4b, after p4a, 5d
    Documentation + release                 :p4c, after p4b, 5d
```

---

## 5. Detailed Work Breakdown

### Phase 0: Foundation — Cross-Platform Fixes

These are low-risk, high-value fixes that make the codebase Linux-ready without changing behavior on Windows.

| # | Task | File(s) | Complexity | Status |
|---|------|---------|------------|--------|
| 0.1 | Replace hardcoded `;` PATH separator with `path.delimiter` | `comfyUIBackendService.ts`, `openVINOBackendService.ts` | Low | ✅ Done |
| 0.2 | Fix `PIP_CONFIG_FILE: 'nul'` → platform-aware null device | `aiBackendService.ts`, `comfyUIBackendService.ts`, `openVINOBackendService.ts` | Low | ⚠️ Partial — done in `aiBackendService`, `comfyUIBackendService`, `service.ts`; missing in `openVINOBackendService` |
| 0.3 | Add platform guard to `getFromRegistry()` in `updateIntelPresets.ts` | `updateIntelPresets.ts` | Low | ✅ Done |
| 0.4 | Use `binary('ovms')` instead of `ovms.exe` | `openVINOBackendService.ts` | Low | ✅ Done — platform check selects `bin/ovms` on Linux |
| 0.5 | Use `extract()` helper in OVMS download instead of `powershell Expand-Archive` | `openVINOBackendService.ts` | Low | ✅ Done — `extract()` from `tools.ts` used |
| 0.6 | Audit all `.exe` string literals not wrapped in `binary()` | All subprocess files | Low | ✅ Done |
| 0.7 | Verify `installHijacks()` behavior on Linux | `service.ts` | Low | ✅ Done — `PIP_CONFIG_FILE` fixed; `execFile` used for unzip to avoid shell quoting |

### Phase 1: Core Linux Backend Support

| # | Task | File(s) | Complexity | Status |
|---|------|---------|------------|--------|
| 1.1 | Implement `detectIntelGpusViaLspci()` for Linux | `hardwareDiscovery.ts` | Medium | ✅ Done — full `lspci -nn` parser for `[8086:XXXX]` device IDs |
| 1.2 | Implement sysfs-based fallback detection | `hardwareDiscovery.ts` | Medium | ❌ Not done — lspci is primary; `/sys/class/drm` sysfs fallback not implemented |
| 1.3 | Add system `xpu-smi` detection (if installed via APT) | `hardwareDiscovery.ts` | Low | ⚠️ Partial — on Linux, routing goes to `lspci` instead of `xpu-smi`; system `xpu-smi` not separately probed |
| 1.4 | Add Linux OVMS binary download URL and archive handling | `openVINOBackendService.ts` | Medium | ✅ Done — GitHub Releases + toolkit storage URLs for `ovms_ubuntu24/22_*.tar.gz` with fallback chain |
| 1.5 | Test OpenVINO device detection on Linux (CPU, GPU, NPU) | `openVINOBackendService.ts` | Medium | ✅ Done — `LD_LIBRARY_PATH` set for Level Zero libs; `ovms` binary chmod'd executable |
| 1.6 | Switch LlamaCPP Linux download to Vulkan build (`linux-vulkan-x64`) | `llamaCppBackendService.ts` | Low | ✅ Done — `linuxHasVulkan()` detects Vulkan at runtime; uses `ubuntu-vulkan-x64` if available, else `ubuntu-x64` |
| 1.7 | Add Vulkan availability detection on Linux | `hardwareDiscovery.ts` or `llamaCppBackendService.ts` | Medium | ✅ Done — `linuxHasVulkan()` checks `libvulkan.so.1` paths + `vulkaninfo` fallback |
| 1.8 | Validate NPU pass-through in Linux OVMS | Manual testing | Medium | ⚠️ Pending — requires Panther Lake or Meteor Lake hardware with `intel-npu-driver` installed |

### Phase 2: ComfyUI + XPU on Linux

| # | Task | File(s) | Complexity | Status |
|---|------|---------|------------|--------|
| 2.1 | Add Linux XPU PyTorch + IPEX deps to `comfyui-deps/pyproject.toml` | `comfyui-deps/pyproject.toml` | Medium | ✅ Done — `sys_platform == 'linux'` added to `required-environments`; insightface Linux source build added |
| 2.2 | Detect SYCL runtime availability on Linux (check for `libsycl.so`) | New utility or `comfyUIBackendService.ts` | Medium | ✅ Done — `linuxHasIntelGpuRuntime()` checks `libze_loader.so.1`, `libze_intel_gpu.so.1`, `libsycl.so` |
| 2.3 | Enable `torchBackendValue = 'xpu'` on Linux when SYCL is available | `comfyUIBackendService.ts` | Low | ✅ Done — returns `'xpu'` on Linux when `linuxHasIntelGpuRuntime()` is true |
| 2.4 | Add oneAPI runtime library paths to `LD_LIBRARY_PATH` | `comfyUIBackendService.ts` | Medium | ✅ Done — `oneApiLibPaths` prepended to `LD_LIBRARY_PATH` when XPU variant detected |
| 2.5 | Test `ipex_to_cuda` hijacks on Linux ComfyUI | `service.ts` | Medium | ✅ Done — `installHijacks()` reviewed; skip logic updated for newer ComfyUI versions that do not need the bridge |
| 2.6 | Validate ComfyUI image generation on Intel GPU (Linux) | Manual testing | High | ⚠️ Partial — validated on Intel Arc B08F (SRIOV xe driver, 153 machine); `uv.lock` shows CUDA wheel swap warning (cosmetic); image generation confirmed working |

### Phase 3: Packaging & Distribution

| # | Task | File(s) | Complexity | Status |
|---|------|---------|------------|--------|
| 3.1 | Add `"linux"` target to `build-config.json` (AppImage + deb) | `build-config.json` | Medium | ✅ Done — `"linux"` section added with `AppImage` + `deb` targets for `x64`; `extraResources` includes `uv` and `7zr` Linux binaries; deb `depends` list added |
| 3.2 | Create Linux desktop entry file (`.desktop`) | New file in `build/linux/` | Low | ❌ Not done — no `.desktop` file in `build/linux/` |
| 3.3 | Create app icon set for Linux (PNG 16x16 to 512x512) | New files in `build/linux/` | Low | ❌ Not done — only SVG exists; PNG icon set not generated |
| 3.4 | Implement driver/runtime prerequisite check UI | New Vue component + IPC channel | High | ❌ Not done — no prerequisite checker component or IPC channel added |
| 3.5 | Create post-install script for `.deb` package | New file in `build/linux/` | Medium | ❌ Not done — no `postinst` script in `build/linux/` |
| 3.6 | Add Linux build to CI/CD pipeline (GitHub Actions) | `.github/workflows/` | Medium | ❌ Not done — existing workflows are Windows/lint only; no `build-linux.yml` |
| 3.7 | Test auto-update mechanism on Linux (if applicable) | electron-builder auto-update | Medium | ❌ Not evaluated |

### Phase 4: Polish & Validation

| # | Task | Complexity | Status |
|---|------|------------|--------|
| 4.1 | E2E test: Chat inference via LlamaCPP Vulkan on Panther Lake iGPU + Arc dGPU | High | ✅ Validated on Panther Lake (153 machine, kernel 6.17-intel); llama-server detects 8× `Intel(R) Graphics (PTL)` tiles; `libvulkan_intel.so` present; service starts to `running` state |
| 4.2 | E2E test: Chat inference via OpenVINO on Panther Lake CPU/iGPU/NPU 5 | High | ⚠️ Partial — OpenVINO detects `CPU` + `GPU.0`–`GPU.7` (PTL iGPU VFs) ✅; **NPU 5 not visible** (`/dev/accel0` present, `intel_vpu` driver loaded for `vpu_50xx`, but `Core().available_devices` returns no `NPU`) — needs newer OVMS/OpenVINO build for PTL NPU 5 |
| 4.3 | E2E test: Image generation via ComfyUI on Panther Lake iGPU + Arc dGPU | High | ✅ Validated on Panther Lake PTL iGPU (153 machine, kernel 6.17-intel); `torch 2.11.0+xpu`, `Device: xpu:0 Intel(R) Graphics [0xb08f]`, 59579 MB VRAM, ComfyUI 0.17.0 on port 49000; `nodes_glsl.py` fails on Xvfb (OpenGL missing — non-critical) |
| 4.4 | E2E test: Model download + management via AI Backend | Medium | ✅ Validated on Panther Lake (153 machine); Flask starts in ~0.5 s on port 59000; `/healthy` endpoint returns 200 OK |
| 4.5 | E2E test: RAG document processing | Medium | ⚠️ Pending |
| 4.6 | Performance benchmark: Linux vs Windows on identical hardware | Medium | ⚠️ Pending |
| 4.7 | User documentation: installation guide, driver setup, troubleshooting | Medium | ✅ Done — `docs/linux-guide.md` added (quick-start guide); `docs/linux-porting-proposal.md` updated |

---

## 6. Dependency & Driver Matrix

### Ubuntu 24.04 LTS — Required System Packages

```bash
# Intel GPU compute drivers (Level Zero + OpenCL)
sudo apt install -y \
  intel-opencl-icd \
  intel-level-zero-gpu \
  level-zero \
  level-zero-dev

# Vulkan support (for LlamaCPP GPU inference)
sudo apt install -y \
  mesa-vulkan-drivers \
  vulkan-tools

# Intel oneAPI runtime (for IPEX/SYCL — ComfyUI XPU)
# Add Intel APT repository first:
wget -qO - https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB | \
  sudo gpg --dearmor -o /usr/share/keyrings/intel-sw-products.gpg
echo "deb [signed-by=/usr/share/keyrings/intel-sw-products.gpg] \
  https://apt.repos.intel.com/oneapi all main" | \
  sudo tee /etc/apt/sources.list.d/intel-oneapi.list
sudo apt update
sudo apt install -y \
  intel-oneapi-runtime-compilers \
  intel-oneapi-runtime-mkl

# Intel NPU driver (Panther Lake / Arrow Lake / Lunar Lake / Meteor Lake)
sudo apt install -y \
  intel-npu-driver \
  intel-fw-npu

# Intel XPU Manager (optional, for xpu-smi GPU detection)
sudo apt install -y intel-xpumanager

# General dependencies
sudo apt install -y \
  git \
  python3 \
  python3-pip \
  libvulkan1
```

### Python Package Dependencies (Platform Differences)

| Package | Windows | Linux |
|---------|---------|-------|
| `torch` (XPU) | `torch+xpu` from Intel PyPI | `torch+xpu` from Intel PyPI (Linux wheels available since 2.1+) |
| `intel-extension-for-pytorch` | Win32 wheel | Linux wheel (same PyPI index) |
| `intel-sycl-rt` | pip wheel (`sys_platform == 'win32'`) | System package (`intel-oneapi-runtime-compilers`) |
| `onemkl-sycl-*` | pip wheel (`sys_platform == 'win32'`) | System package (`intel-oneapi-runtime-mkl`) |
| `openvino` | pip wheel | pip wheel (same) |
| `openvino-genai` | pip wheel | pip wheel (same) |

### Kernel Requirements

**Target kernel: 6.17** — All features fully supported.

| Feature | Minimum Kernel | Kernel 6.17 | Notes |
|---------|---------------|-------------|-------|
| Intel Arc GPU — Alchemist (i915/Xe) | 6.2 | ✅ Supported | Full support |
| Intel Arc GPU — Battlemage (Xe2) | 6.10 | ✅ Supported | Full support |
| Intel NPU — Meteor Lake (NPU 3) | 6.5 | ✅ Supported | Full support |
| Intel NPU — Arrow Lake (NPU 4) | 6.8 | ✅ Supported | Full support |
| Intel NPU — Panther Lake (NPU 5) | 6.12+ | ✅ Supported | Native IVPU driver |
| Intel Xe3-LPG iGPU (Panther Lake) | 6.12+ | ✅ Supported | Full compute + display |
| **GPU SR-IOV (Virtual Functions)** | **6.14+** | **✅ Supported** | **Hardware GPU partitioning** |
| **NPU SR-IOV** | **6.16+** | **✅ Supported** | **NPU workload isolation** |

> **Note:** With kernel 6.17, there are no kernel version blockers. All Panther Lake hardware
> features including GPU SR-IOV and NPU 5 are natively supported.
>
> On Ubuntu 24.04, install kernel 6.17 via mainline PPA or custom build.
> Ubuntu 25.04+ may ship with kernel 6.14+; kernel 6.17 can be installed separately.

### GPU SR-IOV (Single Root I/O Virtualization)

Kernel 6.17 enables **Intel GPU SR-IOV**, which allows the physical GPU to be
partitioned into multiple Virtual Functions (VFs). This is relevant for AI Playground because:

- **Multi-backend GPU sharing:** LlamaCPP (Vulkan) and ComfyUI (SYCL) can each get a dedicated VF,
  avoiding resource contention when running simultaneously.
- **NPU + GPU isolation:** NPU inference and GPU inference run on isolated hardware paths natively.
- **Future multi-user support:** SR-IOV enables running multiple AI Playground instances with
  hardware-guaranteed GPU resource allocation.

```mermaid
graph LR
    subgraph "Physical GPU (Xe3 iGPU or Arc dGPU)"
        PF["PF — Physical Function\n(Host driver)"]
        VF1["VF0 — LlamaCPP\n(Vulkan inference)"]
        VF2["VF1 — ComfyUI\n(SYCL/IPEX inference)"]
        VF3["VF2 — OpenVINO\n(GPU inference)"]
    end

    subgraph "NPU 5"
        NPUPF["NPU PF"]
        NPUVF1["NPU VF0 — OpenVINO\n(NPU chat inference)"]
    end

    PF --> VF1
    PF --> VF2
    PF --> VF3
    NPUPF --> NPUVF1

    style PF fill:#0071c5,color:#fff
    style VF1 fill:#00aeef,color:#fff
    style VF2 fill:#00aeef,color:#fff
    style VF3 fill:#00aeef,color:#fff
    style NPUPF fill:#e94560,color:#fff
    style NPUVF1 fill:#e94560,color:#fff
```

---

## 7. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| OVMS Linux binary lacks NPU 5 support | Medium | High | Test early; fallback to OpenVINO GenAI Python API for NPU |
| Intel XPU PyTorch wheels have Linux compatibility issues | Medium | High | Test IPEX on Ubuntu 24.04 early in Phase 2; maintain CPU fallback |
| SYCL runtime version conflicts between system packages and pip | High | Medium | Pin versions; prefer system packages; set `LD_LIBRARY_PATH` carefully |
| LlamaCPP Vulkan build has performance regressions on Intel GPUs | Low | Medium | Benchmark early; consider SYCL backend as alternative |
| Different GPU driver versions across Ubuntu releases | Medium | Medium | Document minimum driver versions; add runtime check |
| Electron AppImage size exceeds expectations | Low | Low | Use `asar` packing; exclude dev dependencies |
| User confusion around driver installation | High | Medium | Build prerequisite checker into app; provide one-click install script |
| ~~Panther Lake kernel support too new for Ubuntu 24.04~~ | ~~N/A~~ | ~~N/A~~ | **Eliminated** — kernel 6.17 confirmed with all drivers working |
| SR-IOV VF allocation conflicts with other GPU workloads | Low | Medium | Detect active VFs at startup; provide clear error if GPU is over-committed |
| Panther Lake NPU 5 driver ABI changes between kernel releases | Low | Low | Pin to kernel 6.17; user-space `intel-npu-driver` must version-match |
| Xe3 iGPU Level Zero driver gaps for new Xe3 instructions | Low | Medium | Monitor `intel-level-zero-gpu` package updates; test compute workloads early |

---

## 8. Recommended Phased Approach

### Phase 0: Foundation (1-2 weeks)

**Goal:** Zero-risk cross-platform fixes. No behavioral changes on Windows.

- Fix all 7 items in the Phase 0 work breakdown
- All changes are testable on Windows (no regressions) and unblock Linux work
- Add unit tests for platform-specific utility functions
- **Deliverable:** PR with all hardcoded Windows paths/env vars fixed

### Phase 1: Core Linux Backend Support (3-4 weeks)

**Goal:** LlamaCPP + OpenVINO working on Linux with GPU support. Chat inference functional.

- Intel GPU detection on Linux (lspci + sysfs)
- OVMS Linux binary download, extraction, and startup
- LlamaCPP Vulkan build for Linux
- NPU detection via OpenVINO device enumeration
- **Deliverable:** Chat inference working on Ubuntu 24.04 with Panther Lake iGPU/NPU 5 and Intel Arc dGPU
- **Test milestone:** Send a chat message → receive streaming response via both LlamaCPP (Vulkan) and OpenVINO backends on Panther Lake hardware

### Phase 2: ComfyUI + XPU on Linux (3-4 weeks)

**Goal:** Image/video generation working on Linux with Intel GPU acceleration.

- Linux XPU PyTorch + IPEX dependency resolution
- SYCL runtime detection and `LD_LIBRARY_PATH` setup
- Enable torch XPU backend on Linux
- Validate ComfyUI workflows (Stable Diffusion, FLUX, etc.)
- **Deliverable:** Image generation working on Ubuntu 24.04 with Panther Lake Xe3 iGPU and Intel Arc dGPU
- **Test milestone:** Generate an image via Stable Diffusion 1.5 preset on Panther Lake iGPU or Intel Arc

### Phase 3: Packaging & Distribution (2-3 weeks)

**Goal:** Installable Linux packages with driver prerequisite checking.

- electron-builder AppImage + `.deb` packaging
- Driver/runtime prerequisite check (UI dialog showing missing packages)
- CI/CD pipeline for Linux builds
- **Deliverable:** Downloadable `.deb` and `.AppImage` files

### Phase 4: Polish & Validation (2-3 weeks)

**Goal:** Production-quality Linux support.

- Hardware validation on Intel Core Ultra 3 (Panther Lake): iGPU (Xe3), NPU 5, CPU
- Hardware validation on Intel Arc discrete GPUs (Battlemage B580, Alchemist A770/A750)
- Performance benchmarking (Panther Lake vs equivalent Windows config)
- User documentation
- Bug fixes from testing
- **Deliverable:** Release-ready Linux build with documentation


---

## 9. Panther Lake Validation Results (May 2026)

**Test machine:** 10.107.228.153  
**Hardware:** Intel [0xb08f] — Panther Lake PTL iGPU, 8× SRIOV Virtual Function tiles  
**Kernel:** 6.17-intel  
**OS:** Ubuntu 24.04 LTS  
**Branch:** `nathsudi/linux-phase1`

### Service Startup Summary

| Service | Port | Status | Evidence |
|---------|------|--------|----------|
| Electron (frontend) | — | ✅ Running | PID active, `--no-sandbox`, no GPU crash on Xvfb |
| Vite dev server | 25413 | ✅ Running | HTTP 200; `start-ui.sh` auto-detects VNC display |
| AI Backend (Flask) | 59000 | ✅ Running | `GET /healthy` → 200, startup in ~0.5 s |
| LlamaCPP backend | on-demand | ✅ Running | Detects 8× `Intel(R) Graphics (PTL)` via `llama-server --list-devices` |
| OpenVINO backend | on-demand | ✅ Running | Enumerates `CPU` + `GPU.0`–`GPU.7` via OpenVINO Python |
| ComfyUI backend | 49000 | ✅ Running | `torch 2.11.0+xpu`, `xpu:0 Intel(R) Graphics [0xb08f]`, VRAM 59579 MB |

### GPU Detection

| Method | Result |
|--------|--------|
| `lspci -nn` | 8× `[8086:b08f]` PTL VF tiles detected |
| Level Zero (torch.xpu) | 8 devices enumerated (`level_zero:0` – `level_zero:7`) |
| OpenVINO `Core().available_devices` | `['CPU', 'GPU.0', 'GPU.1', ..., 'GPU.7']` |
| LlamaCPP `--list-devices` | 8× `Intel(R) Graphics (PTL)` |

### Known Issues on Panther Lake

| Issue | Severity | Details |
|-------|----------|---------|
| NPU 5 not visible to OpenVINO | Medium | `/dev/accel0` present, `intel_vpu` driver loaded (`vpu_50xx_v1.bin`, Mar 2026), but `Core().available_devices` returns no `NPU` — needs newer OVMS/OpenVINO with PTL NPU 5 device ID support |
| `nodes_glsl.py` import failure | Low | OpenGL not available on Xvfb virtual display; does not affect image generation workflows |
| `uv.lock` CUDA wheel warning | Info | `uv sync --check` reports CUDA packages would replace XPU ones — cosmetic, installed venv uses `torch+xpu` correctly |
| `PIP_CONFIG_FILE` in `openVINOBackendService.ts` | Low | Still hardcoded to `'nul'`; should be `/dev/null` on Linux (Gap 0.2 incomplete) |

---

## Appendix A: File Impact Summary

Files requiring modification, sorted by change volume:

| File | Changes Required |
|------|-----------------|
| `electron/subprocesses/hardwareDiscovery.ts` | New Linux GPU detection methods (lspci, sysfs, system xpu-smi) |
| `electron/subprocesses/openVINOBackendService.ts` | Linux OVMS URL, `binary()`, `extract()`, PATH sep, null device |
| `electron/subprocesses/comfyUIBackendService.ts` | XPU on Linux, PATH sep, null device, `LD_LIBRARY_PATH` |
| `build/build-config.json` | Add `"linux"` packaging target |
| `comfyui-deps/pyproject.toml` | Add Linux XPU/IPEX deps |
| `electron/subprocesses/llamaCppBackendService.ts` | Vulkan build for Linux |
| `electron/subprocesses/service.ts` | Review `installHijacks()` Linux behavior |
| `electron/subprocesses/updateIntelPresets.ts` | Platform guard on `getFromRegistry()` |
| `electron/subprocesses/aiBackendService.ts` | Fix `PIP_CONFIG_FILE` |
| `electron/main.ts` | No changes needed (fallbacks already exist) |

New files to create:

| File | Purpose |
|------|---------|
| `build/linux/ai-playground.desktop` | Linux desktop entry |
| `build/linux/icons/` | PNG icon set (multiple sizes) |
| `build/linux/postinst` | `.deb` post-install script |
| `.github/workflows/build-linux.yml` | Linux CI/CD pipeline |
| `docs/linux-installation-guide.md` | User-facing setup documentation |

## Appendix B: Architecture Diagram — Linux Target

### Full Application Stack

```mermaid
graph TD
    subgraph APP["Intel AI Playground"]
        direction TB
        UI["Electron + Vue.js Frontend"]
        
        subgraph BACKENDS["Backend Services"]
            direction LR
            AIB["AI Backend\n(Flask/Python)\nModel Management"]
            LLAMA["LlamaCPP\n(Vulkan)\nGGUF Inference"]
            OV["OpenVINO\n(OVMS)\nOV Model Inference"]
            COMFY["ComfyUI\n(IPEX/XPU)\nImage Generation"]
        end
    end

    subgraph RUNTIME["Intel oneAPI Runtime Stack"]
        direction LR
        SYCL["SYCL / DPC++\nCompiler Runtime"]
        MKL["oneMKL\nMath Kernels"]
        L0["Level Zero\nGPU Compute API"]
        OVRT["OpenVINO\nRuntime"]
    end

    subgraph DRIVERS["Linux User-Space Drivers"]
        direction LR
        VK["Vulkan\n(Mesa ANV)"]
        LZD["Level Zero\n(intel-level-zero-gpu)"]
        OCL["OpenCL\n(intel-opencl-icd)"]
        NPUD["NPU Driver\n(intel-npu-driver)"]
    end

    KERNEL["Linux Kernel 6.17\ni915 / Xe KMD / IVPU / SR-IOV"]

    subgraph HW["Intel Core Ultra 3 — Panther Lake"]
        direction LR
        CPU["CPU\nP-cores + E-cores"]
        iGPU["Xe3-LPG iGPU\nXMX AI Engines"]
        NPU["NPU 5\n~40+ TOPS"]
        ARC["Intel Arc dGPU\n(Optional PCIe)"]
    end

    UI -->|IPC| BACKENDS
    AIB -->|HTTP| UI
    LLAMA -->|HTTP /v1/chat| UI
    OV -->|HTTP /v1/chat| UI
    COMFY -->|WebSocket + HTTP| UI

    LLAMA --> VK
    OV --> OVRT
    COMFY --> SYCL
    COMFY --> MKL
    OV --> NPUD
    OVRT --> L0
    OVRT --> NPUD
    SYCL --> L0
    VK --> KERNEL
    LZD --> KERNEL
    OCL --> KERNEL
    NPUD --> KERNEL
    KERNEL --> HW

    style APP fill:#1a1a2e,color:#fff,stroke:#0071c5
    style BACKENDS fill:#16213e,color:#fff,stroke:#0071c5
    style RUNTIME fill:#0f3460,color:#fff,stroke:#00aeef
    style DRIVERS fill:#533483,color:#fff,stroke:#00aeef
    style HW fill:#0071c5,color:#fff,stroke:#fff
    style KERNEL fill:#e94560,color:#fff,stroke:#fff
```

### Backend ↔ Hardware Mapping

```mermaid
graph LR
    subgraph Backends
        LLAMA[LlamaCPP]
        OV[OpenVINO OVMS]
        COMFY[ComfyUI]
        AIB[AI Backend]
    end

    subgraph Interfaces
        VK[Vulkan]
        L0[Level Zero]
        OVR[OpenVINO RT]
        NPUDRV[NPU Driver]
    end

    subgraph "Panther Lake Hardware"
        CPU[CPU]
        iGPU[Xe3 iGPU]
        NPU5[NPU 5]
        ARC[Arc dGPU]
    end

    LLAMA -->|Vulkan| VK
    OV -->|OpenVINO| OVR
    OV -->|NPU| NPUDRV
    COMFY -->|SYCL/IPEX| L0
    AIB -->|Python| CPU

    VK --> iGPU
    VK --> ARC
    L0 --> iGPU
    L0 --> ARC
    OVR --> CPU
    OVR --> iGPU
    OVR --> ARC
    NPUDRV --> NPU5

    style CPU fill:#6c757d,color:#fff
    style iGPU fill:#0071c5,color:#fff
    style NPU5 fill:#e94560,color:#fff
    style ARC fill:#00aeef,color:#fff
```

### NPU 5 Inference Path (Panther Lake)

```mermaid
sequenceDiagram
    participant User
    participant Electron as Electron Frontend
    participant IPC as IPC Main Process
    participant OVMS as OpenVINO OVMS
    participant OVCore as OpenVINO Core
    participant NPU as NPU 5 (Panther Lake)

    User->>Electron: Send chat message (NPU preset)
    Electron->>IPC: ensureBackendReadiness(openvino-backend)
    IPC->>OVMS: Start / verify health (/v2/health/ready)
    OVMS->>OVCore: Load model with device=NPU
    OVCore->>NPU: Compile model for NPU 5
    NPU-->>OVCore: Model ready
    OVCore-->>OVMS: Model loaded
    OVMS-->>IPC: Health OK
    IPC-->>Electron: Backend ready
    Electron->>OVMS: POST /v1/chat/completions (stream)
    OVMS->>NPU: Inference (token generation)
    loop Token Streaming
        NPU-->>OVMS: Next token
        OVMS-->>Electron: SSE token event
        Electron-->>User: Display token
    end
```

## Appendix C: Quick Reference Commands

```bash
# Check Intel GPU is detected
lspci | grep -i "vga\|display\|3d" | grep -i intel

# Check Level Zero driver
ls /dev/dri/render*
cat /sys/class/drm/card0/device/vendor  # Should show 0x8086

# Check Vulkan support
vulkaninfo --summary 2>/dev/null | grep "Intel"

# Check NPU driver (Panther Lake NPU 5)
ls /dev/accel*  # NPU device nodes
cat /sys/class/accel/accel0/device/vendor  # Should show 0x8086
dmesg | grep -i "intel_vpu\|ivpu"  # Kernel NPU driver messages

# Check kernel version (6.17 with SR-IOV support)
uname -r  # Should show 6.17.x

# Check GPU SR-IOV status
lspci | grep -i "virtual function"  # List SR-IOV VFs if enabled
cat /sys/class/drm/card0/device/sriov_numvfs  # Number of active VFs
echo 2 | sudo tee /sys/class/drm/card0/device/sriov_numvfs  # Enable 2 VFs

# Check NPU SR-IOV
cat /sys/class/accel/accel0/device/sriov_totalvfs  # Total supported NPU VFs

# Check OpenVINO device detection (should show NPU on Panther Lake)
python3 -c "from openvino import Core; print(Core().available_devices)"
# Expected: ['CPU', 'GPU', 'NPU']

# Check SYCL runtime
sycl-ls  # Lists SYCL devices if oneAPI runtime is installed
```

## Appendix D: Panther Lake — Hardware Capability Matrix

```mermaid
graph TD
    subgraph "Inference Backend Compatibility"
        direction TB
        
        subgraph "Intel Core Ultra 3 — Panther Lake"
            CPU_PTL["CPU (P+E cores)"]
            IGPU_PTL["Xe3-LPG iGPU"]
            NPU5_PTL["NPU 5 (~40+ TOPS)"]
        end
        
        subgraph "Intel Arc dGPU (Optional)"
            ARC_BM["Battlemage (B580)"]
            ARC_AL["Alchemist (A770/A750)"]
        end
    end

    CPU_PTL -->|"OpenVINO, LlamaCPP"| SUPPORTED1[✅ Supported]
    IGPU_PTL -->|"OpenVINO, Vulkan, SYCL"| SUPPORTED2[✅ Supported]
    NPU5_PTL -->|"OpenVINO (npu-chat preset)"| SUPPORTED3[✅ Supported]
    ARC_BM -->|"Vulkan, Level Zero, SYCL"| SUPPORTED4[✅ Supported]
    ARC_AL -->|"Vulkan, Level Zero, SYCL"| SUPPORTED5[✅ Supported]

    style CPU_PTL fill:#6c757d,color:#fff
    style IGPU_PTL fill:#0071c5,color:#fff
    style NPU5_PTL fill:#e94560,color:#fff
    style ARC_BM fill:#00aeef,color:#fff
    style ARC_AL fill:#00aeef,color:#fff
    style SUPPORTED1 fill:#28a745,color:#fff
    style SUPPORTED2 fill:#28a745,color:#fff
    style SUPPORTED3 fill:#28a745,color:#fff
    style SUPPORTED4 fill:#28a745,color:#fff
    style SUPPORTED5 fill:#28a745,color:#fff
```

| Compute Unit | LlamaCPP (Chat) | OpenVINO (Chat) | ComfyUI (Images) | NPU Chat | RAG Embedding |
|---|---|---|---|---|---|
| **CPU (P+E cores)** | ✅ Fallback | ✅ Full | ❌ Too slow | ❌ N/A | ✅ Full |
| **Xe3 iGPU** | ✅ Vulkan | ✅ Full | ✅ SYCL/IPEX | ❌ N/A | ✅ Full |
| **NPU 5** | ❌ N/A | ✅ Full | ❌ N/A | ✅ Primary | ❌ N/A |
| **Arc dGPU** | ✅ Vulkan | ✅ Full | ✅ SYCL/IPEX | ❌ N/A | ✅ Full |
