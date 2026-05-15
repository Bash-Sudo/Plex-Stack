'use strict';
const http  = require('http');
const path  = require('path');
const { spawn } = require('child_process');
const { parseEnv } = require('./utils');

const SOCKET       = '/var/run/docker.sock';
const API          = 'v1.43';
const CWD          = process.cwd();
const COMPOSE_FILE = path.join(CWD, 'docker-compose.yml');
const NVIDIA_FILE  = path.join(CWD, 'docker-compose.nvidia.yml');
const ENV_FILE     = path.join(CWD, '.env');

// ── Low-level Docker API ──────────────────────────────────────────────────────

function dockerReq(method, apiPath, body) {
  return new Promise((resolve, reject) => {
    const opts = {
      socketPath: SOCKET,
      path: `/${API}${apiPath}`,
      method,
      headers: body ? { 'Content-Type': 'application/json' } : {},
    };
    const req = http.request(opts, (res) => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        const raw = Buffer.concat(chunks).toString();
        try { resolve(JSON.parse(raw)); } catch { resolve(raw); }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// ── Container status ──────────────────────────────────────────────────────────

const PROJECT_FILTER = encodeURIComponent(JSON.stringify({ label: ['com.docker.compose.project=plex-stack'] }));

async function getContainers() {
  try {
    const list = await dockerReq('GET', `/containers/json?all=1&filters=${PROJECT_FILTER}`);
    return Array.isArray(list) ? list : [];
  } catch { return []; }
}

async function getStats(id) {
  try {
    return await dockerReq('GET', `/containers/${id}/stats?stream=false`);
  } catch { return null; }
}

function calcCpu(s) {
  if (!s?.cpu_stats?.cpu_usage) return 0;
  const cpu  = s.cpu_stats.cpu_usage.total_usage    - (s.precpu_stats?.cpu_usage?.total_usage  ?? 0);
  const sys  = s.cpu_stats.system_cpu_usage          - (s.precpu_stats?.system_cpu_usage        ?? 0);
  if (sys === 0) return 0;
  const n    = s.cpu_stats.online_cpus || s.cpu_stats.cpu_usage.percpu_usage?.length || 1;
  return Math.min((cpu / sys) * n * 100, 100);
}

function calcMem(s) {
  if (!s?.memory_stats?.usage) return { used: 0, limit: 0, pct: 0 };
  const cache = s.memory_stats.stats?.cache ?? 0;
  const used  = s.memory_stats.usage - cache;
  const limit = s.memory_stats.limit || 1;
  return { used, limit, pct: Math.min((used / limit) * 100, 100) };
}

async function getFullStatus() {
  const containers = await getContainers();
  const statsArr   = await Promise.all(containers.map(c => getStats(c.Id)));

  return containers.map((c, i) => {
    const s   = statsArr[i];
    const mem = calcMem(s);
    return {
      id:          c.Id.slice(0, 12),
      name:        (c.Names[0] ?? c.Id).replace('/', ''),
      state:       c.State,
      status:      c.Status,
      cpu:         s ? parseFloat(calcCpu(s).toFixed(1)) : null,
      mem_used:    mem.used,
      mem_limit:   mem.limit,
      mem_pct:     parseFloat(mem.pct.toFixed(1)),
    };
  });
}

// ── Container actions ─────────────────────────────────────────────────────────

async function restartContainer(name) {
  const containers = await getContainers();
  const c = containers.find(x => (x.Names[0] ?? '').replace('/', '') === name);
  if (!c) throw new Error(`Container "${name}" not found`);
  await dockerReq('POST', `/containers/${c.Id}/restart`);
}

// ── Docker Compose runner ─────────────────────────────────────────────────────

function composeArgs() {
  const cfg = parseEnv(ENV_FILE);
  const base = ['-f', COMPOSE_FILE, '--env-file', ENV_FILE];
  if (cfg.GPU_PROVIDER === 'nvidia') base.splice(2, 0, '-f', NVIDIA_FILE);
  return base;
}

function runCompose(extraArgs, onLine) {
  return new Promise((resolve, reject) => {
    const args = ['compose', ...composeArgs(), ...extraArgs];
    // detached: true so the subprocess survives if plex-control itself gets
    // recreated mid-deploy (which kills our Node process temporarily).
    const child = spawn('docker', args, { cwd: CWD, detached: true });

    const pipe = chunk => {
      for (const line of chunk.toString().split('\n')) {
        if (line.trim()) onLine(line.trimEnd());
      }
    };
    child.stdout.on('data', pipe);
    child.stderr.on('data', pipe);
    child.on('error', reject);
    child.on('close', resolve);
    // Don't unref — we still want to stream output while we're alive.
  });
}

// ── Host environment detection ────────────────────────────────────────────────

async function getDockerInfo() {
  try { return await dockerReq('GET', '/info'); } catch { return {}; }
}

async function getWindowsUsername() {
  // Inspect our own mounts — Docker Desktop for Windows maps host paths as
  // /run/desktop/mnt/host/c/Users/USERNAME/... inside the container.
  try {
    const filter = encodeURIComponent(JSON.stringify({ name: ['plex-control'] }));
    const list   = await dockerReq('GET', `/containers/json?filters=${filter}`);
    const self   = (Array.isArray(list) ? list : []).find(c =>
      (c.Names || []).some(n => n.replace('/', '') === 'plex-control')
    );
    if (!self) return null;
    const detail = await dockerReq('GET', `/containers/${self.Id}/json`);
    for (const m of (detail.Mounts || [])) {
      const match = (m.Source || '').match(/\/Users\/([^/]+)\//i);
      if (match) return match[1];
    }
  } catch {}
  return null;
}

module.exports = { getFullStatus, restartContainer, runCompose, composeArgs, getDockerInfo, getWindowsUsername };
