param()
$REPO_URL    = "https://github.com/Bash-Sudo/Plex-Stack.git"
$DEFAULT_DIR = "$env:USERPROFILE\Plex-Stack"

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process PowerShell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   Plex Stack  |  Windows Installer" -ForegroundColor Cyan
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
}
function Write-Step([int]$n,[string]$text){ Write-Host ""; Write-Host "  [$n/5] $text" -ForegroundColor Yellow; Write-Host "" }
function Write-OK([string]$t)   { Write-Host "    [OK] " -ForegroundColor Green  -NoNewline; Write-Host $t }
function Write-Info([string]$t) { Write-Host "     --> " -ForegroundColor Cyan   -NoNewline; Write-Host $t }
function Write-Warn([string]$t) { Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $t }
function Exit-Err([string]$msg) {
    Write-Host ""; Write-Host "  [ERROR] $msg" -ForegroundColor Red; Write-Host ""
    Read-Host "  Press Enter to close"; exit 1
}
function Wait-Docker([int]$Timeout=180) {
    $e=0
    while ($e -lt $Timeout) {
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep 5; $e+=5
        Write-Info "Waiting for Docker... ($e sec)"
    }
    return $false
}

Show-Header
Write-Host "  This installer sets up your Plex Stack home media server." -ForegroundColor White
Write-Host "  Order: WSL2 check, Docker Desktop, Git, download, launch." -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to begin (Ctrl+C to cancel)"

Write-Step 1 "Checking WSL2 (required for Docker Desktop)"
$wslReady=$false
try { wsl --status 2>&1 | Out-Null; if ($LASTEXITCODE -eq 0) { $wslReady=$true } } catch {}

if ($wslReady) {
    Write-OK "WSL2 is already installed and ready"
} else {
    Write-Info "Installing WSL2 -- this must be done before Docker Desktop..."
    try {
        wsl --install --no-distribution 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "failed" }
    } catch {
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>&1 | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>&1 | Out-Null
    }
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Yellow
    Write-Host "   RESTART REQUIRED" -ForegroundColor Yellow
    Write-Host "  =============================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  WSL2 was enabled. Windows must restart before" -ForegroundColor White
    Write-Host "  Docker Desktop can be installed." -ForegroundColor White
    Write-Host "  Run this installer again after restarting." -ForegroundColor Gray
    Write-Host ""
    $r=Read-Host "  Restart now? (Y/N)"
    if ($r -match "^[Yy]") { Restart-Computer -Force }
    else { Read-Host "  Press Enter to close"; exit 0 }
}

Write-Step 2 "Checking Docker Desktop"
if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-OK "Docker Desktop is already installed"
} else {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Exit-Err "winget not found. Update Windows to version 1709 or later and try again."
    }
    Write-Info "Installing Docker Desktop (this may take a few minutes)..."
    winget install -e --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements
    $env:PATH += ";C:\Program Files\Docker\Docker\resources\bin"
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "  Docker Desktop installed." -ForegroundColor White
        Write-Host "  You may need to restart and run this installer again." -ForegroundColor Gray
        Write-Host ""
        Read-Host "  Press Enter to close"; exit 0
    }
    Write-OK "Docker Desktop installed"
}

Write-Step 3 "Checking Git"
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-OK "Git is already installed"
} else {
    Write-Info "Installing Git..."
    winget install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    $env:PATH += ";C:\Program Files\Git\bin;C:\Program Files\Git\cmd"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warn "Git installed. Close and re-run this installer to refresh PATH."
        Read-Host "  Press Enter to close"; exit 0
    }
    Write-OK "Git installed"
}

Write-Step 4 "Setting up Plex Stack"
$scriptDir=Split-Path -Parent $PSCommandPath
if (Test-Path (Join-Path $scriptDir "docker-compose.yml")) {
    $INSTALL_DIR=$scriptDir; Write-OK "Using existing install at: $INSTALL_DIR"
} elseif (Test-Path (Join-Path $DEFAULT_DIR "docker-compose.yml")) {
    $INSTALL_DIR=$DEFAULT_DIR; Write-OK "Found existing install at: $INSTALL_DIR"
} else {
    Write-Host "  Where should Plex Stack be installed?" -ForegroundColor White
    Write-Host "  Default: $DEFAULT_DIR" -ForegroundColor Gray
    Write-Host ""
    $ui=Read-Host "  Press Enter for default, or type a path"
    $INSTALL_DIR=if ($ui.Trim() -eq "") { $DEFAULT_DIR } else { $ui.Trim() }
    Write-Info "Downloading Plex Stack to $INSTALL_DIR..."
    git clone $REPO_URL "$INSTALL_DIR"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $INSTALL_DIR "docker-compose.yml"))) {
        Exit-Err "Download failed. Check your internet connection."
    }
    Write-OK "Plex Stack downloaded"
}
Set-Location $INSTALL_DIR

Write-Step 5 "Starting Docker and the control panel"
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    $dexe="C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dexe) { Write-Info "Starting Docker Desktop..."; Start-Process $dexe }
    else { Exit-Err "Docker Desktop not found. Start it manually then re-run this installer." }
    Write-Info "Waiting for Docker (30-90 sec on first launch)..."
    if (-not (Wait-Docker)) { Exit-Err "Docker took too long. Start Docker Desktop manually, then run Start_Plex-Stack.bat" }
}
Write-OK "Docker is ready"
Write-Host ""
Write-Info "Building the control panel (first run ~200 MB download)..."
Write-Host ""
docker compose up -d --build plex-control
if ($LASTEXITCODE -ne 0) { Exit-Err "Control panel failed to start. Check Docker Desktop is running." }
Write-Host ""
Write-OK "Control panel is running"

try {
    $ws=New-Object -ComObject WScript.Shell
    $lnk=$ws.CreateShortcut("$env:USERPROFILE\Desktop\Start Plex Stack.lnk")
    $lnk.TargetPath=Join-Path $INSTALL_DIR "Start_Plex-Stack.bat"
    $lnk.WorkingDirectory=$INSTALL_DIR
    $lnk.Description="Start the Plex Stack media server"
    $lnk.Save()
    Write-OK "Desktop shortcut created"
} catch { Write-Warn "Desktop shortcut could not be created (non-critical)" }

Write-Info "Opening setup wizard in your browser..."
Start-Sleep 5
Start-Process "http://localhost:7979"

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   Installation complete!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  The setup wizard is now open in your browser." -ForegroundColor White
Write-Host "  Follow the steps to configure your media server." -ForegroundColor White
Write-Host ""
Write-Host "  Installed to : $INSTALL_DIR" -ForegroundColor Gray
Write-Host "  Control panel: http://localhost:7979" -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to close"
