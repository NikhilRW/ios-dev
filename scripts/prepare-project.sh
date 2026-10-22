#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f .dev-session/tools.env ]] || { echo 'Run bootstrap-tools.sh first.' >&2; exit 1; }
# shellcheck disable=SC1091
source .dev-session/tools.env
xcodegen generate --spec "$ROOT/project.yml"
xcodebuild -list -json -project "$ROOT/HelloIOS.xcodeproj" > .dev-session/project.json
node <<'NODE'
const fs = require('node:fs');
const p = JSON.parse(fs.readFileSync('.dev-session/project.json', 'utf8')).project;
if (!p?.schemes?.includes('HelloIOS') || !p?.targets?.includes('HelloIOS')) {
  console.error('Generated project must expose HelloIOS target and shared scheme.');
  process.exit(1);
}
console.log('HelloIOS target and scheme verified (inspection only).');
NODE
