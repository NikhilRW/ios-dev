#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
umask 077
[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  echo 'This session requires an Apple Silicon macOS runner (macos-26).' >&2; exit 1;
}
[[ "$(node --version)" == v24.22.1 ]] || {
  echo 'Configure Node 24.22.1 with setup-node before bootstrapping.' >&2; exit 1;
}
: "${RUNNER_TEMP:?RUNNER_TEMP must name the runner temporary directory}"
mkdir -p .dev-session "$RUNNER_TEMP/helloios-tools"
TOOLS="$RUNNER_TEMP/helloios-tools"
mkdir -p "$TOOLS/bin" "$TOOLS/preview"
curl -fLsS --retry 3 --connect-timeout 15 --max-time 180 \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip \
  -o "$TOOLS/xcodegen.zip"
printf '%s  %s\n' 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806 "$TOOLS/xcodegen.zip" | shasum -a 256 -c -
unzip -qo "$TOOLS/xcodegen.zip" -d "$TOOLS"
curl -fLsS --retry 3 --connect-timeout 15 --max-time 180 \
  https://github.com/cloudflare/cloudflared/releases/download/2026.10.3/cloudflared-darwin-arm64.tgz \
  -o "$TOOLS/cloudflared.tgz"
printf '%s  %s\n' 1165d14b6f6360a3b8c283d7d1100024d6ec7cd9bc9e32519e96150645f3ec55 "$TOOLS/cloudflared.tgz" | shasum -a 256 -c -
tar -xzf "$TOOLS/cloudflared.tgz" -C "$TOOLS/bin" cloudflared
chmod +x "$TOOLS/bin/cloudflared" "$TOOLS/xcodegen/bin/xcodegen"
# Explicitly versioned host-only install; no Expo/RN app dependencies.
npm install --prefix "$TOOLS/preview" --save-exact --omit=dev --no-audit --no-fund @expo/serve-sim@0.10.3
NODE_BIN="$(dirname "$(command -v node)")"
{
  # Keep $PATH literal so independent remote shells retain their own base PATH.
  # shellcheck disable=SC2016
  printf 'export PATH=%q:%q:%q:"$PATH"\n' "$NODE_BIN" "$TOOLS/bin" "$TOOLS/xcodegen/bin"
  printf 'SERVE_SIM_CLI=%q\n' "$TOOLS/preview/node_modules/@expo/serve-sim/dist/serve-sim.js"
  printf 'CLOUDFLARED=%q\n' "$TOOLS/bin/cloudflared"
} > .dev-session/tools.env
"$TOOLS/xcodegen/bin/xcodegen" --version
"$TOOLS/bin/cloudflared" --version
node "$TOOLS/preview/node_modules/@expo/serve-sim/dist/serve-sim.js" --version
echo 'Pinned host tools installed. No application compilation performed.'
