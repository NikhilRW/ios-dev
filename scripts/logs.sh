#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f .dev-session/tools.env && -f .dev-session/simulator.env ]] || {
  echo 'Prepare the tools and boot a simulator first.' >&2; exit 1;
}
# shellcheck disable=SC1091
source .dev-session/tools.env
# shellcheck disable=SC1091
source .dev-session/simulator.env
echo 'Streaming HelloIOS unified logs. Press Ctrl-C to return to the shell.'
xcrun simctl spawn "$SIMULATOR_UDID" log stream --style compact --level debug \
  --predicate 'process == "HelloIOS" OR subsystem BEGINSWITH "com.nikhil.helloios"'
