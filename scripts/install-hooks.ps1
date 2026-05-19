# Configure git to use the repo's .githooks/ directory so the pre-commit hook
# (which runs gitleaks against staged changes) is active.
#
# Run once per clone:   .\scripts\install-hooks.ps1
#
# Why: git hooks are not committed by default — they live in .git/hooks/ which
# is per-clone. The .githooks/ directory IS committed, and pointing core.hooksPath
# at it lets every clone share the same hooks via a single git config flip.

$ErrorActionPreference = "Stop"

# Verify gitleaks is installed
$gl = Get-Command gitleaks -ErrorAction SilentlyContinue
if (-not $gl) {
    $wingetPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe\gitleaks.exe"
    if (-not (Test-Path $wingetPath)) {
        Write-Host "Installing gitleaks via winget..." -ForegroundColor Yellow
        winget install --id gitleaks.gitleaks --silent --accept-source-agreements --accept-package-agreements
    } else {
        Write-Host "gitleaks found at $wingetPath (PATH will pick it up after shell restart)" -ForegroundColor Green
    }
} else {
    Write-Host "gitleaks already on PATH: $($gl.Source)" -ForegroundColor Green
}

# Point git at our shared hooks directory
git config core.hooksPath .githooks
Write-Host "core.hooksPath set to .githooks" -ForegroundColor Green

# Verify hook is recognized
$hookPath = Join-Path (Resolve-Path .) ".githooks/pre-commit"
if (Test-Path $hookPath) {
    Write-Host "Pre-commit hook active: $hookPath" -ForegroundColor Green
} else {
    Write-Host "WARNING: .githooks/pre-commit not found in this repo" -ForegroundColor Red
}

Write-Host ""
Write-Host "Setup complete. Next push must pass gitleaks scanning of staged changes."
Write-Host "Bypass in emergency (NEVER for prod secrets):  git commit --no-verify"
