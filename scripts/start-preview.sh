#!/bin/bash
set +x
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
umask 077
[[ -f .dev-session/tools.env && -f .dev-session/simulator.env ]] || {
  echo 'Prepare the tools and boot a simulator first.' >&2; exit 1;
}
# shellcheck disable=SC1091
source .dev-session/tools.env
# shellcheck disable=SC1091
source .dev-session/simulator.env
: "${RUNNER_TEMP:?RUNNER_TEMP must be set}"
if [[ -f .dev-session/services.json ]]; then
  echo 'Preview was already started. Use status.sh, or cleanup.sh before restarting.' >&2
  exit 1
fi
PRIVATE="$(mktemp -d "$RUNNER_TEMP/helloios-preview.XXXXXX")"
chmod 700 "$PRIVATE"
printf '%s\n' "$PRIVATE" > .dev-session/private-dir.txt
# native-sim's topology: loopback serve-sim -> bundled auth gate -> Quick Tunnel.
# Foreground serve-sim preserves capture/host options; each service is detached
# with private output. No token or raw upstream error is emitted by this supervisor.
node - "$PRIVATE" "$SERVE_SIM_CLI" "$CLOUDFLARED" "$SIMULATOR_UDID" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');
const { createRequire } = require('node:module');
const { randomBytes } = require('node:crypto');
const [privateDir, cli, cloudflared, udid] = process.argv.slice(2);
const gateScript = path.resolve('.github/native-sim/gate.cjs');
const records = {};
let phase = 'pinned CLI interface verification';
// Only errors constructed here may expose a public diagnostic. Upstream errors
// and response bodies can contain credentials and stay in the private log.
class ProbeError extends Error {}
const probeError = (message, status) => new ProbeError(
  message + (Number.isInteger(status) ? ` (HTTP ${status})` : '')
);
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
const save = () => fs.writeFileSync('.dev-session/services.json', JSON.stringify(records));
async function start(name, command, args, env = process.env) {
  const fd = fs.openSync(path.join(privateDir, `${name}.log`), 'a', 0o600);
  const child = spawn(command, args, { detached: true, stdio: ['ignore', fd, fd], env });
  fs.closeSync(fd);
  await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
  records[name] = { pid: child.pid, command: command === process.execPath ? args[0] : command };
  save();
  child.unref();
}
async function waitFor(check, seconds, label) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) {
    if (Object.values(records).some(r => !alive(r.pid))) throw new Error('A required preview service exited');
    try { const result = await check(); if (result) return result; } catch { /* bounded retry */ }
    await sleep(1000);
  }
  throw new Error(`${label} timed out`);
}
const request = (url, options = {}) => fetch(url, { redirect: 'manual', signal: AbortSignal.timeout(7000), ...options });
async function healthy(url) {
  const res = await request(url + '/readyz');
  await res.body?.cancel();
  return res.status === 200;
}
async function gateHealthy(url) {
  const res = await request(url + '/__native-sim/healthz');
  if (res.status !== 200) { await res.body?.cancel(); return false; }
  const health = await res.json();
  return health.ok === true && health.target === 3200;
}
async function verifyGate(url) {
  for (const route of ['/', '/api', `/helper/${udid}/stream.mjpeg`]) {
    phase = `${url.startsWith('https:') ? 'HTTPS' : 'local'} unauthenticated ${route === '/' ? 'page' : route === '/api' ? 'API' : 'MJPEG'} rejection`;
    const res = await request(url + route);
    await res.body?.cancel();
    if (res.status !== 401 && res.status !== 403) throw probeError('Unauthenticated preview access was not refused', res.status);
  }
}
async function verifySession(url, token) {
  const scope = url.startsWith('https:') ? 'HTTPS' : 'local';
  phase = `${scope} token-to-cookie navigation`;
  // Emulate document navigation. Keep headers (including Set-Cookie) private.
  const nav = await request(url + '/?k=' + encodeURIComponent(token), {
    headers: { Accept: 'text/html', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'document' },
  });
  const cookie = nav.headers.getSetCookie().map(c => c.split(';')[0]).join('; ');
  const location = nav.headers.get('location');
  await nav.body?.cancel();
  if (nav.status !== 302 || !cookie || !location || location.includes('k=')) throw probeError('Gate token-to-cookie navigation did not return a clean redirect and cookie', nav.status);
  phase = `${scope} authenticated cookie navigation`;
  const page = await request(new URL(location, url), { headers: { Cookie: cookie } });
  await page.body?.cancel();
  if (page.status !== 200) throw probeError('Authenticated cookie navigation was refused', page.status);
  phase = `${scope} authenticated JPEG frame`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const stream = await request(`${url}/helper/${udid}/stream.mjpeg`, {
      headers: { Cookie: cookie }, signal: controller.signal,
    });
    if (stream.status !== 200) throw probeError('Authenticated MJPEG stream was refused', stream.status);
    let data = Buffer.alloc(0);
    for await (const chunk of stream.body) {
      data = Buffer.concat([data, Buffer.from(chunk)]);
      if (data.includes(Buffer.from([0xff, 0xd8])) && data.includes(Buffer.from([0xff, 0xd9]))) break;
      if (data.length > 4000000) throw probeError('No JPEG frame received within the probe size limit');
    }
    if (!data.includes(Buffer.from([0xff, 0xd8])) || !data.includes(Buffer.from([0xff, 0xd9]))) throw probeError('Stream ended without a complete JPEG frame');
  } finally { clearTimeout(timer); controller.abort(); }
  const WebSocket = createRequire(cli)('ws');
  async function socket(authenticated) {
    phase = `${scope} ${authenticated ? 'authenticated input admission' : 'unauthenticated input rejection'}`;
    await new Promise((resolve, reject) => {
      // Exercise browser-style gate cookie authentication, not serve-sim's
      // built-in token subprotocol. Its input socket sits behind the gate.
      const ws = new WebSocket(`${url.replace(/^http/, 'ws')}/helper/${udid}/ws`, {
        headers: { Origin: url, ...(authenticated ? { Cookie: cookie } : {}) },
      });
      let done = false;
      const finish = err => {
        if (done) return; done = true; clearTimeout(timeout); ws.terminate();
        if (err) reject(err); else resolve();
      };
      const timeout = setTimeout(() => finish(probeError('Input socket check timed out')), 12000);
      ws.on('unexpected-response', (_req, res) => {
        res.resume();
        finish(!authenticated && [401, 403].includes(res.statusCode) ? null : probeError('Input handshake returned an unexpected response', res.statusCode));
      });
      ws.on('message', data => {
        if (!authenticated) return finish(probeError('Unauthenticated input received data'));
        if (data[0] === 0x83 || data[0] === 0x82) finish();
      });
      ws.on('close', () => finish(probeError('Input socket closed before the expected result')));
      ws.on('error', () => finish(probeError('Input socket connection failed')));
    });
  }
  await socket(false);
  await socket(true); // Admission only: browser touch/gesture delivery still needs a human check.
}
(async () => {
  const help = execFileSync(process.execPath, [cli, '--help'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  fs.writeFileSync(path.join(privateDir, 'serve-sim-help.txt'), help, { mode: 0o600 });
  for (const flag of ['--allow-any-host-when-insecure', '--host', '--transport', '--codec', '--mjpeg-fps', '--mjpeg-quality', '--max-dimension']) {
    if (!help.includes(flag)) {
      console.error(`Pinned serve-sim 0.10.3 lacks ${flag}. Stop: review the native-sim preview interface before opening a tunnel.`);
      throw new Error('Missing required preview flag');
    }
  }
  const stateDir = path.join(privateDir, 'state');
  fs.mkdirSync(stateDir, { mode: 0o700 });
  phase = 'local simulator capture readiness';
  await start('preview', process.execPath, [cli, udid, '--host', '127.0.0.1', '--port', '3200',
    '--allow-any-host-when-insecure', '--quiet', '--transport', 'http', '--codec', 'mjpeg',
    '--mjpeg-fps', '30', '--mjpeg-quality', '0.7', '--max-dimension', '900', '--disable-share', '--disable', 'clipboard'],
    { ...process.env, SERVE_SIM_STATE_DIR: stateDir });
  await waitFor(() => healthy('http://127.0.0.1:3200'), 180, 'Simulator capture readiness');
  let state;
  try { state = JSON.parse(fs.readFileSync(path.join(stateDir, `server-${udid}.json`), 'utf8')); }
  catch { throw new Error('Missing serve-sim per-device JSON state'); }
  if (state.device !== udid || state.port !== 3200 || state.pid !== records.preview.pid) {
    throw new Error('serve-sim state does not match the selected simulator');
  }
  phase = 'local native-sim auth gate startup';
  const token = randomBytes(32).toString('base64url');
  await start('gate', process.execPath, [gateScript], {
    ...process.env, NATIVE_SIM_GATE_TOKEN: token,
    NATIVE_SIM_TARGET_PORT: '3200', NATIVE_SIM_GATE_PORT: '3199',
  });
  fs.writeFileSync(path.join(privateDir, 'gate-session.json'), JSON.stringify({
    token, device: udid, previewPid: records.preview.pid, gatePid: records.gate.pid,
  }), { mode: 0o600 });
  await waitFor(() => gateHealthy('http://127.0.0.1:3199'), 30, 'native-sim auth gate readiness');
  await verifyGate('http://127.0.0.1:3199');
  await verifySession('http://127.0.0.1:3199', token);
  phase = 'Quick Tunnel startup and DNS readiness';
  await start('tunnel', cloudflared, ['tunnel', '--no-autoupdate', '--url', 'http://127.0.0.1:3199']);
  const url = await waitFor(() => {
    const log = fs.readFileSync(path.join(privateDir, 'tunnel.log'), 'utf8');
    return log.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com\b/)?.[0];
  }, 90, 'Quick Tunnel hostname');
  fs.writeFileSync('.dev-session/tunnel-url.txt', url + '\n');
  await waitFor(() => gateHealthy(url), 120, 'Tunnel DNS and gate readiness');
  phase = 'HTTPS authentication, JPEG, and input admission checks';
  await verifyGate(url);
  await verifySession(url, token);
  console.log('native-sim preview ready: gate authentication, JPEG frame, and WebSocket admission checks passed locally and through HTTPS.');
  console.log(`Bare preview URL (authentication required): ${url}`);
  console.log('After joining SSH: cd "$GITHUB_WORKSPACE" && bash scripts/preview-url.sh');
  console.log('Home screen is ready. Build manually with: bash scripts/build-run.sh');
})().catch(error => {
  // Upstream errors can contain tokens. Never stringify the caught exception here.
  fs.writeFileSync(path.join(privateDir, 'startup-error.txt'), String(error?.stack || error), { mode: 0o600 });
  console.error(`Preview startup failed during ${phase}. Private diagnostics are under the directory recorded in .dev-session/private-dir.txt. Do not publish those files.`);
  if (error instanceof ProbeError) console.error(`Check result: ${error.message}`);
  for (const r of Object.values(records)) { try { process.kill(-r.pid, 'SIGTERM'); } catch {} }
  process.exitCode = 1;
});
NODE
