@echo off
setlocal enabledelayedexpansion
title Plex Stack Installer

set "REPO_URL=https://github.com/Bash-Sudo/plex-stack.git"
set "DEFAULT_DIR=%USERPROFILE%\Plex-Stack"

cls
echo.
echo  =====================================================
echo   Ultimate Plex Stack  ^|  Windows Installer
echo  =====================================================
echo.
echo  This will install Docker Desktop, download Plex Stack,
echo  and open the setup wizard in your browser.
echo.
echo  Estimated time: 5-10 minutes depending on internet speed.
echo.
pause

:: ---- Require Administrator ----
net session >/dev/null 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: Please right-click this file and choose
    echo         "Run as Administrator"
    echo.
    pause
    exit /b 1
)

:: ---- Require winget ----
winget --version >/dev/null 2>&1
if errorlevel 1 (
    echo.
    echo  ERROR: winget not found.
    echo  Please update Windows (10 version 1709 or later required).
    echo.
    pause
    exit /b 1
)

:: ============================================================
::  STEP 1 - Docker Desktop
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
    echo  Docker install failed. Download manually from:
    echo  https://www.docker.com/products/docker-desktop/
    echo.
    pause
    exit /b 1
)

:: Attempt to use docker in this session
set "PATH=%PATH%;C:\Program Files\Docker\Docker\resources\bin"
docker --version >/dev/null 2>&1
if errorlevel 1 (
    echo.
    echo  =====================================================
    echo   RESTART REQUIRED
    echo  =====================================================
    echo.
    echo  Docker Desktop installed but Windows needs to restart
    echo  to finish WSL2 setup.
    echo.
    echo  After restarting, run this installer again.
    echo.
    pause
    exit /b 0
)

:: ============================================================
::  STEP 2 - Git
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
    echo  to apply the updated PATH.
    echo.
    pause
    exit /b 0
)

:: ============================================================
::  STEP 3 - Clone / locate repo
:: ============================================================
:clone_repo
echo.
echo  [3/4] Setting up Plex Stack...

:: Are we already running from inside the cloned repo?
if exist "%~dp0docker-compose.yml" (
    echo        Found existing install here.
    set "INSTALL_DIR=%~dp0"
    goto :start_stack
)

:: Ask where to install
echo.
echo  Install location (press Enter for default):
echo  Default: %DEFAULT_DIR%
echo.
set /p "INSTALL_DIR=Path: "
if "!INSTALL_DIR!"=="" set "INSTALL_DIR=%DEFAULT_DIR%"

:: Already downloaded?
if exist "!INSTALL_DIR!\docker-compose.yml" (
    echo        Existing install found at !INSTALL_DIR!
    goto :start_stack
)

echo        Downloading Plex Stack to !INSTALL_DIR!...
git clone "%REPO_URL%" "!INSTALL_DIR!"
if errorlevel 1 (
    echo.
    echo  Download failed. Check your internet connection.
    echo.
    pause
    exit /b 1
)

:: Copy prefetcharr config template for new installs
if exist "!INSTALL_DIR!\prefetcharr\config.example.toml" (
    if not exist "!INSTALL_DIR!\prefetcharr\config.toml" (
        copy /y "!INSTALL_DIR!\prefetcharr\config.example.toml" "!INSTALL_DIR!\prefetcharr\config.toml" >/dev/null
    )
)

:: ============================================================
::  STEP 4 - Start control panel
:: ============================================================
:start_stack
echo.
echo  [4/4] Starting the control panel...
cd /d "!INSTALL_DIR!"

:: Start Docker Desktop if daemon is not running
docker info >/dev/null 2>&1
if errorlevel 1 (
    echo        Starting Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    echo        Waiting for Docker to be ready (this takes 30-90 seconds)...
    set /a WAITED=0
    :wait_docker_install
    timeout /t 5 /nobreak >/dev/null
    set /a WAITED+=5
    docker info >/dev/null 2>&1
    if errorlevel 1 (
        if !WAITED! geq 180 (
            echo.
            echo  Docker is taking too long. Start Docker Desktop manually
            echo  then run Start_Plex-Stack.bat from !INSTALL_DIR!
            echo.
            pause
            exit /b 1
        )
        echo        Still waiting... ^(!WAITED! seconds^)
        goto :wait_docker_install
    )
    echo        Docker is ready.
)

echo.
echo        Building the control panel...
echo        First run downloads ~200 MB — please wait.
echo.
docker compose up -d --build plex-control
if errorlevel 1 (
    echo.
    echo  Something went wrong. Check Docker Desktop is running.
    echo.
    pause
    exit /b 1
)

echo.
echo        Waiting for control panel to start...
timeout /t 5 /nobreak >/dev/null
start http://localhost:7979

:: Create Desktop shortcut
echo        Creating Desktop shortcut...
powershell -NoProfile -Command "$ws = New-Object -COM WScript.Shell; $s = $ws.CreateShortcut([Environment]::GetFolderPath('Desktop') + '\Start Plex Stack.lnk'); $s.TargetPath = '!INSTALL_DIR!\Start_Plex-Stack.bat'; $s.WorkingDirectory = '!INSTALL_DIR!'; $s.Description = 'Start Plex Stack'; $s.Save()" >/dev/null 2>&1

echo.
echo  =====================================================
echo   Done! Setup wizard opening in your browser now.
echo  =====================================================
echo.
echo  Your Plex Stack is at: !INSTALL_DIR!
echo.
echo  In the future, use "Start Plex Stack" on your Desktop
echo  or run Start_Plex-Stack.bat to launch the stack.
echo.
pause
