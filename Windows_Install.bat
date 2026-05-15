@echo off
title Plex Stack Installer

:: Re-launch as Administrator if needed
net session >/dev/null 2>&1
if errorlevel 1 (
    echo Requesting administrator access...
    powershell -Command "Start-Process cmd -Verb RunAs -ArgumentList '/c \"%~f0\"'"
    exit /b
)

:: Run the PowerShell installer
:: If Windows_Install.ps1 is in the same folder, use it.
:: Otherwise download it from GitHub automatically.

if exist "%~dp0Windows_Install.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Install.ps1"
) else (
    echo Downloading installer...
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/Bash-Sudo/Plex-Stack/main/Windows_Install.ps1' -OutFile '$env:TEMP\PlexInstall.ps1'; & '$env:TEMP\PlexInstall.ps1'"
)
