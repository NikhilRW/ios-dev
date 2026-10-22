# HelloIOS — SwiftUI development from a PC

A minimal native SwiftUI app (`Hello, world!`) and a manually started, temporary
GitHub-hosted Mac development session. Edit Swift in the Mac's terminal, then
build/install/relaunch explicitly. The browser shows the **iOS Simulator**, initially
its Home screen, rather than the macOS desktop.

```text
Windows OpenSSH → Upterm relay → macos-26 arm64 runner → terminal + Xcode/simctl
Windows browser → HTTPS Quick Tunnel → native-sim auth gate → serve-sim → simulator
```

There is no Xcode Canvas preview or live Swift reload. A Swift edit appears after
another build and launch. Node is a host-side preview dependency; the app uses
SwiftUI only. No Apple Developer membership, signing certificate, provisioning
profile, or development team is needed for this simulator-only build.

The workflow adapts the published **native-sim 0.2.2** template for SwiftUI. Its
auth gate is vendored in `.github/native-sim/gate.cjs`; no native-sim CLI commands
are needed to run the session. This replaces the earlier built-in serve-sim
authentication approach with the user-approved native-sim gate.

## 1. GitHub and PC prerequisites

- A **public** GitHub repository and permission to run its workflows. Enable
  GitHub Actions, including the pinned checkout, setup-node, and Upterm actions
  if your organization restricts third-party actions.
- Put `.github/workflows/ios-dev-session.yml` on the repository's **default
  branch** so **Run workflow** is available.
- Register your **public SSH authentication key** in GitHub → Settings → SSH
  and GPG keys. Its matching **private key stays on your PC**. Do not upload it
  to this repository or Actions secrets. A signing-only key is not sufficient.
- Windows OpenSSH (`ssh -V` in PowerShell), a browser, and Git for publishing
  and recovering edits. Neither Xcode nor Node is required on the PC.
- No Cloudflare account, domain, tunnel credential, preview secret, or additional
  paid service is required. Public standard runners are used, not larger runners.

If you need a new PC key (omit this command if you already have a suitable one):

```powershell
ssh-keygen -t ed25519 -C "your-email@example.com"
Get-Content "$HOME/.ssh/id_ed25519.pub"
```

Add the printed `.pub` text as an **Authentication Key** in GitHub. Keep the
private file `id_ed25519` local. Registered public keys can be checked at
`https://github.com/YOUR_USERNAME.keys`.

### Publish the files yourself

Create an empty public repository on GitHub. In this local folder, these are
instructions to execute yourself after reviewing the files:

```powershell
git init
git add .
git diff --cached
git commit -m "Add SwiftUI remote development session"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
git push -u origin main
```

If Git/remote configuration already exists, use that configuration rather than
adding a duplicate remote. Repository creation, commit, push, and workflow dispatch
were not performed during implementation.

## 2. Start a session and connect from Windows

1. Open **Actions → iOS development session → Run workflow**, select your branch,
   and run it.
2. Follow the **live step logs**. Setup validates arm64, the image's selected
   Xcode, an installed iOS runtime, and GitHub SSH keys. It installs pinned tools,
   generates the project, boots one iPhone, and starts the authenticated preview.
   It does **not** compile, install, or launch HelloIOS.
3. Wait for **native-sim preview ready** and the **SSH command** in **Interactive Upterm
   session**. The bare preview hostname can be public; it does not authorize a
   viewer. The job summary is a convenience; live logs are the connection source.
4. Paste the **exact `ssh ...` command** printed by Upterm into PowerShell.
   Upterm also prints an `upterm join ...` command; Windows native OpenSSH uses
   the `ssh` form and needs no Upterm installation.

If your matching key is not selected automatically, insert these options immediately
after `ssh`, preserving **every other part** of the supplied command:

```powershell
# Shape only — replace the placeholder with the destination from THIS run's logs.
ssh -i "$HOME/.ssh/id_ed25519" -o IdentitiesOnly=yes <EXACT-UPTERM-DESTINATION-AND-OPTIONS>
```

Preserve the supplied hostname, session/user identifier, port, and any proxy
options. Do not replace the relay destination with `github.com`, or reuse a
previous run's command. The default relay is `ssh://uptermd.upterm.dev:22`.
Its host verification is bundled and retained by the action. Keep normal SSH
host-key verification enabled on the PC as well.

Authorization is explicitly `limit-access-to-actor: true`. With pinned action
**v2.7.0**, a re-run also authorizes the person who clicked **Re-run jobs**, using
that account's registered GitHub SSH keys. Setup validates both original and
re-running actors. No unrelated account is intentionally authorized.

## 3. Open the private preview; build and edit

In the remote SSH terminal:

```bash
cd "$GITHUB_WORKSPACE"
bash scripts/preview-url.sh
```

Open the printed **private navigation URL** on your PC. Initially you should see
the simulator Home screen. `/?k=...` exchanges the gate session token for a cookie
and redirects to a clean URL. The link grants simulator control and access to
serve-sim's authenticated host actions: keep the full link private. A fresh token
and tunnel hostname are created for each preview start.

`preview-url.sh` refuses noninteractive stdout/stdin. Run it in SSH, never in an
Actions step or a public log capture. A terminal recording or transcript can still
record its output, so treat such recordings as private.

Now explicitly build and run:

```bash
bash scripts/build-run.sh
```

After a successful build, **Hello, world!** appears in the same browser session.
Change the greeting and repeat:

```bash
nano HelloIOS/ContentView.swift
# Change Text("Hello, world!") to your greeting; save and close nano.
bash scripts/build-run.sh
```

`vi HelloIOS/ContentView.swift` also works. Build products reuse `build/DerivedData`
throughout this session. A failed compilation returns nonzero, does not run the
install/relaunch step, and leaves the existing app and preview running.

### Helper reference

Run scripts with `bash` so a Windows-created executable bit is not required.
Each helper resolves the repository from its own path and loads persisted session
state; a previous shell's exports are not required.

| Command | Purpose |
| --- | --- |
| `bash scripts/prepare-project.sh` | Regenerate after editing `project.yml`; inspect target/shared scheme without building |
| `bash scripts/boot-simulator.sh` | Boot/wait for the persisted simulator; rerunnable |
| `bash scripts/build.sh` | Simulator Debug build, `CODE_SIGNING_ALLOWED=NO`; output retained in `build/latest-build.log` |
| `bash scripts/run.sh` | Check `.app`, terminate the old HelloIOS process if running, install, launch |
| `bash scripts/build-run.sh` | Build, then run only on success |
| `bash scripts/logs.sh` | Stream HelloIOS unified logs; **Ctrl-C** stops the stream and returns to the shell |
| `bash scripts/status.sh` | Simulator identity/current state, PIDs, readiness, elapsed time, bare hostname; no token |
| `bash scripts/preview-url.sh` | Read current native-sim gate token from private JSON state; print only in interactive SSH |
| `bash scripts/cleanup.sh` | Best-effort stop of recorded preview/auth-gate/tunnel process groups; remove private preview state |

To restart a failed preview while SSH is still usable:

```bash
bash scripts/cleanup.sh
bash scripts/start-preview.sh
bash scripts/preview-url.sh
```

The hostname and token change; open the new private link. A failed preview startup
during setup fails the job rather than exposing an ungated preview.

## 4. Save your edits before ending the session

The checkout token has `contents: read` and is not persisted in Git configuration.
Remote edits are **not automatically pushed**. No write credential or automatic
publishing is configured. Ask before adding either.

A terminal-friendly tracked-file backup, run in SSH:

```bash
git status --short
git diff --binary HEAD
git ls-files --others --exclude-standard
```

Copy the **entire** diff to a local UTF-8/LF file such as `session.patch`, without
terminal prompts, wrapping changes, or transcript escape codes. Binary changes use
Git's encoded patch format. On the PC, in a checkout of the **same starting
commit**, validate and apply:

```powershell
git apply --check .\session.patch
git apply .\session.patch
git status --short
```

**`git diff --binary HEAD` omits untracked files.** Use the `git ls-files` list to
copy new files separately to the PC, preserving paths and contents. For a small
new text file, print it in SSH and save the text locally. For binary or many new
files, in SSH create an archive containing only those explicitly chosen source
paths and print it as base64:

```bash
tar -czf "$RUNNER_TEMP/new-source.tgz" HelloIOS/NewView.swift path/to/new-asset.png
base64 < "$RUNNER_TEMP/new-source.tgz"
```

Substitute actual existing new source files. Copy the complete base64 output into
local `new-source.base64`, then in PowerShell:

```powershell
$encoded = Get-Content -Raw .\new-source.base64
[IO.File]::WriteAllBytes("$PWD\new-source.tgz", [Convert]::FromBase64String($encoded))
tar -tzf .\new-source.tgz
tar -xzf .\new-source.tgz
```

Inspect the archive listing and recovered files. Do not include `.dev-session`,
private runner state, tools, or credentials. Confirm the patch **and** new files
are safely local before exiting. Publishing recovered changes remains your choice.

## 5. Lifetime, concurrency, disconnects, and cleanup

- The job has **`timeout-minutes: 300`**: five hours **total**, starting when the
  job executes. Time in GitHub's queue is excluded; checkout, downloads, simulator
  boot, preview setup, SSH use, and manual builds all consume the same budget.
  `status.sh` estimates elapsed time from the first step; GitHub's job clock is
  authoritative and starts slightly earlier.
- One repository-scoped concurrency group allows one active session. A second
  run queues; cancel the active run to make room. GitHub concurrency allows only
  one pending run by default, so additional submissions can replace the pending
  run. There is no automatic cancellation of the active run.
- Attached-mode Upterm is the final long-running regular step. Its
  `wait-timeout-minutes: 0` disables the **wait-for-first-guest** timeout, not the
  job's 300-minute limit. There is no extra five-hour sleep or post-job wait.
- To stop early, use GitHub **Cancel workflow**, or type **`exit`** / **Ctrl-D**
  in the hosted shell. Exiting ends Upterm and lets cleanup run.
- Closing the PC SSH terminal, losing the client network, or using OpenSSH's
  **Enter, `~.`** escape disconnects the client without exiting the hosted shell.
  Per pinned Upterm documentation, reconnect using the same command while the
  session/job is alive. A host-to-relay outage is different: inspect the live
  action status; a terminal/disconnected session may require a new run.
- Normal completion runs best-effort cleanup. Hard timeout/abrupt cancellation
  may prevent cleanup; GitHub runner disposal is the ultimate boundary.
- The VM, simulator state, build products, and source changes that you have not
  backed up disappear when the job ends. Startup failures and relay/service
  outages can make the session end or become unusable sooner.

## Implementation and pinned interfaces

| Component | Pin / behavior |
| --- | --- |
| Runner | Standard `macos-26`; runner-images currently maps it to **arm64**; runtime `uname -m` check refuses anything else |
| Xcode / iOS runtime | Image's selected installed Xcode; choose an available iOS >=17 iPhone; no runtime download |
| Node LTS | **24.22.1** (Krypton) |
| XcodeGen | **2.46.0**, release ZIP SHA-256 verified |
| cloudflared | **2026.10.3**, Darwin arm64 archive SHA-256 verified |
| Standalone preview | **`@expo/serve-sim@0.10.3`**, explicit exact npm install; runtime dependencies resolved by npm and its generated runner-local lockfile |
| native-sim integration | **0.2.2**, adapted workflow template **v24** and vendored auth gate template **v18**; published npm package SHA-1 `b496a3a8938f44f18607259162f1bd64b1c74b32` |
| Upterm | **v0.39.0**, action minimum >=v0.32.0 |
| `actions/checkout` | **v6.1.0**, `d23441a48e516b6c34aea4fa41551a30e30af803` |
| `actions/setup-node` | **v6.5.0**, `249970729cb0ef3589644e2896645e5dc5ba9c38` |
| `owenthereal/action-upterm` | **v2.7.0**, `b9dfa526f890bbd5162d781f8d9c69b97731d73d` |

Tool installation uses release binaries, not a Homebrew latest-version install.
XcodeGen's full release tree is retained so its setting presets remain available.
Generated `HelloIOS.xcodeproj` is disposable. App target, product, and shared
scheme are `HelloIOS`; bundle ID is `com.nikhil.helloios`; minimum iOS is 17.0.
Info.plist, scene and launch-screen metadata are generated by Xcode settings.

Simulator selection is deterministic: prefer non-foldable iPhones, then newest
installed compatible iOS runtime, then name and UDID. Subsequent helper calls
reuse the saved UDID for capture, build destination, install, launch, and logs.

### How native-sim is adapted

The published native-sim CLI validates Expo/React Native projects and its `up`
command can commit, push, and dispatch. This SwiftUI repository uses its generated
workflow pattern and bundled gate directly, rather than running `native-sim up`.
The relevant adaptations are:

- XcodeGen preparation and the existing manual `build-run.sh` replace automatic
  Expo/RN builds, installation, and launch.
- Attached Upterm replaces native-sim's post-build hold loop; the job cap is
  **300 minutes total**, with no additional timer.
- Tokens are minted privately on the runner rather than supplied as a workflow
  dispatch input. Full private links are delivered only through SSH, never as an
  Actions output or commit status. Permissions remain `contents: read`.
- Host tools/actions keep their concrete pins rather than native-sim's moving
  `latest` installs. The native-sim CLI's optional agent-device, TURN, R2, build
  cache, and JavaScript tooling are not required for this SwiftUI session.
- The vendored MIT gate retains upstream attribution. Its local adjustments
  remove agent-device routing, use Secure cookies over HTTPS, disable response
  caching, restrict the public health path, and clean up proxied sockets.

Do not run `native-sim init --force` over these customized files; use the workflow
already in this repository.

### Preview authentication and private state

- `serve-sim` is bound to **127.0.0.1:3200**, with HTTP/MJPEG,
  30 fps, quality 0.7, max dimension 900. Clipboard startup capability is disabled
  because this minimal app does not need it. The Share button is hidden.
- The **native-sim gate** listens on **127.0.0.1:3199** and protects every preview,
  API, streaming, and input request. Cloudflared exposes **3199**, not 3200.
  Serve-sim's `--require-token` is replaced by this gate; its
  `--allow-any-host-when-insecure` permits the forwarded tunnel Host behind the
  authenticated gate. Both listeners remain loopback-only.
- The normal foreground preview, gate, and tunnel run in detached process groups
  with redirected descriptors and `unref()`. Foreground serve-sim preserves its
  capture/host options, following native-sim's template approach.
- Nonsecret configuration/PIDs/start time live in gitignored `.dev-session/`.
  Pinned tool paths are persisted in `tools.env`, so SSH shells work independently.
- A randomly named mode-**700** directory under `$RUNNER_TEMP` holds stdout,
  stderr, probe failure diagnostics, `gate-session.json`, and `SERVE_SIM_STATE_DIR`. The pointer in
  `.dev-session/private-dir.txt` is nonsecret. It is not the token.
- Startup creates a fresh 32-byte base64url gate token and supplies it only to the
  gate child process through `NATIVE_SIM_GATE_TOKEN`. The private mode-**600**
  `gate-session.json` records `token`, `device`, `previewPid`, and `gatePid`.
  `preview-url.sh` validates these fields against the live service PIDs and emits
  `https://<tunnel>/?k=<token>` only in the user's interactive SSH terminal.
  Serve-sim's own internal state/log output also stays private.
- Startup waits for serve-sim's loopback **`/readyz`**, then the gate's local
  liveness endpoint, before opening the tunnel. It waits for the assigned hostname
  and external gate liveness, and verifies real authenticated JPEG delivery and
  WebSocket admission. All waits are bounded. It checks unauthenticated page/API/MJPEG rejection, the navigation
  cookie exchange, a complete JPEG, unauthenticated HID rejection, and authenticated
  WebSocket admission both locally and through HTTPS. No simulated taps or app
  launch are performed during those checks.
- The gate returns explicit HTTP **403** on an unauthenticated WebSocket upgrade;
  the separate cookie-authenticated probe must receive input admission. Connection
  resets, timeouts, unexpected closes, and unauthenticated input data fail
  startup. Public failure output identifies the individual check without printing
  tokens, cookies, response bodies, or raw upstream exceptions.
- serve-sim keeps helper URLs same-origin and honors the forwarded HTTPS scheme;
  the gate preserves Host and cloudflared's forwarded scheme for HTTP and WebSocket
  upgrades. No wildcard CORS permission is added.
- Only **`/__native-sim/healthz`** is public through the gate, and it indicates
  gate liveness, not video readiness. Even upstream `/healthz` and `/readyz` need
  gate authentication through the public tunnel. Browser navigation exchanges
  `?k=` for the `native_sim_k` HttpOnly/SameSite=Lax cookie (Secure over HTTPS)
  and redirects to a clean URL. The browser sends that cookie on its input socket.
  Bearer authentication is also available to the gate; query tokens are refused
  on WebSocket upgrades. Serve-sim handles its internal host-action token behind
  the gate.
- No token-bearing files, URLs, or output are sent to Actions outputs, artifacts,
  summaries, or public logs. Do not run serve-sim yourself without private output
  redirection, use shell tracing, dump environment/private state, or publish the
  startup logs.

**Quick Tunnel limitation:** Cloudflare documents no SSE support, no uptime
guarantee, and a 200 in-flight-request limit. serve-sim uses MJPEG for video and
WebSockets for input here; its auxiliary SSE metrics/event/log panels may not work
through a Quick Tunnel. `logs.sh` uses the SSH terminal instead. Actual browser
video and input must still be checked on the real runner. No known documented
authentication incompatibility blocks this architecture; hosted native capture
compatibility and external relay/tunnel availability remain runtime checks.

## Troubleshooting

| Symptom | Targeted check |
| --- | --- |
| No usable GitHub keys | Add a public **authentication** key to the triggering account; check its `.keys` URL. A re-run checks both actors. Bot accounts are not suitable. |
| `Permission denied (publickey)` | Use the matching local private key with `-i` and `-o IdentitiesOnly=yes`; retain the exact Upterm destination. `ssh -v` on your PC shows offered identities; inspect locally. An unrelated key should be rejected. |
| Upterm/relay startup fails | Read the action's live diagnostics; check GitHub Releases download access and relay TCP port 22 connectivity. Retry a run after a transient outage. Preserve bundled relay host verification. |
| No simulator runtime/device | Read setup's Xcode/runtime output; inspect `xcrun simctl list runtimes` and `xcrun simctl list devices available`. Check the runner image and selected Xcode. No automatic multi-GB runtime download is attempted. |
| Tunnel DNS/502 immediately after assignment | Allow DNS propagation; startup waits up to 120 seconds. Check `status.sh` in SSH. Retry preview startup if the tunnel died; use the newly minted hostname. |
| Bare URL shows an authentication error | Expected. In SSH run `preview-url.sh` and open its private link; a bare URL is not a credential. |
| Private URL fails or repeatedly redirects | Use the current session link, a top-level browser tab, and allow its cookie. Restarting preview changes the token. Inspect `status.sh`; do not post the full URL or cookie publicly. |
| Video works but input fails | Click the simulator surface, try a Home-screen tap/drag, inspect browser Network WebSocket status locally. It should use `wss://` on the same hostname and authenticate. Try browser reload/current private link and disable interfering browser extensions. US-keyboard input is upstream's supported baseline. |
| Capture or startup probe fails | The workflow deliberately fails closed. If SSH already exists, inspect the private directory from `private-dir.txt` and `startup-error.txt` locally; native capture may be incompatible with the image's Xcode/runtime. Those logs may contain the token; never attach them publicly. During initial setup failure the VM is disposed, so retry and investigate the pinned native tool/image compatibility before changing pins. |
| Old startup reports only `local authentication, JPEG, and input admission checks` | Publish the native-sim gate/workflow/script updates, then start a **new Run workflow** on that updated branch. Re-running an old job uses its old commit. The native-sim gate now handles authentication and returns explicit 403 responses to unauthorized input upgrades. |
| Swift build fails | Inspect `build/latest-build.log`, fix source, and repeat `build-run.sh`. After changing `project.yml`, rerun `prepare-project.sh`. Keep destination on the persisted simulator; signing is disabled for this build. |
| App missing on run | Build first. `run.sh` requires `build/DerivedData/Build/Products/Debug-iphonesimulator/HelloIOS.app`. Installation and launch failures are returned, not hidden. |
| Logs show little output | The static greeting emits few app logs; launch the app first. `Ctrl-C` stops log streaming only. |
| Lost SSH connection | Reuse the same run's SSH command if its shell/job is alive. If the relay session ended, the job timed out, or the hosted shell exited, start a new run and restore backed-up source. |

## Verification results and real-run acceptance

Implementation environment: **Windows**. No workflow was dispatched by the
implementing agent. A user-run earlier session failed during the old local
authentication probes; the native-sim adaptation still needs real-run validation.

| Check | Result |
| --- | --- |
| Minimal SwiftUI entry/view, sources, target, shared scheme, bundle ID, generated Info.plist, orientations, simulator-only build command | **Passed — static review** |
| YAML parser and actionlint 1.7.12 workflow/expression checks | **Passed** |
| Bash syntax and embedded Node JavaScript syntax | **Passed** |
| ShellCheck 0.11.0 / Bash portability review | **Passed**; runtime macOS system Bash verification still required |
| 15 mocked helper-contract checks (paths with spaces, simulator selection/persistence, pipeline failure status, install/launch ordering and error propagation, noninteractive private-link rejection) | **Passed on Windows/Git Bash**; mocks do not prove real Xcode/simulator operation |
| 8 native-sim gate tests over real local HTTP/TCP sockets (denied routes/keys/upgrades, cookie exchange, live streaming, bidirectional WebSocket proxying, forwarded Host/scheme) | **Passed on Windows** using fixture upstreams; run with `node --test --test-timeout=15000 tests/native-sim-gate.test.cjs` |
| Startup probe functions against the vendored gate with a fixture preview | **Passed on Windows**: unauthenticated HTTP/WebSocket rejection, cookie navigation, JPEG delivery, authenticated input admission; real native capture/tunnel still required |
| Published npm 0.10.3 archive, actual `--help` and `--version`, required flags, state/auth source and matching API spec | **Passed**; help/version executed on Windows with native capture unused |
| Runner label architecture, concrete release versions, action commit refs/inputs, attached zero-timeout behavior | **Passed — upstream metadata/source review** |
| Token/public log/output paths and gitignored runtime/generated data | **Passed — static review** |
| XcodeGen generation, `xcodebuild`/simctl, installed runtime/native capture | **Not run — requires macOS/Xcode** |
| SSH allowed-key success / unrelated-key rejection | **Not run — requires authorized workflow dispatch and PC keys** |
| Real local/tunnel authentication, cookie redirect, JPEG delivery and WebSocket admission probes | **Not run — included in runner startup; requires dispatch** |
| Browser visible video, tap/gesture/available keyboard delivery | **Not run — requires browser plus running Mac session** |
| Build/launch greeting; edit/rebuild/relaunch; compile-error recovery with stream intact | **Not run — requires manual remote builds** |
| Client disconnect/reconnect and hosted-shell exit | **Not run — documented from pinned upstream; requires real session** |
| Cancellation stops access / cleanup on disposal | **Not run — requires real session** |
| Five-hour hard limit | **Passed — configuration is 300 minutes**; **actual five-hour expiry not observed** |

After you authorize/start a run, verify the not-run rows. In particular:

1. Reach a ready Home-screen preview and SSH command with **no HelloIOS build**.
2. Join with the authorized key; verify an unrelated key is rejected.
3. In a fresh/private browser window, the bare URL must not expose the preview.
   Private navigation must work. Confirm visible video, taps, gestures, and
   supported keyboard entry in a simulator text field (the greeting has none).
4. Build/run HelloIOS, edit the greeting and rebuild, then deliberately introduce
   a Swift compile error. Confirm nonzero build status and a still-usable preview;
   fix the error and rebuild successfully.
5. Disconnect/reconnect without exiting; then test `exit` ends the session.
6. In a separate run, cancel and confirm SSH/preview access ends. Only record
   actual five-hour expiry as observed if you let a session reach that limit.

### Upstream references reviewed

- [Runner image architecture](https://github.com/actions/runner-images#available-images)
- [Upterm action v2.7.0](https://github.com/owenthereal/action-upterm/tree/b9dfa526f890bbd5162d781f8d9c69b97731d73d)
- [Upterm v0.39.0](https://github.com/owenthereal/upterm/releases/tag/v0.39.0)
- [Published serve-sim 0.10.3](https://www.npmjs.com/package/@expo/serve-sim/v/0.10.3)
- [Published native-sim 0.2.2 workflow and gate templates](https://www.npmjs.com/package/native-sim/v/0.2.2)
- [native-sim upstream](https://github.com/bidah/native-sim)
- [Matching serve-sim API/auth spec at published gitHead](https://github.com/expo/expo-device-hub/blob/2dbd92873b6ce44722cb0d283c70bd2684172c63/llp/0003-serve-sim-http-api.spec.md)
- [Matching state interface](https://github.com/expo/expo-device-hub/blob/2dbd92873b6ce44722cb0d283c70bd2684172c63/packages/serve-sim/packages/serve-sim/src/state.ts)
- [Cloudflare Quick Tunnels and limitations](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)
- [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)
- [Node release metadata](https://nodejs.org/dist/index.json)
