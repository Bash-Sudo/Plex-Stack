'use strict';
const http   = require('http');
const https  = require('https');
const fs     = require('fs');
const path   = require('path');
const os     = require('os');
const { exec } = require('child_process');
const { parseEnv, buildEnvContent } = require('./utils');
const docker = require('./docker');

const PORT       = 7979;
const CWD        = process.cwd();
const ENV_FILE   = path.join(CWD, '.env');
const PUBLIC_DIR = path.join(__dirname, '..', 'public');

// ── Helpers ───────────────────────────────────────────────────────────────────

function getBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks).toString()));
    req.on('error', reject);
  });
}

function serveFile(res, filePath, type) {
  try {
    const isHtml = type.includes('html');
    res.writeHead(200, {
      'Content-Type': type,
      // Never cache HTML so wizard/dashboard changes always load fresh
      ...(isHtml ? { 'Cache-Control': 'no-store' } : { 'Cache-Control': 'public, max-age=3600' }),
    });
    res.end(fs.readFileSync(filePath));
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}

function json(res, code, data) {
  res.writeHead(code, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function sse(res) {
  res.writeHead(200, {
    'Content-Type':  'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection':    'keep-alive',
  });
  return (event, data) => res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

// ── Status SSE broadcast ──────────────────────────────────────────────────────

const statusClients = new Set();
let   statusCache   = [];

async function refreshStatus() {
  try { statusCache = await docker.getFullStatus(); } catch { statusCache = []; }
  if (statusClients.size === 0) return;
  const msg = `event: status\ndata: ${JSON.stringify(statusCache)}\n\n`;
  for (const res of statusClients) { try { res.write(msg); } catch {} }
}

// ── System info ───────────────────────────────────────────────────────────────

function getLocalIp() {
  // host.docker.internal resolves to the real host LAN IP on Docker Desktop (Win/Mac).
  // We do a synchronous DNS lookup via /etc/hosts which Docker Desktop populates.
  try {
    const hosts = fs.readFileSync('/etc/hosts', 'utf8');
    for (const line of hosts.split('\n')) {
      const parts = line.trim().split(/\s+/);
      if (parts.includes('host.docker.internal') && parts[0] && parts[0] !== '127.0.0.1') {
        return parts[0];
      }
    }
  } catch {}
  // Fallback: return first non-internal IPv4 (works when running locally on host)
  for (const ifaces of Object.values(os.networkInterfaces())) {
    for (const iface of ifaces) {
      if (iface.family === 'IPv4' && !iface.internal) return iface.address;
    }
  }
  return null;
}

function getWanIp() {
  return new Promise(resolve => {
    https.get('https://api.ipify.org?format=json', res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => { try { resolve(JSON.parse(d).ip); } catch { resolve(null); } });
    }).on('error', () => resolve(null));
  });
}

function getDisk(mountPath) {
  return new Promise(resolve => {
    exec(`df -B1 "${mountPath}" 2>/dev/null`, (err, out) => {
      if (err || !out) return resolve(null);
      const parts = out.trim().split('\n')[1]?.split(/\s+/);
      if (!parts || parts.length < 4) return resolve(null);
      resolve({ total: +parts[1] || 0, used: +parts[2] || 0, free: +parts[3] || 0 });
    });
  });
}

// ── Request router ────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const { pathname } = url;

  // Static files from public/
  if (req.method === 'GET' && !pathname.startsWith('/api/')) {
    const MIME = {
      '.html': 'text/html; charset=utf-8',
      '.png':  'image/png',
      '.jpg':  'image/jpeg',
      '.ico':  'image/x-icon',
      '.svg':  'image/svg+xml',
      '.css':  'text/css',
      '.js':   'application/javascript',
    };
    const target = pathname === '/'
      ? path.join(PUBLIC_DIR, 'index.html')
      : path.join(PUBLIC_DIR, pathname);
    const ext  = path.extname(target).toLowerCase();
    const mime = MIME[ext] || 'application/octet-stream';
    return serveFile(res, target, mime);
  }

  // Platform defaults
  if (req.method === 'GET' && pathname === '/api/platform') {
    // Run detections in parallel
    const [info, winUser] = await Promise.all([
      docker.getDockerInfo(),
      docker.getWindowsUsername(),
    ]);

    // GPU: check if nvidia runtime is registered with the Docker daemon
    const gpuDetected = (info.Runtimes && 'nvidia' in info.Runtimes) ? 'nvidia' : 'none';

    // Username: prefer the Windows host user parsed from mount paths
    const home     = os.homedir().replace(/\\/g, '/');
    const username = winUser || os.userInfo().username;

    let defaultBase, defaultMedia;
    // We're always inside a Linux container, but we know if Docker Desktop is on Windows
    // by checking if we successfully parsed a Windows username from mounts
    if (winUser) {
      defaultBase  = `C:/Users/${winUser}/AppData/Local/Plex-Stack`;
      defaultMedia = `C:/Users/${winUser}/Videos`;
    } else if (process.platform === 'darwin') {
      defaultBase  = `${home}/Library/Application Support/Plex-Stack`;
      defaultMedia = `${home}/Movies`;
    } else {
      defaultBase  = `${home}/docker`;
      defaultMedia = '/data';
    }

    return json(res, 200, { platform: process.platform, username, defaultBase, defaultMedia, gpuDetected });
  }

  // Config read/write
  if (req.method === 'GET' && pathname === '/api/config') {
    return json(res, 200, parseEnv(ENV_FILE));
  }

  if (req.method === 'POST' && pathname === '/api/save') {
    try {
      const values = JSON.parse(await getBody(req));
      fs.writeFileSync(ENV_FILE, buildEnvContent(values), 'utf8');
      writePrefetcharrConfig(values);
      return json(res, 200, { ok: true });
    } catch (e) {
      return json(res, 500, { ok: false, error: e.message });
    }
  }

  // System info (IPs + disk)
  if (req.method === 'GET' && pathname === '/api/system') {
    const cfg = parseEnv(ENV_FILE);
    const [wanIp, mediaDisk, configDisk] = await Promise.all([
      getWanIp(),
      getDisk('/mnt/media'),
      getDisk('/mnt/config'),
    ]);
    // Only use SERVER_IP from .env — never show Docker Desktop internal IPs
    // (e.g. 192.168.65.x) which confuse users. Null = not configured yet.
    const localIp = cfg.SERVER_IP || null;
    return json(res, 200, { localIp, wanIp, mediaDisk, configDisk, localIpIsSet: !!cfg.SERVER_IP });
  }

  // Container status SSE stream
  if (req.method === 'GET' && pathname === '/api/stream/status') {
    res.writeHead(200, {
      'Content-Type':  'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection':    'keep-alive',
    });
    statusClients.add(res);
    if (statusCache.length) {
      res.write(`event: status\ndata: ${JSON.stringify(statusCache)}\n\n`);
    }
    req.on('close', () => statusClients.delete(res));
    return;
  }

  // Compose operation SSE stream
  // ?action = deploy | update | phase1 | phase2
  if (req.method === 'GET' && pathname === '/api/stream/compose') {
    const action = url.searchParams.get('action') || 'deploy';
    const send   = sse(res);

    // Heartbeat so browser doesn't time out during long operations
    const hb = setInterval(() => { try { res.write(': ping\n\n'); } catch {} }, 15000);

    const finish = (code) => {
      clearInterval(hb);
      send('done', { code });
      res.end();
    };

    try {
      if (action === 'phase1') {
        const code = await docker.runPhase(1, l => send('log', { line: l }));
        return finish(code);
      }
      if (action === 'phase2') {
        const code = await docker.runPhase(2, l => send('log', { line: l }));
        return finish(code);
      }
      // restart: restart all services EXCEPT plex-control so we don't kill ourselves
      if (action === 'restart') {
        send('log', { line: 'Restarting services (plex-control stays running)…' });
        const code = await docker.runCompose(['restart', ...docker.ALL_SERVICES], l => send('log', { line: l }));
        return finish(code);
      }
      if (action === 'update') {
        send('log', { line: 'Pulling latest images…' });
        const pullCode = await docker.runCompose(['pull', ...docker.ALL_SERVICES], l => send('log', { line: l }));
        if (pullCode !== 0) return finish(pullCode);
        send('log', { line: '' });
        send('log', { line: 'Recreating containers…' });
        const upCode = await docker.runCompose(['up', '-d', '--remove-orphans', ...docker.ALL_SERVICES], l => send('log', { line: l }));
        return finish(upCode);
      }
      // default: full deploy (wizard initial setup only)
      const upCode = await docker.runCompose(
        ['up', '-d', '--remove-orphans'],
        l => send('log', { line: l }),
      );
      finish(upCode);
    } catch (e) {
      send('log', { line: `Error: ${e.message}` });
      finish(1);
    }
  }

  // Restart individual container
  const restartMatch = pathname.match(/^\/api\/containers\/([^/]+)\/restart$/);
  if (req.method === 'POST' && restartMatch) {
    try {
      await docker.restartContainer(restartMatch[1]);
      return json(res, 200, { ok: true });
    } catch (e) {
      return json(res, 500, { ok: false, error: e.message });
    }
  }

  // Download start.bat (GPU-aware)
  if (req.method === 'GET' && pathname === '/api/download/start.bat') {
    const cfg = parseEnv(ENV_FILE);
    const cmd = cfg.GPU_PROVIDER === 'nvidia'
      ? 'docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up -d'
      : 'docker compose up -d';
    const bat = [
      '@echo off',
      'echo Starting Ultimate Plex Stack...',
      cmd,
      'timeout /t 3 /nobreak >nul',
      'start http://localhost:7979',
      '',
    ].join('\r\n');
    res.writeHead(200, {
      'Content-Type':        'application/octet-stream',
      'Content-Disposition': 'attachment; filename="start.bat"',
    });
    return res.end(bat);
  }

  // Download start.sh (GPU-aware)
  if (req.method === 'GET' && pathname === '/api/download/start.sh') {
    const cfg = parseEnv(ENV_FILE);
    const cmd = cfg.GPU_PROVIDER === 'nvidia'
      ? 'docker compose -f docker-compose.yml -f docker-compose.nvidia.yml up -d'
      : 'docker compose up -d';
    const sh = [
      '#!/bin/bash',
      cmd,
      'sleep 3',
      'xdg-open http://localhost:7979 2>/dev/null || open http://localhost:7979 2>/dev/null',
      '',
    ].join('\n');
    res.writeHead(200, {
      'Content-Type':        'application/octet-stream',
      'Content-Disposition': 'attachment; filename="start.sh"',
    });
    return res.end(sh);
  }

  // Folder browser — lists directories for the path picker
  // C:/ is mounted read-only at /mnt/windows inside the container
  if (req.method === 'GET' && pathname === '/api/browse') {
    const reqPath = (url.searchParams.get('path') || 'C:/').replace(/\\/g, '/');
    try {
      const winToHost = (p) => {
        const m = p.match(/^([A-Za-z]):\/?(.*)$/);
        if (!m) throw new Error('Only Windows drive paths (C:/, D:/, …) are supported');
        const drive = m[1].toLowerCase();
        const rest  = m[2] ? '/' + m[2] : '';
        // C:/ is mounted at /mnt/windows — other drives not yet supported
        if (drive === 'c') return `/mnt/windows${rest}`;
        throw new Error(`Drive ${drive.toUpperCase()}: is not mounted. Add it to docker-compose.yml to browse it.`);
      };

      const hostPath = winToHost(reqPath);
      const entries  = fs.readdirSync(hostPath, { withFileTypes: true });
      const dirs = entries
        .filter(e => e.isDirectory() && !e.name.startsWith('.'))
        .map(e => e.name)
        .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));

      // Parent path
      const norm   = reqPath.replace(/\/$/, '');
      const parts  = norm.split('/');
      const parent = parts.length > 1
        ? (parts.slice(0, -1).join('/') || parts[0] + '/')
        : null;

      return json(res, 200, { path: reqPath, dirs, parent });
    } catch (e) {
      return json(res, 500, { error: e.message, path: reqPath });
    }
  }

  res.writeHead(404);
  res.end('Not found');
});

// ── Start ─────────────────────────────────────────────────────────────────────

function ensurePrefetcharrConfig() {
  // Docker bind-mounts need a FILE to exist before container start.
  // If config.toml is missing, Docker creates it as a directory — breaking prefetcharr.
  // Copy the example on startup to prevent this.
  const config  = path.join(CWD, 'prefetcharr', 'config.toml');
  const example = path.join(CWD, 'prefetcharr', 'config.example.toml');
  try {
    const stat = fs.existsSync(config) && fs.statSync(config);
    if (!stat || stat.isDirectory()) {
      if (stat && stat.isDirectory()) fs.rmdirSync(config);  // remove wrongly-created dir
      if (fs.existsSync(example)) {
        fs.copyFileSync(example, config);
        console.log('  Created prefetcharr/config.toml from example');
      }
    }
  } catch (e) { console.warn('  Could not ensure prefetcharr config:', e.message); }
}

function start() {
  ensurePrefetcharrConfig();
  refreshStatus();
  setInterval(refreshStatus, 10_000);

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`\n  Plex Stack Control Panel`);
    console.log(`  http://localhost:${PORT}\n`);
  });

  server.on('error', e => {
    if (e.code === 'EADDRINUSE') console.error(`\nPort ${PORT} already in use.\n`);
    else console.error(e.message);
    process.exit(1);
  });
}

// ── Prefetcharr config.toml writer ───────────────────────────────────────────

function writePrefetcharrConfig(values) {
  const configPath = path.join(CWD, 'prefetcharr', 'config.toml');
  try {
    if (!fs.existsSync(path.dirname(configPath))) return;
    const plexToken = values.PLEX_TOKEN || '';
    const sonarrKey = values.SONARR_KEY || '';
    const content = [
      '# Prefetcharr — auto-written by Plex Stack Control Panel',
      '# Edit via Settings in the control panel, then restart prefetcharr.',
      '',
      'interval            = 900',
      'log_dir             = "/log"',
      'log_level           = "Info"',
      'prefetch_num        = 2',
      'request_seasons     = true',
      'append_to_queue     = false',
      'connection_retries  = 6',
      '',
      '[media_server]',
      'type    = "Plex"',
      'url     = "http://plex:32400"',
      `api_key = "${plexToken}"`,
      '',
      '# users     = [ "Jason" ]',
      '# libraries = [ "TV Shows" ]',
      '',
      '[sonarr]',
      'url     = "http://sonarr:8989"',
      `api_key = "${sonarrKey}"`,
      '',
      '# exclude_tag = "no_prefetch"',
    ].join('\n') + '\n';
    fs.writeFileSync(configPath, content, 'utf8');
  } catch {}
}

module.exports = { start };
