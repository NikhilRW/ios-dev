#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f .dev-session/tools.env ]] || { echo 'Run bootstrap-tools.sh first.' >&2; exit 1; }
# shellcheck disable=SC1091
source .dev-session/tools.env
xcrun simctl list devices available --json > .dev-session/devices.json
node <<'NODE'
const fs = require('node:fs');
const devices = JSON.parse(fs.readFileSync('.dev-session/devices.json', 'utf8')).devices;
const candidates = Object.entries(devices).flatMap(([runtime, list]) => {
  const version = runtime.match(/SimRuntime\.iOS-(\d+(?:-\d+)*)$/)?.[1];
  if (!version || Number(version.split('-')[0]) < 17) return [];
  return list.filter(d => d.isAvailable !== false && /^iPhone\b/.test(d.name))
    .map(d => ({ ...d, runtime, version: version.split('-').map(Number) }));
});
candidates.sort((a, b) => {
  const regular = d => /fold|duo/i.test(d.name + ' ' + (d.deviceTypeIdentifier || '')) ? 1 : 0;
  if (regular(a) !== regular(b)) return regular(a) - regular(b);
  for (let i = 0; i < 3; i++) {
    const diff = (b.version[i] || 0) - (a.version[i] || 0);
    if (diff) return diff;
  }
  return a.name.localeCompare(b.name, 'en') || a.udid.localeCompare(b.udid, 'en');
});
let chosen = candidates[0];
// Reruns retain the selected device, even if another device has since booted.
if (fs.existsSync('.dev-session/simulator.json')) {
  const old = JSON.parse(fs.readFileSync('.dev-session/simulator.json', 'utf8'));
  chosen = candidates.find(d => d.udid === old.udid);
}
if (!chosen || !/^[A-F0-9-]{36}$/i.test(chosen.udid)) {
  console.error('No available selected iPhone on an installed iOS >=17 runtime. Inspect xcrun simctl list; no runtime is downloaded automatically.');
  process.exit(1);
}
fs.writeFileSync('.dev-session/simulator.json', JSON.stringify(chosen, null, 2));
console.log(`Selected ${chosen.name}: ${chosen.udid} (${chosen.runtime})`);
NODE
SIMULATOR_UDID="$(node -p "require('./.dev-session/simulator.json').udid")"
printf 'SIMULATOR_UDID=%q\n' "$SIMULATOR_UDID" > .dev-session/simulator.env
if [[ "$(node -p "require('./.dev-session/simulator.json').state")" != Booted ]]; then
  xcrun simctl boot "$SIMULATOR_UDID"
fi
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
