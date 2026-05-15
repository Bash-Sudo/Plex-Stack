@echo off
setlocal enabledelayedexpansion
title Plex Stack Installer

:: ============================================================
::  UPDATE THIS LINE with your actual GitHub repo URL
::  before sharing this file with others!
:: ============================================================
set "REPO_URL=https://github.com/YOUR_USERNAME/plex-stack.git"
set "DEFAULT_DIR=%USERPROFILE%\Plex-Stack"

cls
echo.
echo  =====================================================
echo   Ultimate Plex Stack ^| Windows Installer
echo  =====================================================
echo.
echo  This will install Docker Desktop, download Plex Stack,
echo  and open the setup wizard in your browser.
echo.
echo  Estimated time: 5-10 minutes (depending on internet speed)
echo.
pause

:: ---- Admin check ----
net session >/dev/null 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: Please right-click this file and choose
    echo         "Run as Administrator"
    echo.
    pause
    exit /b 1
)

:: ---- Check winget (required for installs) ----
winget --version >/dev/null 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: This installer requires Windows 10 version 1709 or later.
    echo  Please update Windows and try again.
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  STEP 1 — Docker Desktop
:: ============================================================
echo.
echo  [1/4] Checking Docker Desktop...

docker --version >/dev/null 2>&1
if not errorlevel 1 (
    echo        Already installed. Skipping.
    goto :install_git
)

echo        Installing Docker Desktop (this may take a few minutes)...
winget install -e --id Docker.DockerDesktop --silent --accept-package-agreements --accept-source-agreements
if errorlevel 1 (
    echo.
    echo  Docker Desktop install failed. Please download it manually:
    echo  https://www.docker.com/products/docker-desktop/
    echo.
    pause
    exit /b 1
)

:: Refresh PATH so docker is available in this session
set "PATH=%PATH%;C:\Program Files\Docker\Docker\resources\bin"

docker --version >/dev/null 2>&1
if errorlevel 1 (
    echo.
    echo  =====================================================
    echo   RESTART REQUIRED
    echo  =====================================================
    echo.
    echo  Docker Desktop was installed but your computer needs
    echo  to restart to finish setup (required for WSL2).
    echo.
    echo  After restarting, run this installer again.
    echo.
    pause
    exit /b 0
)

:: ============================================================
::  STEP 2 — Git
:: ============================================================
:install_git
echo.
echo  [2/4] Checking Git...

git --version >/dev/null 2>&1
if not errorlevel 1 (
    echo        Already installed. Skipping.
    goto :clone_repo
)

echo        Installing Git...
winget install -e --id Git.Git --silent --accept-package-agreements --accept-source-agreements
set "PATH=%PATH%;C:\Program Files\Git\bin;C:\Program Files\Git\cmd"

git --version >/dev/null 2>&1
if errorlevel 1 (
    echo.
    echo  Git installed. Please close and re-run this installer
    echo  to refresh the PATH.
    echo.
    pause
    exit /b 0
)

:: ============================================================
::  STEP 3 — Clone / locate the repo
:: ============================================================
:clone_repo
echo.
echo  [3/4] Setting up Plex Stack...

:: Already inside a cloned copy?
if exist "%~dp0docker-compose.yml" (
    echo        Found existing install at: %~dp0
    set "INSTALL_DIR=%~dp0"
    goto :start_stack
)

:: Ask where to install
echo.
echo  Where would you like to install Plex Stack?
echo  Default: %DEFAULT_DIR%
echo.
set /p "INSTALL_DIR=Press Enter to use default, or type a path: "
if "!INSTALL_DIR!"=="" set "INSTALL_DIR=%DEFAULT_DIR%"

if exist "!INSTALL_DIR!\docker-compose.yml" (
    echo        Existing install found at !INSTALL_DIR!
    goto :start_stack
)

echo        Downloading Plex Stack to !INSTALL_DIR!...
git clone "%REPO_URL%" "!INSTALL_DIR!"
if errorlevel 1 (
    echo.
    echo  Download failed. Check your internet connection and try again.
    echo.
    pause
    exit /b 1
)

:: Copy prefetcharr config template
if exist "!INSTALL_DIR!\prefetcharr\config.example.toml" (
    if not exist "!INSTALL_DIR!\prefetcharr\config.toml" (
        copy "!INSTALL_DIR!\prefetcharr\config.example.toml" "!INSTALL_DIR!\prefetcharr\config.toml" >/dev/null
    )
)

:: ============================================================
::  STEP 4 — Start the stack
:: ============================================================
:start_stack
echo.
echo  [4/4] Starting Docker Desktop and Plex Stack...
cd /d "!INSTALL_DIR!"

:: Start Docker Desktop if not running
docker info >/dev/null 2>&1
if errorlevel 1 (
    echo        Starting Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    echo        Waiting for Docker to be ready (30-90 seconds)...
    set /a WAITED=0
    :wait_docker_install
    timeout /t 5 /nobreak >/dev/null
    set /a WAITED+=5
    docker info >/dev/null 2>&1
    if errorlevel 1 (
        if !WAITED! geq 180 (
            echo.
            echo  Docker took too long to start.
            echo  Please start Docker Desktop manually, then run Start_Plex-Stack.bat
            echo.
            pause
            exit /b 1
        )
        echo        Still waiting... ^(!WAITED!s^)
        goto :wait_docker_install
    )
)

echo        Docker is ready. Building and starting containers...
docker compose up -d --build
if errorlevel 1 (
    echo.
    echo  Something went wrong starting the stack.
    echo  Check Docker Desktop is running and try again.
    echo.
    pause
    exit /b 1
)

echo.
echo        Waiting for the control panel to start...
timeout /t 5 /nobreak >/dev/null
start http://localhost:7979

:: Create Desktop shortcut for Start_Plex-Stack.bat
echo.
echo  Creating Desktop shortcut...
powershell -NoProfile -Command ^
  "$ws = New-Object -COM WScript.Shell; $s = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\Start Plex Stack.lnk'); $s.TargetPath = '!INSTALL_DIR!\Start_Plex-Stack.bat'; $s.WorkingDirectory = '!INSTALL_DIR!'; $s.IconLocation = 'C:\Program Files\Docker\Docker\Docker Desktop.exe,0'; $s.Save()" >/dev/null 2>&1

echo.
echo  =====================================================
echo   Installation complete!
echo  =====================================================
echo.
echo  Your browser should now show the setup wizard.
echo  Follow the steps to configure your media server.
echo.
echo  Installed to: !INSTALL_DIR!
echo.
echo  To start Plex Stack in the future:
echo    Double-click "Start Plex Stack" on your Desktop
echo    OR run Start_Plex-Stack.bat in !INSTALL_DIR!
echo.
pause
