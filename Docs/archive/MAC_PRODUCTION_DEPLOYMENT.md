> **⚠️ HISTORICAL** — This document has been archived. It describes completed work or superseded architecture. See the active docs in `Docs/` for current information.

# Mac Production Deployment

Use this guide when the iPhone client is coming from TestFlight and the Mac Brain also needs to read the same **production** CloudKit records.

This guide covers the macOS app bundle. The Rails backend on the server Mac is a separate deployable and must be updated independently. Installing a new TestFlight Mac build does **not** update `~/AgentKVTMac/server` or restart the backend API.

## Why this matters

Mixing **TestFlight iPhone** with an **Xcode-run Mac app** is not a reliable shared-store setup:

- TestFlight builds use the production CloudKit environment
- Xcode debug runs typically use development data while you are iterating locally

For real user-facing sync, the Mac side should also be distributed as a production-style build.

## Recommended path

Use the signed **AgentKVTMacApp** target, upload it to **App Store Connect**, then install it on the server Mac through **TestFlight for Mac**.

The repo already has the macOS app target and shared CloudKit setup:

- bundle identifier `com.agentkvt.app`
- CloudKit container `iCloud.AgentKVT`
- app group `group.com.agentkvt.shared`

## 1. Archive the macOS app

In Xcode:

1. Open [AgentKVTWorkspace.xcodeproj](../AgentKVTWorkspace.xcodeproj)
2. Choose the `AgentKVTMacApp` scheme
3. Choose a Mac archive destination
4. Use **Product -> Archive**

## 2. Upload to App Store Connect

From the Organizer:

1. Select the archive
2. Choose **Distribute App**
3. Choose **App Store Connect**
4. Upload the macOS build

After App Store Connect finishes processing the build, add it to a TestFlight testing group for macOS.

## 3. Install TestFlight on the server Mac

On the server Mac:

1. Install **TestFlight** from the Mac App Store
2. Sign in with the Apple ID that should own the private CloudKit data
3. Install the macOS AgentKVT build from TestFlight

## 4. Configure the production Mac app

Production/TestFlight installs do not inherit Xcode scheme environment variables.

The Mac app now reads runtime configuration from this file by default:

```text
~/Library/Group Containers/group.com.agentkvt.shared/Library/Application Support/agentkvt-runner.plist
```

Start from [AgentKVTMac/Deploy/agentkvt-runner.plist.sample](../AgentKVTMac/Deploy/agentkvt-runner.plist.sample).

Useful starter values:

```xml
<key>RUN_SCHEDULER</key>
<true/>
<key>OLLAMA_MODEL</key>
<string>qwen3.6:35b</string>
<key>OLLAMA_BASE_URL</key>
<string>http://localhost:11434</string>
<key>SCHEDULER_INTERVAL_SECONDS</key>
<integer>30</integer>
```

Environment variables still override the file if you deliberately launch the app that way, but the config plist is the production-friendly path.

### Secrets (API keys, tokens)

Do **not** store `OLLAMA_API_KEY`, `AGENTKVT_AGENT_TOKEN`, or similar in `~/Library/LaunchAgents/*.plist`. Those files are easy to leak via backups, support bundles, or accidental sharing. Put secrets in the runner plist instead (same keys as environment variables), then restrict permissions:

```bash
chmod 600 ~/.agentkvt/agentkvt-runner.plist
```

If you already put `OLLAMA_API_KEY` in `com.agentkvt.macapp.plist`, migrate it once:

```bash
./bin/agentkvt_move_ollama_key_off_launchagent.sh
launchctl kickstart -k "gui/$(id -u)/com.agentkvt.macapp"
```

For the current backend pivot smoke environment, there is one important distinction:

- signed/TestFlight macOS app: use the shared app-group config/log paths above
- unsigned or Xcode-built app launched by `launchd`: prefer home-directory overrides

The unsigned launchd case can stall while opening app-group files before the scheduler starts. If you need to run that path on the server Mac during development, set these LaunchAgent environment variables:

```text
AGENTKVT_CONFIG_FILE=~/.agentkvt/agentkvt-runner.plist
AGENTKVT_LOG_FILE=~/.agentkvt/logs/agentkvt-macapp.log
```

and copy the runtime plist from the app-group location into `~/.agentkvt/agentkvt-runner.plist`.

## 5. Launch and verify

When the signed app launches, tail:

```bash
LOG="$HOME/Library/Group Containers/group.com.agentkvt.shared/Library/Logs/agentkvt-mac.log"
tail -n 200 "$LOG"
```

You want to see:

- `SwiftData storage: app group + CloudKit`
- clock tick lines that show the Mac can see missions

## 6. Optional auto-start at login

If the server Mac should reopen the app automatically after login, use:

- [AgentKVTMac/Deploy/com.agentkvt.macapp.plist](../AgentKVTMac/Deploy/com.agentkvt.macapp.plist)

This is a `LaunchAgent` template for the signed app bundle, not the old CLI runner.

## Notes

- The CLI runner is still useful for isolated smoke tests, but it is not the production shared-store path.
- The production macOS app defaults to scheduler mode automatically. CLI runs still default to the one-shot smoke test unless `RUN_SCHEDULER` is set.
- Backend deploy/restart steps live in [BACKEND_DEPLOYMENT.md](BACKEND_DEPLOYMENT.md).
