// Adapted from native-sim@0.2.2, templates/gate.cjs (template version 18).
// Upstream: https://github.com/bidah/native-sim — Rodrigo Figueroa.
// Published package SHA-1: b496a3a8938f44f18607259162f1bd64b1c74b32.
// Changes: no agent-device route; private runner-generated token; exact health
// path; secure HTTPS cookie; no-store responses; clean redirects; socket cleanup.
// SPDX-License-Identifier: MIT
/*
Copyright (c) Rodrigo Figueroa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/
const http = require('node:http');
const net = require('node:net');
const { timingSafeEqual } = require('node:crypto');

const TOKEN = process.env.NATIVE_SIM_GATE_TOKEN || '';
const TARGET_PORT = Number(process.env.NATIVE_SIM_TARGET_PORT || 3200);
const PORT = Number(process.env.NATIVE_SIM_GATE_PORT || 3199);
const COOKIE = 'native_sim_k';

if (!/^[A-Za-z0-9_-]{43}$/.test(TOKEN) ||
    ![PORT, TARGET_PORT].every(p => Number.isInteger(p) && p > 0 && p <= 65535) || PORT === TARGET_PORT) {
  console.error('A fresh 32-byte base64url NATIVE_SIM_GATE_TOKEN and distinct valid loopback ports are required.');
  process.exit(1);
}

function matches(value) {
  if (typeof value !== 'string') return false;
  const bytes = Buffer.from(value);
  const expected = Buffer.from(TOKEN);
  return bytes.length === expected.length && timingSafeEqual(bytes, expected);
}

function authorize(req, allowQuery = true) {
  for (const part of (req.headers.cookie || '').split(';')) {
    const [name, ...value] = part.trim().split('=');
    if (name === COOKIE && matches(value.join('='))) return 'cookie';
  }
  const bearer = /^Bearer\s+(.+)$/i.exec(req.headers.authorization || '');
  if (bearer && matches(bearer[1])) return 'bearer';
  const url = new URL(req.url, 'http://localhost');
  if (allowQuery && matches(url.searchParams.get('k'))) return 'query';
  return false;
}

const DENIED = '<!doctype html><meta charset="utf-8"><title>native-sim</title>' +
  '<h1>Authentication required</h1><p>Connect through SSH and run ' +
  '<code>bash scripts/preview-url.sh</code> for this session\'s private link.</p>';

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/__native-sim/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ ok: true, target: TARGET_PORT }));
    return;
  }
  const auth = authorize(req);
  if (!auth) {
    res.writeHead(403, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(DENIED);
    return;
  }
  if (auth === 'query') {
    url.searchParams.delete('k');
    const https = String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim() === 'https';
    res.writeHead(302, {
      'Set-Cookie': `${COOKIE}=${TOKEN}; Path=/; HttpOnly; SameSite=Lax${https ? '; Secure' : ''}`,
      Location: url.pathname.replace(/^\/+/, '/') + url.search,
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
    });
    res.end();
    return;
  }
  const upstream = http.request({
    host: '127.0.0.1', port: TARGET_PORT, method: req.method, path: req.url,
    // Preserve the public Host so serve-sim advertises same-origin video/input
    // URLs. Cloudflared supplies x-forwarded-proto; local probes use HTTP.
    headers: { ...req.headers, 'x-forwarded-host': req.headers.host },
  }, upRes => {
    res.writeHead(upRes.statusCode || 502, { ...upRes.headers, 'cache-control': 'no-store' });
    upRes.pipe(res);
  });
  upstream.on('error', () => {
    if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
    res.end('Simulator preview upstream is unavailable.');
  });
  res.on('close', () => upstream.destroy());
  req.on('error', () => upstream.destroy());
  req.pipe(upstream);
});

server.on('upgrade', (req, socket, head) => {
  // Browsers send the gate cookie; probes can send its bearer token. Never
  // put the gate token in a WebSocket query string.
  if (!authorize(req, false)) {
    socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
    return;
  }
  const upstream = net.connect(TARGET_PORT, '127.0.0.1', () => {
    const forwarded = { ...req.headers, 'x-forwarded-host': req.headers.host };
    const headers = Object.entries(forwarded).flatMap(([name, value]) =>
      (Array.isArray(value) ? value : [value]).map(v => `${name}: ${v}`)
    ).join('\r\n');
    upstream.write(`${req.method} ${req.url} HTTP/1.1\r\n${headers}\r\n\r\n`);
    if (head.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  const drop = () => { socket.destroy(); upstream.destroy(); };
  upstream.on('error', drop);
  socket.on('error', drop);
  upstream.on('close', () => socket.destroy());
  socket.on('close', () => upstream.destroy());
});

// MJPEG is long-lived. Do not impose a whole-request/socket timeout.
server.requestTimeout = 0;
server.timeout = 0;
server.listen(PORT, '127.0.0.1', () => {
  console.log(`native-sim auth gate on 127.0.0.1:${PORT} -> 127.0.0.1:${TARGET_PORT}`);
});
