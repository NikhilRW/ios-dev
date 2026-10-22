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
# Run the foreground server in a detached process group. In 0.10.3,
# --require-token explicitly refuses --detach / --no-preview.
# No token, token-bearing URL, or raw upstream error is emitted by this supervisor.
node - "$PRIVATE" "$SERVE_SIM_CLI" "$CLOUDFLARED" "$SIMULATOR_UDID" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const { spawn, execFileSync } = require('node:child_process');
const { createRequire } = require('node:module');
const [privateDir, cli, cloudflared, udid] = process.argv.slice(2);
const records = {};
let phase = 'pinned CLI interface verification';
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const alive = pid => { try { process.kill(pid, 0); return true; } catch { return false; } };
const save = () => fs.writeFileSync('.dev-session/services.json', JSON.stringify(records));
async function start(name, command, args, env = process.env) {
  const fd = fs.openSync(path.join(privateDir, `${name}.log`), 'a', 0o600);
  const child = spawn(command, args, { detached: true, stdio: ['ignore', fd, fd], env });
  fs.closeSync(fd);
  await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
  records[name] = { pid: child.pid, command: name === 'preview' ? cli : cloudflared };
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
async function verifyGate(url) {
  for (const route of ['/', '/api', `/helper/${udid}/stream.mjpeg`]) {
    const res = await request(url + route);
    await res.body?.cancel();
    if (res.status !== 401 && res.status !== 403) throw new Error('Unauthenticated preview access was not refused');
  }
}
async function verifySession(url, token) {
  // Emulate document navigation. Keep headers (including Set-Cookie) private.
  const nav = await request(url + '/?token=' + encodeURIComponent(token), {
    headers: { Accept: 'text/html', 'Sec-Fetch-Mode': 'navigate', 'Sec-Fetch-Dest': 'document' },
  });
  const cookie = nav.headers.getSetCookie().map(c => c.split(';')[0]).join('; ');
  const location = nav.headers.get('location');
  await nav.body?.cancel();
  if (nav.status !== 302 || !cookie || !location || location.includes('token=')) throw new Error('Token-to-cookie navigation failed');
  const page = await request(new URL(location, url), { headers: { Cookie: cookie } });
  await page.body?.cancel();
  if (page.status !== 200) throw new Error('Authenticated cookie navigation failed');
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const stream = await request(`${url}/helper/${udid}/stream.mjpeg`, {
      headers: { Cookie: cookie }, signal: controller.signal,
    });
    if (stream.status !== 200) throw new Error('Authenticated MJPEG stream failed');
    let data = Buffer.alloc(0);
    for await (const chunk of stream.body) {
      data = Buffer.concat([data, Buffer.from(chunk)]);
      if (data.includes(Buffer.from([0xff, 0xd8])) && data.includes(Buffer.from([0xff, 0xd9]))) break;
      if (data.length > 4000000) throw new Error('No JPEG frame received');
    }
    if (!data.includes(Buffer.from([0xff, 0xd9]))) throw new Error('No complete JPEG frame received');
  } finally { clearTimeout(timer); controller.abort(); }
  const WebSocket = createRequire(cli)('ws');
  async function socket(authenticated) {
    await new Promise((resolve, reject) => {
      const ws = new WebSocket(`${url.replace(/^http/, 'ws')}/helper/${udid}/ws`,
        authenticated ? [`serve-sim.token.${token}`] : [], { headers: { Origin: url } });
      let done = false;
      const finish = err => {
        if (done) return; done = true; clearTimeout(timeout); ws.terminate();
        if (err) reject(err); else resolve();
      };
      const timeout = setTimeout(() => finish(new Error('Input socket admission timed out')), 12000);
      ws.on('unexpected-response', (_req, res) => {
        res.resume();
        finish(!authenticated && [401, 403].includes(res.statusCode) ? null : new Error('Input handshake refused'));
      });
      ws.on('message', data => {
        if (!authenticated) return finish(new Error('Unauthenticated input received data'));
        if (data[0] === 0x83 || data[0] === 0x82) finish();
      });
      ws.on('close', code => finish(!authenticated && code === 1008 ? null : new Error('Input socket closed before admission')));
      ws.on('error', () => finish(new Error('Input socket connection failed')));
    });
  }
  await socket(false);
  await socket(true); // Admission only: browser touch/gesture delivery still needs a human check.
}
(async () => {
  const help = execFileSync(process.execPath, [cli, '--help'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  fs.writeFileSync(path.join(privateDir, 'serve-sim-help.txt'), help, { mode: 0o600 });
  for (const flag of ['--require-token', '--host', '--transport', '--codec', '--mjpeg-fps', '--mjpeg-quality', '--max-dimension']) {
    if (!help.includes(flag)) {
      console.error(`Pinned serve-sim 0.10.3 lacks ${flag}. Stop: review a supported authenticated release before opening a tunnel.`);
      throw new Error('Missing required preview flag');
    }
  }
  const stateDir = path.join(privateDir, 'state');
  fs.mkdirSync(stateDir, { mode: 0o700 });
  phase = 'local simulator capture readiness';
  await start('preview', process.execPath, [cli, udid, '--host', '127.0.0.1', '--port', '3200',
    '--require-token', '--quiet', '--transport', 'http', '--codec', 'mjpeg',
    '--mjpeg-fps', '30', '--mjpeg-quality', '0.7', '--max-dimension', '900', '--disable-share', '--disable', 'clipboard'],
    { ...process.env, SERVE_SIM_STATE_DIR: stateDir });
  await waitFor(() => healthy('http://127.0.0.1:3200'), 180, 'Simulator capture readiness');
  let state;
  try { state = JSON.parse(fs.readFileSync(path.join(stateDir, `server-${udid}.json`), 'utf8')); }
  catch { throw new Error('Missing serve-sim per-device JSON state'); }
  if (!state.token || state.device !== udid || state.port !== 3200 || state.pid !== records.preview.pid) {
    throw new Error('serve-sim state does not match the authenticated session');
  }
  phase = 'local authentication, JPEG, and input admission checks';
  await verifyGate('http://127.0.0.1:3200');
  await verifySession('http://127.0.0.1:3200', state.token);
  phase = 'Quick Tunnel startup and DNS readiness';
  await start('tunnel', cloudflared, ['tunnel', '--no-autoupdate', '--url', 'http://127.0.0.1:3200']);
  const url = await waitFor(() => {
    const log = fs.readFileSync(path.join(privateDir, 'tunnel.log'), 'utf8');
    return log.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com\b/)?.[0];
  }, 90, 'Quick Tunnel hostname');
  fs.writeFileSync('.dev-session/tunnel-url.txt', url + '\n');
  await waitFor(() => healthy(url), 120, 'Tunnel DNS and capture readiness');
  phase = 'HTTPS authentication, JPEG, and input admission checks';
  await verifyGate(url);
  await verifySession(url, state.token);
  console.log('Preview ready: authentication, JPEG frame, and WebSocket admission checks passed locally and through HTTPS.');
  console.log(`Bare preview URL (authentication required): ${url}`);
  console.log('After joining SSH: cd "$GITHUB_WORKSPACE" && bash scripts/preview-url.sh');
  console.log('Home screen is ready. Build manually with: bash scripts/build-run.sh');
})().catch(error => {
  // Upstream errors can contain tokens. Never stringify the caught exception here.
  fs.writeFileSync(path.join(privateDir, 'startup-error.txt'), String(error?.stack || error), { mode: 0o600 });
  console.error(`Preview startup failed during ${phase}. Private diagnostics are under the directory recorded in .dev-session/private-dir.txt. Do not publish those files.`);
  for (const r of Object.values(records)) { try { process.kill(-r.pid, 'SIGTERM'); } catch {} }
  process.exitCode = 1;
});
NODE
