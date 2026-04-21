# Documentation Index - Linux POC

This directory contains documentation for the Intel AI Playground Linux port.

---

## Quick Start

**New to Linux POC?** Start here: **[LINUX_SETUP_GUIDE.md](LINUX_SETUP_GUIDE.md)**

---

## Primary Documentation

### For Users & Testers

**[LINUX_SETUP_GUIDE.md](LINUX_SETUP_GUIDE.md)** (14KB)
- Step-by-step installation instructions
- Prerequisites and system requirements
- Proxy configuration for Intel network
- Verification and testing procedures
- Troubleshooting common issues
- Known limitations

**Start here if you want to:** Run the application on Linux, test features, or troubleshoot issues.

---

### For Developers

**[LINUX_IMPLEMENTATION.md](LINUX_IMPLEMENTATION.md)** (33KB)
- Technical reference and architecture overview
- Complete code changes with diffs (6 files)
- Platform patterns and cross-platform helpers
- Verification commands
- Future work roadmap (Phases 2-6)

**Start here if you want to:** Understand the implementation, review code changes, or extend Linux support.

---

### For Project Stakeholders

**[LINUX_POC_RESULTS.md](LINUX_POC_RESULTS.md)** (16KB)
- POC success metrics and validation
- Test results and performance analysis
- Known issues and risk assessment
- Windows vs Linux comparison
- Next milestones and recommendations

**Start here if you want to:** Understand POC outcomes, review achievements, or plan next phases.

---

## Supporting Documentation

### [proxy-configuration.md](proxy-configuration.md) (2.4KB)
Detailed proxy troubleshooting for Intel corporate network. Referenced from setup guide.

### [linux-porting-proposal.md](linux-porting-proposal.md) (26KB)
Original 4-phase porting proposal with comprehensive technical analysis. Historical reference.

### [comfyui-uv-migration.md](comfyui-uv-migration.md) (5.7KB)
ComfyUI dependency migration documentation. Relevant for Phase 4 work.

---

## Archived Documentation

Historical documents from POC development (moved to `archive/` subdirectory):
- `LINUX_POC_README.md` - Superseded by LINUX_SETUP_GUIDE.md
- `linux-poc-current-status.md` - Testing notes consolidated into RESULTS
- `linux-poc-implementation-complete.md` - Pre-testing status, superseded
- `linux-poc-implementation-plan.md` - Consolidated into LINUX_IMPLEMENTATION.md
- `linux-poc-success-report.md` - Consolidated into LINUX_POC_RESULTS.md
- `verification-report.md` - Verification details merged into IMPLEMENTATION

---

## Documentation Structure

```
docs/
├── README.md (this file)
│
├── Primary Documentation
│   ├── LINUX_SETUP_GUIDE.md          [Users/Testers]
│   ├── LINUX_IMPLEMENTATION.md       [Developers]
│   └── LINUX_POC_RESULTS.md          [Stakeholders]
│
├── Supporting Documentation
│   ├── proxy-configuration.md        [Troubleshooting]
│   ├── linux-porting-proposal.md     [Planning]
│   └── comfyui-uv-migration.md       [Phase 4 reference]
│
└── archive/                           [Historical]
    ├── LINUX_POC_README.md
    ├── linux-poc-current-status.md
    ├── linux-poc-implementation-complete.md
    ├── linux-poc-implementation-plan.md
    ├── linux-poc-success-report.md
    └── verification-report.md
```

---

## Quick Reference

### Installation Commands

```bash
# Clone and setup
git clone <repo-url>
cd AI-Playground
git checkout nathsudi/linux-phase1
cd WebUI
npm install
npm run dev
```

See [LINUX_SETUP_GUIDE.md](LINUX_SETUP_GUIDE.md) for complete instructions.

---

### Verification Commands

```bash
# Check application is running
ps aux | grep electron

# Check AI Backend health
curl http://127.0.0.1:59000/healthy

# Monitor logs
tail -f /tmp/app-log.txt
```

See [LINUX_SETUP_GUIDE.md](LINUX_SETUP_GUIDE.md#verification) for details.

---

### Code Changes

6 files modified (~60 lines total):
1. `service.ts` - PIP_CONFIG_FILE fix
2. `aiBackendService.ts` - PIP_CONFIG_FILE fix
3. `comfyUIBackendService.ts` - PATH separator + PIP_CONFIG_FILE
4. `updateIntelPresets.ts` - Platform guards
5. `uv.ts` - Binary name selection
6. `hardwareDiscovery.ts` - lspci GPU detection

See [LINUX_IMPLEMENTATION.md](LINUX_IMPLEMENTATION.md#code-changes) for complete diffs.

---

## Status

**Branch:** `nathsudi/linux-phase1`  
**Status:** ✅ POC Complete - Tested and Working  
**Last Updated:** April 21, 2026

**What Works:**
- ✅ Application launches on Linux
- ✅ AI Backend running
- ✅ LlamaCPP inference working
- ✅ Intel GPU detection via lspci
- ✅ Model download and chat functional

**Known Limitations:**
- ❌ OpenVINO backend (Phase 3 work)
- ❌ ComfyUI backend (Phase 4 work)
- ⚠️ No GPU acceleration yet (Phase 2 work)

---

## Contributing

### To Test the POC
Follow [LINUX_SETUP_GUIDE.md](LINUX_SETUP_GUIDE.md)

### To Extend Linux Support
1. Read [LINUX_IMPLEMENTATION.md](LINUX_IMPLEMENTATION.md) for architecture
2. Review Phase 2-6 roadmap
3. Follow established patterns (platform guards, `process.platform` checks)
4. Test on both Linux and Windows

### To Report Issues
1. Check [Troubleshooting](LINUX_SETUP_GUIDE.md#troubleshooting) section
2. Review [Known Limitations](LINUX_SETUP_GUIDE.md#known-limitations)
3. Include logs from `/tmp/app-log.txt`
4. Specify Linux distribution and version

---

## Changelog

### v1.0 (April 21, 2026)
- ✅ Phase 1 POC complete
- ✅ Core functionality working
- ✅ Documentation consolidated (7 files → 3 primary + 3 supporting)
- ✅ Ready for Phase 2-5 implementation

---

**For questions or support, see individual document sections or check archived documentation.**
