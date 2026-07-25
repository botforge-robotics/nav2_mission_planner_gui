import cors from 'cors';
import express from 'express';
import net from 'net';
import os from 'os';
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

const PORT = Number(process.env.API_PORT || 3001);
const DB_PATH = process.env.DB_PATH || path.join(process.cwd(), 'data', 'app.db');
const HEARTBEAT_TIMEOUT_MS = Number(process.env.HEARTBEAT_TIMEOUT_MS || 2500);
const SCAN_PORTS = (process.env.SCAN_PORTS || '9090')
  .split(',')
  .map((p) => Number(p.trim()))
  .filter(Boolean);

fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });
const db = new Database(DB_PATH);
db.pragma('journal_mode = WAL');

db.exec(`
  CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS discovered (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    ip TEXT NOT NULL,
    port TEXT NOT NULL DEFAULT '9090',
    last_seen INTEGER NOT NULL,
    source TEXT NOT NULL DEFAULT 'scan'
  );
  CREATE TABLE IF NOT EXISTS app_data (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  );
`);

const DEFAULT_SETTINGS = {
  cmdVelTopic: '/cmd_vel_teleop',
  linearVelocity: 0.4,
  angularVelocity: 1.0,
  twistType: 'geometry_msgs/msg/Twist',
  mapsPath: 'navpromini_mapping/maps',
  mappingLaunchFile: 'navpromini_mission_planner/mapping_launch',
  mappingOdomTopic: '/odom',
  mappingOdomTopicType: 'nav_msgs/msg/Odometry',
  mappingArgs: [
    { name: 'use_sim_time', value: 'false' },
    { name: 'use_rviz', value: 'false' },
  ],
  saveMapLaunchFile: 'nav2_mission_planner/save_map',
  saveMapArgs: [],
  navigationLaunchFile: 'navpromini_mission_planner/navigation_launch',
  navigationOdomTopic: '/amcl_pose',
  navigationOdomTopicType: 'geometry_msgs/msg/PoseWithCovarianceStamped',
  navigationArgs: [
    { name: 'use_sim_time', value: 'false' },
    { name: 'use_rviz', value: 'false' },
  ],
  cameraImageTopic: '',
  cameraEnabled: false,
  odomTopic: '/odom',
  odomTopicType: 'nav_msgs/msg/Odometry',
  lidarTopic: '/scan',
  communicationTimeout: 120,
  cameraVisible: false,
  joystickVisible: true,
  pathTopic: '/plan',
  tfTopic: '/tf',
  mapFrame: 'map',
  odomFrame: 'odom',
  baseLinkFrame: 'base_link',
  bookmarks: {},
  bookmarksVisible: true,
  missions: {},
};

function getMeta(key) {
  const row = db.prepare('SELECT value FROM meta WHERE key = ?').get(key);
  return row ? row.value : null;
}

function setMeta(key, value) {
  db.prepare(
    'INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
  ).run(key, value);
}

function getAppData(key, fallback) {
  const row = db.prepare('SELECT value FROM app_data WHERE key = ?').get(key);
  if (!row) return fallback;
  try {
    return JSON.parse(row.value);
  } catch {
    return fallback;
  }
}

function setAppData(key, value) {
  db.prepare(
    `INSERT INTO app_data (key, value, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`,
  ).run(key, JSON.stringify(value), Date.now());
}

function probePort(ip, port, timeoutMs = HEARTBEAT_TIMEOUT_MS) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let done = false;
    const finish = (ok) => {
      if (done) return;
      done = true;
      socket.destroy();
      resolve(ok);
    };
    socket.setTimeout(timeoutMs);
    socket.once('connect', () => finish(true));
    socket.once('timeout', () => finish(false));
    socket.once('error', () => finish(false));
    socket.connect(port, ip);
  });
}

/** Skip Docker / VM bridge ranges (e.g. 172.19.0.10 is not a Wi‑Fi robot). */
function isIgnoredScanIp(ip) {
  const p = ip.split('.').map(Number);
  if (p.length !== 4 || p.some((n) => Number.isNaN(n))) return true;
  // 172.16.0.0/12 — Docker bridges commonly 172.17–172.31
  if (p[0] === 172 && p[1] >= 16 && p[1] <= 31) return true;
  if (p[0] === 127) return true;
  if (p[0] === 169 && p[1] === 254) return true;
  return false;
}

function isVirtualIface(name) {
  return /^(docker|br-|veth|virbr|cni|flannel|kube|tun|tap|wg)/i.test(name);
}

function localSubnets() {
  const cidrEnv = process.env.SCAN_CIDR;
  if (cidrEnv) return [cidrEnv];

  const nets = [];
  const ifaces = os.networkInterfaces();
  for (const [name, entries] of Object.entries(ifaces)) {
    if (isVirtualIface(name)) continue;
    for (const e of entries || []) {
      const family = e.family === 'IPv4' || e.family === 4;
      if (!family || e.internal) continue;
      if (isIgnoredScanIp(e.address)) continue;
      const parts = e.address.split('.').map(Number);
      // Real LAN only: 10.x / 192.168.x
      if (!(parts[0] === 10 || (parts[0] === 192 && parts[1] === 168))) continue;
      nets.push(`${parts[0]}.${parts[1]}.${parts[2]}.0/24`);
    }
  }
  return nets.length ? [...new Set(nets)] : ['192.168.1.0/24'];
}

function hostsFromCidr(cidr) {
  const [base, bitsStr] = cidr.split('/');
  const bits = Number(bitsStr || 24);
  if (bits !== 24) {
    // only support /24 for simple LAN sweep
    const p = base.split('.').map(Number);
    return Array.from({ length: 254 }, (_, i) => `${p[0]}.${p[1]}.${p[2]}.${i + 1}`);
  }
  const p = base.split('.').map(Number);
  return Array.from({ length: 254 }, (_, i) => `${p[0]}.${p[1]}.${p[2]}.${i + 1}`);
}

async function mapPool(items, concurrency, fn) {
  const results = [];
  let idx = 0;
  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      results[i] = await fn(items[i], i);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, () => worker()),
  );
  return results;
}

async function scanNearby() {
  // Drop previous scan hits (clears Docker false positives like 172.19.0.10)
  db.prepare('DELETE FROM discovered WHERE source = ?').run('scan');

  const cidrs = localSubnets();
  const hosts = [...new Set(cidrs.flatMap(hostsFromCidr))].filter(
    (ip) => !isIgnoredScanIp(ip),
  );
  const found = [];
  await mapPool(hosts, 64, async (ip) => {
    for (const port of SCAN_PORTS) {
      const ok = await probePort(ip, port, 400);
      if (ok) {
        found.push({ ip, port: String(port) });
        break;
      }
    }
  });

  const upsert = db.prepare(`
    INSERT INTO discovered (id, name, ip, port, last_seen, source)
    VALUES (@id, @name, @ip, @port, @last_seen, 'scan')
    ON CONFLICT(id) DO UPDATE SET
      name = excluded.name,
      ip = excluded.ip,
      port = excluded.port,
      last_seen = excluded.last_seen,
      source = 'scan'
  `);

  const now = Date.now();
  for (const r of found) {
    if (isIgnoredScanIp(r.ip)) continue;
    const id = `${r.ip}:${r.port}`;
    upsert.run({
      id,
      name: `NavProMini ${r.ip}`,
      ip: r.ip,
      port: r.port,
      last_seen: now,
    });
  }
  return found;
}

const app = express();
app.use(cors());
app.use(express.json({ limit: '2mb' }));

app.get('/api/health', (_req, res) => {
  res.json({ ok: true });
});

app.get('/api/defaults', (_req, res) => {
  res.json(DEFAULT_SETTINGS);
});

app.get('/api/claim', (_req, res) => {
  const raw = getMeta('claimed_robot');
  res.json(raw ? JSON.parse(raw) : null);
});

app.post('/api/claim', async (req, res) => {
  const { name, ip, port = '9090', id } = req.body || {};
  if (!ip) return res.status(400).json({ error: 'ip required' });
  if (isIgnoredScanIp(String(ip))) {
    return res.status(400).json({ error: 'Docker/bridge IPs cannot be claimed' });
  }
  const robot = {
    id: id || `${ip}:${port}`,
    name: name || `NavProMini ${ip}`,
    ip: String(ip),
    port: String(port),
    claimedAt: Date.now(),
  };
  setMeta('claimed_robot', JSON.stringify(robot));
  // Seed settings once
  if (!getAppData('settings', null)) {
    setAppData('settings', DEFAULT_SETTINGS);
  }
  const alive = await probePort(robot.ip, Number(robot.port));
  res.json({ robot, online: alive });
});

app.delete('/api/claim', (_req, res) => {
  db.prepare('DELETE FROM meta WHERE key = ?').run('claimed_robot');
  res.json({ ok: true });
});

app.get('/api/heartbeat', async (_req, res) => {
  const raw = getMeta('claimed_robot');
  if (!raw) return res.json({ claimed: false, online: false });
  const robot = JSON.parse(raw);
  const online = await probePort(robot.ip, Number(robot.port));
  res.json({
    claimed: true,
    online,
    robot,
    checkedAt: Date.now(),
  });
});

app.get('/api/nearby', async (req, res) => {
  const doScan = req.query.scan !== '0';
  if (doScan) {
    try {
      await scanNearby();
    } catch (e) {
      return res.status(500).json({ error: String(e) });
    }
  }
  const cutoff = Date.now() - 5 * 60 * 1000;
  const rows = db
    .prepare(
      'SELECT id, name, ip, port, last_seen, source FROM discovered WHERE last_seen >= ? ORDER BY last_seen DESC',
    )
    .all(cutoff)
    .filter((r) => !isIgnoredScanIp(r.ip));
  res.json({ robots: rows, scannedAt: Date.now(), subnets: localSubnets() });
});

app.post('/api/announce', (req, res) => {
  const { name, ip, port = '9090' } = req.body || {};
  if (!ip) return res.status(400).json({ error: 'ip required' });
  if (isIgnoredScanIp(String(ip))) {
    return res.status(400).json({ error: 'Docker/bridge IPs are not allowed' });
  }
  const id = `${ip}:${port}`;
  db.prepare(`
    INSERT INTO discovered (id, name, ip, port, last_seen, source)
    VALUES (?, ?, ?, ?, ?, 'announce')
    ON CONFLICT(id) DO UPDATE SET
      name = excluded.name,
      last_seen = excluded.last_seen,
      source = 'announce'
  `).run(id, name || `NavProMini ${ip}`, String(ip), String(port), Date.now());
  res.json({ ok: true, id });
});

app.get('/api/settings', (_req, res) => {
  const settings = getAppData('settings', DEFAULT_SETTINGS);
  res.json({ ...DEFAULT_SETTINGS, ...settings });
});

app.put('/api/settings', (req, res) => {
  const current = getAppData('settings', DEFAULT_SETTINGS);
  // Keep transport defaults locked to NavProMini; allow UI prefs + missions/bookmarks
  const locked = { ...DEFAULT_SETTINGS };
  const incoming = req.body || {};
  const next = {
    ...locked,
    ...current,
    ...incoming,
    // force robot contract
    cmdVelTopic: locked.cmdVelTopic,
    twistType: locked.twistType,
    mapsPath: locked.mapsPath,
    mappingLaunchFile: locked.mappingLaunchFile,
    navigationLaunchFile: locked.navigationLaunchFile,
    mappingOdomTopic: locked.mappingOdomTopic,
    mappingOdomTopicType: locked.mappingOdomTopicType,
    navigationOdomTopic: locked.navigationOdomTopic,
    navigationOdomTopicType: locked.navigationOdomTopicType,
    pathTopic: locked.pathTopic,
    lidarTopic: locked.lidarTopic,
    tfTopic: locked.tfTopic,
    mapFrame: locked.mapFrame,
    odomFrame: locked.odomFrame,
    baseLinkFrame: locked.baseLinkFrame,
    mappingArgs: locked.mappingArgs,
    navigationArgs: locked.navigationArgs,
    cameraEnabled: false,
    cameraImageTopic: '',
  };
  setAppData('settings', next);
  res.json(next);
});

app.get('/api/data/:key', (req, res) => {
  res.json(getAppData(req.params.key, null));
});

app.put('/api/data/:key', (req, res) => {
  setAppData(req.params.key, req.body);
  res.json({ ok: true });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Mission Planner API on :${PORT} (db=${DB_PATH})`);
});
