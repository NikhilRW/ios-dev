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
APP="$ROOT/build/DerivedData/Build/Products/Debug-iphonesimulator/HelloIOS.app"
[[ -d "$APP" ]] || { echo 'HelloIOS.app is missing. Run bash scripts/build.sh first.' >&2; exit 1; }
# Query the selected guest, not host processes. Real query/termination errors fail.
xcrun simctl spawn "$SIMULATOR_UDID" launchctl list > .dev-session/guest-processes.txt
if awk '$1 ~ /^[0-9]+$/ && index($3, "UIKitApplication:com.nikhil.helloios[") == 1 { found=1 } END { exit !found }' .dev-session/guest-processes.txt; then
  xcrun simctl terminate "$SIMULATOR_UDID" com.nikhil.helloios
fi
xcrun simctl install "$SIMULATOR_UDID" "$APP"
xcrun simctl launch "$SIMULATOR_UDID" com.nikhil.helloios
