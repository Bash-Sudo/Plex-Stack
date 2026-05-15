@echo off
setlocal enabledelayedexpansion
title Plex Stack
cd /d "%~dp0"

echo.
echo  Starting Plex Stack...
echo.

:: ---- Check Docker Desktop is running ----
docker info >/dev/null 2>&1
if errorlevel 1 (
    echo  Docker is not running. Starting Docker Desktop...
    start "" "C:\Program Files\Docker\Docker\Docker Desktop.exe"

    echo  Waiting for Docker to be ready...
    set /a WAITED=0
    :wait_docker
    timeout /t 4 /nobreak >/dev/null
    set /a WAITED+=4
    docker info >/dev/null 2>&1
    if errorlevel 1 (
        if !WAITED! geq 120 (
            echo.
            echo  ERROR: Docker took too long to start.
            echo  Please open Docker Desktop manually and try again.
            echo.
            pause
            exit /b 1
        )
        echo  Still waiting... ^(!WAITED!s^)
        goto :wait_docker
    )
    echo  Docker is ready.
    echo.
)

:: ---- Check if plex-control container is running ----
for /f "delims=" %%s in ('docker ps --filter "name=plex-control" --format "{{.Names}}" 2^>nul') do set "RUNNING=%%s"

if /i "!RUNNING!"=="plex-control" (
    echo  Stack is already running.
) else (
    echo  Starting containers...
    docker compose up -d
    timeout /t 3 /nobreak >/dev/null
)

echo  Opening control panel...
start http://localhost:7979
echo.
