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

function Write-Step([int]$n, [string]$text) {
    Write-Host ""
    Write-Host "  [$n/4] $text" -ForegroundColor Yellow
    Write-Host ""
}

function Write-OK([string]$text)   { Write-Host "    [OK] " -ForegroundColor Green  -NoNewline; Write-Host $text }
function Write-Info([string]$text) { Write-Host "     --> " -ForegroundColor Cyan   -NoNewline; Write-Host $text }
function Write-Warn([string]$text) { Write-Host "  [WARN] " -ForegroundColor Yellow -NoNewline; Write-Host $text }

function Exit-WithError([string]$msg) {
    Write-Host ""
    Write-Host "  [ERROR] $msg" -ForegroundColor Red
    Write-Host ""
    Read-Host "  Press Enter to close"
    exit 1
}

function Wait-ForDocker([int]$Timeout = 180) {
    $elapsed = 0
    while ($elapsed -lt $Timeout) {
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { return $true }
        Start-Sleep 5
        $elapsed += 5
        Write-Info "Still waiting for Docker... ($elapsed sec)"
    }
    return $false
}

Show-Header
Write-Host "  This installer sets up your Plex Stack home media server." -ForegroundColor White
Write-Host "  It will install Docker Desktop and Git if not already installed." -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to begin (or Ctrl+C to cancel)"

Write-Step 1 "Checking Docker Desktop"
$hasDocker = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)

if ($hasDocker) {
    Write-OK "Docker Desktop is already installed"
} else {
    Write-Info "Installing Docker Desktop (this may take a few minutes)..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Exit-WithError "winget not found. Update Windows to version 1709 or later and try again."
    }
    winget install -e --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements
    $env:PATH += ";C:\Program Files\Docker\Docker\resources\bin"
    $hasDocker = $null -ne (Get-Command docker -ErrorAction SilentlyContinue)
    if (-not $hasDocker) {
        Write-Host ""
        Write-Host "  =============================================" -ForegroundColor Yellow
        Write-Host "   RESTART REQUIRED" -ForegroundColor Yellow
        Write-Host "  =============================================" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Docker Desktop installed. Windows needs to restart" -ForegroundColor White
        Write-Host "  to finish WSL2 setup. Run this installer again after." -ForegroundColor White
        Write-Host ""
        Read-Host "  Press Enter to close"
        exit 0
    }
    Write-OK "Docker Desktop installed"
}

Write-Step 2 "Checking Git"
if (Get-Command git -ErrorAction SilentlyContinue) {
    Write-OK "Git is already installed"
} else {
    Write-Info "Installing Git..."
    winget install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements
    $env:PATH += ";C:\Program Files\Git\bin;C:\Program Files\Git\cmd"
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warn "Git installed. Close and run this installer again to refresh PATH."
        Read-Host "  Press Enter to close"
        exit 0
    }
    Write-OK "Git installed"
}

Write-Step 3 "Setting up Plex Stack"
$scriptDir = Split-Path -Parent $PSCommandPath
if (Test-Path (Join-Path $scriptDir "docker-compose.yml")) {
    $INSTALL_DIR = $scriptDir
    Write-OK "Using existing install at: $INSTALL_DIR"
} elseif (Test-Path (Join-Path $DEFAULT_DIR "docker-compose.yml")) {
    $INSTALL_DIR = $DEFAULT_DIR
    Write-OK "Found existing install at: $INSTALL_DIR"
} else {
    Write-Host "  Where should Plex Stack be installed?" -ForegroundColor White
    Write-Host "  Default: $DEFAULT_DIR" -ForegroundColor Gray
    Write-Host ""
    $userInput = Read-Host "  Press Enter for default, or type a custom path"
    $INSTALL_DIR = if ($userInput.Trim() -eq "") { $DEFAULT_DIR } else { $userInput.Trim() }
    Write-Info "Downloading Plex Stack to $INSTALL_DIR..."
    git clone $REPO_URL "$INSTALL_DIR"
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $INSTALL_DIR "docker-compose.yml"))) {
        Exit-WithError "Download failed. Check your internet connection and try again."
    }
    $example = Join-Path $INSTALL_DIR "prefetcharr\config.example.toml"
    $cfgTarget  = Join-Path $INSTALL_DIR "prefetcharr\config.toml"
    if ((Test-Path $example) -and -not (Test-Path $cfgTarget)) {
        Copy-Item $example $cfgTarget
    }
    Write-OK "Plex Stack downloaded to $INSTALL_DIR"
}

Set-Location $INSTALL_DIR

Write-Step 4 "Starting Docker and the control panel"
docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Info "Starting Docker Desktop..."
    $dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) { Start-Process $dockerExe }
    else { Exit-WithError "Docker Desktop not found. Please start it manually and try again." }
    Write-Info "Waiting for Docker to be ready (30-90 seconds on first launch)..."
    if (-not (Wait-ForDocker)) {
        Exit-WithError "Docker took too long to start. Launch Docker Desktop manually then run Start_Plex-Stack.bat"
    }
}
Write-OK "Docker is ready"
Write-Host ""
Write-Info "Building the control panel (first run downloads ~200 MB, please wait)..."
Write-Host ""
docker compose up -d --build plex-control
if ($LASTEXITCODE -ne 0) {
    Exit-WithError "Control panel failed to start. Check Docker Desktop is running and try again."
}
Write-Host ""
Write-OK "Control panel is running"

try {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut("$env:USERPROFILE\Desktop\Start Plex Stack.lnk")
    $lnk.TargetPath       = Join-Path $INSTALL_DIR "Start_Plex-Stack.bat"
    $lnk.WorkingDirectory = $INSTALL_DIR
    $lnk.Description      = "Start the Plex Stack media server"
    $lnk.Save()
    Write-OK "Desktop shortcut created"
} catch {
    Write-Warn "Desktop shortcut could not be created"
}

Write-Info "Opening setup wizard in your browser..."
Start-Sleep 5
Start-Process "http://localhost:7979"

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   Installation complete!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  The setup wizard should now be open in your browser." -ForegroundColor White
Write-Host "  Follow the steps to configure your media server." -ForegroundColor White
Write-Host ""
Write-Host "  Installed to : $INSTALL_DIR" -ForegroundColor Gray
Write-Host "  Control panel: http://localhost:7979" -ForegroundColor Gray
Write-Host ""
Write-Host "  Use the 'Start Plex Stack' shortcut on your Desktop in future." -ForegroundColor Gray
Write-Host ""
Read-Host "  Press Enter to close"
