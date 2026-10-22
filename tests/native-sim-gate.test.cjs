const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const { randomBytes, createHash } = require('node:crypto');

// Synthetic fixture credential only. No GitHub, simulator, or tunnel needed.
const token = randomBytes(32).toString('base64url');
const requests = [];
const sockets = new Set();
let upstream, child, origin, cookie;

function track(socket) {
  sockets.add(socket);
  socket.on('close', () => sockets.delete(socket));
}

async function freePort() {
  const server = net.createServer();
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

before(async () => {
  upstream = http.createServer((req, res) => {
    requests.push({ path: req.url, host: req.headers.host, proto: req.headers['x-forwarded-proto'] });
    if (req.url.endsWith('/stream.mjpeg')) {
      res.writeHead(200, { 'Content-Type': 'multipart/x-mixed-replace; boundary=frame' });
      res.write(Buffer.from('--frame\r\nContent-Type: image/jpeg\r\n\r\n', 'ascii'));
      res.write(Buffer.from([0xff, 0xd8, 0xff, 0xd9]));
      return; // Prove a live response is forwarded before the upstream ends.
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ fixture: true }));
  });
  upstream.on('connection', track);
  upstream.on('upgrade', (req, socket, head) => {
    requests.push({ path: req.url, upgrade: true, host: req.headers.host, proto: req.headers['x-forwarded-proto'] });
    const accept = createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    if (head.length) socket.write(head);
    socket.on('data', data => socket.write(data));
    socket.on('error', () => {});
  });
  upstream.listen(0, '127.0.0.1');
  await once(upstream, 'listening');
  const port = await freePort();
  origin = `http://127.0.0.1:${port}`;
  child = spawn(process.execPath, [path.resolve('.github/native-sim/gate.cjs')], {
    env: { ...process.env, NATIVE_SIM_GATE_TOKEN: token,
      NATIVE_SIM_TARGET_PORT: String(upstream.address().port), NATIVE_SIM_GATE_PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.resume(); child.stderr.resume();
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) throw new Error('Gate fixture exited before readiness');
    try {
      const res = await fetch(origin + '/__native-sim/healthz');
      if (res.status === 200) { await res.body.cancel(); return; }
    } catch { /* wait for the child listener */ }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error('Gate fixture did not become ready');
});

after(async () => {
  if (child && child.exitCode === null) { const exit = once(child, 'exit'); child.kill(); await exit; }
  for (const socket of sockets) socket.destroy();
  if (upstream) await new Promise(resolve => upstream.close(resolve));
});

test('only the exact gate liveness path is public', async () => {
  const res = await fetch(origin + '/__native-sim/healthz');
  assert.equal((await res.json()).ok, true);
  assert.equal((await fetch(origin + '/__native-sim/healthz-extra')).status, 403);
});

test('unauthenticated preview, API, capture and controls never reach upstream', async () => {
  const before = requests.length;
  for (const route of ['/', '/api', '/readyz', '/helper/device/stream.mjpeg', '/exec-ws']) {
    const res = await fetch(origin + route);
    assert.equal(res.status, 403);
    assert.equal(res.headers.get('cache-control'), 'no-store');
    await res.body.cancel();
  }
  assert.equal(requests.length, before);
});

test('private navigation exchanges a key for a clean HTTPS-secure cookie', async () => {
  const res = await fetch(origin + '/?k=' + token, {
    redirect: 'manual', headers: { 'x-forwarded-proto': 'https' },
  });
  assert.equal(res.status, 302);
  assert.equal(res.headers.get('location'), '/');
  const setCookie = res.headers.get('set-cookie');
  assert.match(setCookie, /HttpOnly/);
  assert.match(setCookie, /SameSite=Lax/);
  assert.match(setCookie, /; Secure/);
  cookie = setCookie.split(';')[0];
  await res.body.cancel();
  const page = await fetch(origin, { headers: { Cookie: cookie } });
  assert.equal(page.status, 200);
  assert.equal((await page.json()).fixture, true);
});

test('wrong keys and cookies are rejected; bearer auth is supported', async () => {
  for (const options of [{}, { headers: { Cookie: 'native_sim_k=wrong' } }, { headers: { Authorization: 'Bearer wrong' } }]) {
    const res = await fetch(origin + '/?k=wrong', options);
    assert.equal(res.status, 403);
    await res.body.cancel();
  }
  const res = await fetch(origin + '/api', { headers: { Authorization: `Bearer ${token}` } });
  assert.equal(res.status, 200);
  await res.body.cancel();
});

test('MJPEG chunks stream through a live response without buffering to EOF', async () => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 3000);
  try {
    const res = await fetch(origin + '/helper/device/stream.mjpeg', { headers: { Cookie: cookie }, signal: controller.signal });
    assert.equal(res.status, 200);
    const reader = res.body.getReader();
    let bytes = Buffer.alloc(0);
    while (!bytes.includes(Buffer.from([0xff, 0xd9]))) {
      const result = await reader.read();
      assert.equal(result.done, false);
      bytes = Buffer.concat([bytes, Buffer.from(result.value)]);
    }
    assert.ok(bytes.includes(Buffer.from([0xff, 0xd8])));
    await reader.cancel();
  } finally { clearTimeout(timer); controller.abort(); }
});

function upgrade(route, headers = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request(origin + route, { headers: {
      Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Version': '13',
      'Sec-WebSocket-Key': randomBytes(16).toString('base64'), ...headers,
    } });
    req.on('error', reject);
    req.on('response', res => { res.resume(); resolve({ status: res.statusCode }); });
    req.on('upgrade', (res, socket, head) => { track(socket); resolve({ status: res.statusCode, socket, head }); });
    req.end();
  });
}

test('unauthenticated WebSocket and query-token upgrades cannot reach controls', async () => {
  const before = requests.length;
  for (const route of ['/helper/device/ws', `/helper/device/ws?k=${token}`, '/exec-ws']) {
    assert.equal((await upgrade(route)).status, 403);
  }
  assert.equal(requests.length, before);
});

test('authenticated browser WebSocket upgrades and bidirectional bytes are forwarded', async () => {
  const result = await upgrade('/helper/device/ws', {
    Cookie: cookie, Origin: 'https://fixture.trycloudflare.com',
    Host: 'fixture.trycloudflare.com', 'x-forwarded-proto': 'https',
  });
  assert.equal(result.status, 101);
  const payload = Buffer.from('opaque input fixture');
  const data = once(result.socket, 'data');
  result.socket.write(payload);
  assert.deepEqual((await data)[0], payload);
  const observed = requests.at(-1);
  assert.equal(observed.host, 'fixture.trycloudflare.com');
  assert.equal(observed.proto, 'https');
  result.socket.destroy();
});

test('HTTP forwarding preserves public host and HTTPS scheme', async () => {
  // Fetch owns Host; use node:http to emulate cloudflared's wire-level header.
  await new Promise((resolve, reject) => {
    const req = http.get(origin + '/api', { headers: {
      Cookie: cookie, Host: 'fixture.trycloudflare.com', 'x-forwarded-proto': 'https',
    } }, res => { res.resume(); res.on('end', resolve); });
    req.on('error', reject);
  });
  assert.equal(requests.at(-1).host, 'fixture.trycloudflare.com');
  assert.equal(requests.at(-1).proto, 'https');
});
