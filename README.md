<p align="center">
  <img src="public/logo.png" width="300" alt="Plex Stack">
</p>

<h1 align="center">Plex Stack</h1>

<p align="center">
  A complete, beginner-friendly home media server — set up in minutes, runs automatically.
</p>

---

## ⚡ Windows Quick Start

<p align="center">

### [⬇ Download Windows Installer](https://raw.githubusercontent.com/Bash-Sudo/Plex-Stack/main/Windows_Install.bat)

</p>

> **Right-click → Run as Administrator** — that's it.

**Already have Docker Desktop?** The installer detects it and skips straight to downloading the stack and opening the setup wizard.

**Don't have Docker Desktop?** No problem — the installer downloads and installs it for you automatically. Windows may need to restart once for Docker's WSL2 setup, then just run the installer again.

**What happens after you run it:**
- Docker Desktop installs (if needed)
- Plex Stack downloads to your computer
- The setup wizard opens in your browser automatically
- Follow the 6-step wizard to configure everything

---

## What You Get

| Service | What It Does | Web UI |
|---|---|---|
| **Plex** | Stream your movies and TV shows anywhere | :32400 |
| **Radarr** | Automatically finds and downloads movies | :7878 |
| **Sonarr** | Automatically finds and downloads TV shows | :8989 |
| **Prowlarr** | Manages your download sources (indexers) | :9696 |
| **qBittorrent** | Downloads files — with optional VPN protection | :8080 |
| **Tautulli** | Plex statistics and watch history | :8181 |
| **Autobrr** | Grabs new torrents the moment they release | :7474 |
| **Seerr** | Let family and friends request movies and shows | :5055 |
| **Wizarr** | Invite people to your Plex server | :5690 |
| **Prefetcharr** | Pre-downloads the next episode while you watch | — |
| **Control Panel** | Browser dashboard for everything above | :7979 |

---

## Windows Installation

### Requirements
- Windows 10 (version 1709+) or Windows 11
- 8 GB RAM minimum, 16 GB recommended
- An internet connection

No Docker, Git, or technical knowledge required — the installer handles everything.

---

### Step 1 — Download & Run the Installer

**[⬇ Download Windows_Install.bat](https://raw.githubusercontent.com/Bash-Sudo/Plex-Stack/main/Windows_Install.bat)**

Right-click → **Run as Administrator**

| Situation | What happens |
|---|---|
| **Docker not installed** | Installer downloads and installs Docker Desktop automatically |
| **Docker already installed** | Installer skips Docker setup and goes straight to Plex Stack |
| **Windows restart needed** | Installer tells you — just restart and run it again |

> 💡 The installer creates a **"Start Plex Stack"** shortcut on your Desktop for future use.

---

### Step 2 — What the Installer Does

1. Installs **Docker Desktop** if not already present (the engine that runs everything)
2. Installs **Git** if not already present (for updates)
3. Downloads Plex Stack to your computer
4. Starts the control panel and opens the **setup wizard** in your browser

---

### Step 3 — Setup Wizard

The wizard opens automatically in your browser and walks you through:

| Step | What Happens |
|---|---|
| **1 — System** | Timezone and GPU auto-detected for you |
| **2 — Folders** | Choose where your media files will live |
| **3 — VPN** | Optional — protect downloads on private networks |
| **4 — Plex Claim** | Links Plex to your account (grab token right before deploying) |
| **▶ Deploy #1** | Stack starts — modal shows progress |
| **5 — API Keys** | Connect Sonarr, Radarr, and Plex together |
| **Done!** | Redirected to your live dashboard |

---

## Daily Use

Double-click **`Start_Plex-Stack.bat`** in your Plex Stack folder.

It checks if Docker is running (starts it if not), brings up any stopped containers, and opens your browser automatically.

> 💡 The installer creates a **Desktop shortcut** so you don't have to find the folder.

Bookmark **http://localhost:7979** for quick access.

---

## After First Deploy — API Keys

Once the stack is running, the wizard's Step 5 will guide you through connecting everything. Here's where to find each key:

### Sonarr API Key
1. Open [Sonarr](http://localhost:8989) → **Settings → General**
2. Copy the **API Key** at the top of the page
3. Paste it in the wizard or Settings panel

### Radarr API Key
1. Open [Radarr](http://localhost:7878) → **Settings → General**
2. Copy the **API Key** at the top of the page

### Plex Token
1. Sign in to Plex, click your **avatar → Account**
2. In the address bar, add `/:/prefs` or visit the [token guide](https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/)

### Plex Claim Token (first setup only)
Get a one-time claim token from **[plex.tv/claim](https://www.plex.tv/claim)**
> ⚠️ Expires in 4 minutes — get it right before clicking Deploy

---

## NVIDIA GPU Transcoding

If you have an NVIDIA GPU, the wizard auto-detects it and offers hardware transcoding (NVENC/NVDEC).

**Requirements:**
- Up-to-date NVIDIA drivers (Game Ready or Studio)
- Docker Desktop with WSL2 backend (default on Windows)

No extra software needed — Docker Desktop handles GPU access automatically through WSL2.

---

## Folder Structure

The installer creates this structure in your Videos folder:

```
Videos/
├── media/
│   ├── movies/     ← Radarr puts finished movies here
│   └── tv/         ← Sonarr puts finished TV shows here
└── downloads/
    ├── movies/     ← qBittorrent downloads to here first
    └── tv/
```

Radarr and Sonarr move files from `downloads/` to `media/` automatically using hardlinks — no copying, instant moves.

---

## Troubleshooting

**Control panel not loading at localhost:7979**
→ Double-click `Start_Plex-Stack.bat` — it checks and starts everything

**A container shows Stopped on the dashboard**
→ Click **Restart** on that card in the dashboard

**Want to run the setup wizard again**
→ Go to `http://localhost:7979` → click **Setup Wizard** in the nav

**Starting completely fresh**
```batch
cd C:\Plex-Stack
docker compose down --remove-orphans
docker compose up -d
```

**Updating to the latest version**
→ Click **Update All** on the dashboard, or run:
```batch
cd C:\Plex-Stack
git pull
docker compose up -d --build
```

---

## Linux / macOS

Clone the repo and edit `.env` with your settings, then:
```bash
cp prefetcharr/config.example.toml prefetcharr/config.toml
docker compose up -d --build
```
Open http://localhost:7979 for the control panel.

---

## Credits

Based on [DonMcD's Ultimate Plex Stack](https://github.com/DonMcD/ultimate-plex-stack) with a browser-based control panel, setup wizard, and Windows installer added on top.
