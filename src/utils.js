'use strict';
const fs = require('fs');

function parseEnv(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const result = {};
  for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx === -1) continue;
    result[trimmed.slice(0, idx).trim()] = trimmed.slice(idx + 1).trim();
  }
  return result;
}

function buildEnvContent(v) {
  const g = (k, d = '') => v[k] ?? d;
  return [
    '# User/Group IDs',
    `PUID=${g('PUID', '1000')}`,
    `PGID=${g('PGID', '1000')}`,
    `TZ=${g('TZ', 'America/Edmonton')}`,
    '',
    '# Paths',
    `BASE_PATH=${g('BASE_PATH')}`,
    `MEDIA_SHARE=${g('MEDIA_SHARE')}`,
    '',
    '# Plex',
    `PLEX_CLAIM=${g('PLEX_CLAIM')}`,
    `PLEX_URL=${g('PLEX_URL')}`,
    `PLEX_TOKEN=${g('PLEX_TOKEN')}`,
    '',
    '# VPN',
    `VPN_USER=${g('VPN_USER')}`,
    `VPN_PASS=${g('VPN_PASS')}`,
    `VPN_PROV=${g('VPN_PROV', 'pia')}`,
    `VPN_CLIENT=${g('VPN_CLIENT', 'wireguard')}`,
    `LAN_NETWORK=${g('LAN_NETWORK', '192.168.1.0/24')}`,
    '',
    '# Network & API Keys',
    `SERVER_IP=${g('SERVER_IP')}`,
    `SONARR_KEY=${g('SONARR_KEY')}`,
    `RADARR_KEY=${g('RADARR_KEY')}`,
    '',
    '# Hardware Transcoding: none | nvidia',
    `GPU_PROVIDER=${g('GPU_PROVIDER', 'none')}`,
    '',
    '# VPN for qBittorrent: yes | no',
    `VPN_ENABLED=${g('VPN_ENABLED', 'yes')}`,
    '',
    '# Setup wizard completion flag — do not edit manually',
    `SETUP_COMPLETE=${g('SETUP_COMPLETE', 'no')}`,
    '',
  ].join('\n');
}

module.exports = { parseEnv, buildEnvContent };
