#!/bin/bash
set +x
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f .dev-session/tools.env ]] || { echo 'No prepared session in this checkout.' >&2; exit 1; }
# shellcheck disable=SC1091
source .dev-session/tools.env
node <<'NODE'
const fs = require('node:fs');
const read = file => fs.existsSync(file) ? fs.readFileSync(file, 'utf8').trim() : null;
const start = Number(read('.dev-session/start-epoch.txt'));
if (start) {
  const elapsed = Math.floor(Date.now() / 1000) - start;
  console.log(`Elapsed since first workflow step: ${Math.floor(elapsed / 60)}m ${elapsed % 60}s`);
  console.log(`Approximate time left: ${Math.max(0, 300 - Math.ceil(elapsed / 60))}m (GitHub's job clock is authoritative; includes checkout/setup).`);
}
const sim = read('.dev-session/simulator.json');
if (sim) { const s = JSON.parse(sim); console.log(`Simulator: ${s.name} | ${s.udid} | ${s.runtime}`); }
const services = JSON.parse(read('.dev-session/services.json') || '{}');
for (const [name, r] of Object.entries(services)) {
  let alive = true; try { process.kill(r.pid, 0); } catch { alive = false; }
  console.log(`${name}: ${alive ? 'running' : 'stopped'} (PID ${r.pid})`);
}
console.log('Bare preview URL:', read('.dev-session/tunnel-url.txt') || 'not assigned');
console.log('Authenticated URL: run bash scripts/preview-url.sh in SSH.');
NODE
if [[ -f .dev-session/simulator.env ]]; then
  # shellcheck disable=SC1091
  source .dev-session/simulator.env
  xcrun simctl list devices available --json | node -e '
    const fs = require("node:fs"); const id = process.argv[1];
    const all = Object.values(JSON.parse(fs.readFileSync(0, "utf8")).devices).flat();
    console.log("Current simulator state:", all.find(d => d.udid === id)?.state || "unavailable");
  ' "$SIMULATOR_UDID"
fi
if curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:3200/readyz -o /dev/null 2>/dev/null; then
  echo 'Capture readiness: ready'
else
  echo 'Capture readiness: unavailable'
fi
if curl -fsS --connect-timeout 2 --max-time 5 http://127.0.0.1:3199/__native-sim/healthz -o /dev/null 2>/dev/null; then
  echo 'Local native-sim auth gate: running'
else
  echo 'Local native-sim auth gate: unavailable'
fi
if [[ -f .dev-session/tunnel-url.txt ]]; then
  IFS= read -r TUNNEL_URL < .dev-session/tunnel-url.txt
  if [[ "$TUNNEL_URL" =~ ^https://[a-z0-9-]+\.trycloudflare\.com$ ]] && \
    curl -fsS --connect-timeout 3 --max-time 8 "$TUNNEL_URL/__native-sim/healthz" -o /dev/null 2>/dev/null; then
    echo 'HTTPS tunnel/gate liveness: ready (capture readiness is reported separately)'
  else
    echo 'HTTPS tunnel/gate liveness: unavailable'
  fi
fi
