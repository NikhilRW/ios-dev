#!/bin/bash
set +x
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -t 0 && -t 1 ]] || { echo 'Run preview-url.sh only in the interactive SSH terminal.' >&2; exit 1; }
[[ -f .dev-session/tools.env && -f .dev-session/simulator.env && -f .dev-session/private-dir.txt ]] || {
  echo 'Preview session state is missing. Check status.sh.' >&2; exit 1;
}
# shellcheck disable=SC1091
source .dev-session/tools.env
# shellcheck disable=SC1091
source .dev-session/simulator.env
node - "$SIMULATOR_UDID" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
try {
  const udid = process.argv[2];
  const dir = fs.readFileSync('.dev-session/private-dir.txt', 'utf8').trim();
  const state = JSON.parse(fs.readFileSync(path.join(dir, 'gate-session.json'), 'utf8'));
  const services = JSON.parse(fs.readFileSync('.dev-session/services.json', 'utf8'));
  const url = fs.readFileSync('.dev-session/tunnel-url.txt', 'utf8').trim();
  if (!/^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(url) || !/^[A-Za-z0-9_-]{43}$/.test(state.token) || state.device !== udid || state.previewPid !== services.preview.pid || state.gatePid !== services.gate.pid) throw new Error();
  process.kill(state.previewPid, 0);
  process.kill(state.gatePid, 0);
  process.kill(services.tunnel.pid, 0);
  console.log(`${url}/?k=${encodeURIComponent(state.token)}`);
} catch {
  console.error('Cannot read a live authenticated preview session. Run bash scripts/status.sh.');
  process.exitCode = 1;
}
NODE
