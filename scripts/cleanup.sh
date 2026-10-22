#!/bin/bash
set +x
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 0
[[ -f .dev-session/tools.env ]] || exit 0
# shellcheck disable=SC1091
source .dev-session/tools.env
node <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const { execFileSync } = require('node:child_process');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
(async () => {
  let records = {};
  try { records = JSON.parse(fs.readFileSync('.dev-session/services.json', 'utf8')); } catch {}
  const owned = Object.values(records).filter(r => {
    if (!Number.isSafeInteger(r.pid) || r.pid <= 1 || typeof r.command !== 'string') return false;
    try { return execFileSync('/bin/ps', ['-p', String(r.pid), '-o', 'command='], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).includes(r.command); }
    catch { return false; }
  });
  for (const r of owned) { try { process.kill(-r.pid, 'SIGTERM'); } catch {} }
  const end = Date.now() + 22000;
  const alive = r => { try { process.kill(r.pid, 0); return true; } catch { return false; } };
  while (owned.some(alive) && Date.now() < end) await sleep(250);
  for (const r of owned.filter(alive)) { try { process.kill(-r.pid, 'SIGKILL'); } catch {} }
  // Only remove this session's randomly named private directory under RUNNER_TEMP.
  try {
    const dir = fs.readFileSync('.dev-session/private-dir.txt', 'utf8').trim();
    const parent = fs.realpathSync(process.env.RUNNER_TEMP || os.tmpdir());
    if (path.dirname(fs.realpathSync(dir)) === parent && /^helloios-preview\.[A-Za-z0-9]+$/.test(path.basename(dir))) {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  } catch {}
  for (const file of ['services.json', 'private-dir.txt', 'tunnel-url.txt']) {
    try { fs.unlinkSync(path.join('.dev-session', file)); } catch {}
  }
  console.log('Best-effort preview/tunnel cleanup complete.');
})().catch(() => { console.error('Cleanup incomplete; runner disposal is the final cleanup boundary.'); });
NODE
exit 0
