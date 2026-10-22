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
[[ -d HelloIOS.xcodeproj ]] || { echo 'Run bash scripts/prepare-project.sh first.' >&2; exit 1; }
mkdir -p build
xcodebuild \
  -project "$ROOT/HelloIOS.xcodeproj" \
  -scheme HelloIOS \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
  -derivedDataPath "$ROOT/build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "$ROOT/build/latest-build.log"
