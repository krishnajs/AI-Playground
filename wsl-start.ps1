# Intel AI Playground - WSL2 Launch Script
# Usage: .\wsl-start.ps1
# Runs the app inside WSL2 (Ubuntu) for Linux testing.
# Requires: WSL2 with Ubuntu installed and wsl-setup.sh already run.

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ── WSL check ────────────────────────────────────────────────────────────
if (-not (Get-Command wsl -ErrorAction SilentlyContinue)) {
    Write-Error "WSL not found. Run: wsl --install -d Ubuntu-24.04 (then reboot)"
    exit 1
}

$distros = wsl --list --quiet 2>$null
if (-not $distros) {
    Write-Host ""
    Write-Host "ERROR: No WSL distribution installed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Steps to fix:" -ForegroundColor Yellow
    Write-Host "  1. Reboot your PC (WSL kernel was just installed)"
    Write-Host "  2. After reboot, open PowerShell as Admin and run:"
    Write-Host "       wsl --install -d Ubuntu-24.04"
    Write-Host "  3. Set a username and password when prompted"
    Write-Host "  4. Then run this script again"
    exit 1
}

# Convert Windows path to WSL path (C:\Users\foo -> /mnt/c/Users/foo)
# Compatible with PowerShell 5.1 — no script-block replacement needed
$NormalizedPath = $RepoRoot -replace '\\', '/'
$DriveLetter = $NormalizedPath.Substring(0, 1).ToLower()
$WslPath = '/mnt/' + $DriveLetter + $NormalizedPath.Substring(2)

Write-Host ""
Write-Host "  Launching AI Playground inside WSL2..." -ForegroundColor Cyan
Write-Host "  Repo: $WslPath" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  UI will be at: http://localhost:25413" -ForegroundColor Green
Write-Host "  Press Ctrl+C in the WSL window to stop all services." -ForegroundColor Yellow
Write-Host ""

# Run setup if node_modules not present, then start
# Use --cd to safely handle paths with spaces; pass the path as an env var inside bash
wsl --cd "$WslPath" bash -c '
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
  if ! command -v node &>/dev/null; then
    echo "ERROR: Node.js not found in WSL. Run: bash scripts/wsl-setup.sh from inside WSL first."
    exit 1
  fi
  bash start-ui.sh
'
