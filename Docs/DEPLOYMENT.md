# Deployment Guide

This is the consolidated deployment guide for the AgentKVT system. It covers the Rails backend, the Mac Brain app, iOS clients, and network reachability.

## Deployment Boundary

AgentKVT production has two independent deployables:

- **the signed/TestFlight macOS app bundle** (the Brain)
- **the Rails backend** running from the repo checkout on the server Mac

Installing a new TestFlight build does **not** update the backend repo, run Rails migrations, or restart the API. Treat each as a separate service with its own deploy flow.

---

## 1. Rails Backend (Server Mac)

### One-time setup

1. Ensure the repo is cloned on the server Mac.
2. Run the bootstrap script:

   ```bash
   cd /path/to/agentkvt
   ./bin/bootstrap_agentkvt_backend.sh
   ```

3. Configure production secrets in `server/.env` (gitignored). At minimum:
   - `RAILS_ENV=production`
   - `SECRET_KEY_BASE` — generate with `cd server && bundle exec rails secret`
   - `AGENTKVT_ALLOW_HTTP=1` — required while clients use plain HTTP (Tailscale/LAN)
   - `AGENTKVT_AGENT_TOKEN` — same token the Mac runner uses

4. Prepare the production databases:

   ```bash
   ./bin/prepare_production_db.sh
   ```

5. Install the backend LaunchAgent:

   ```bash
   mkdir -p ~/.agentkvt/logs ~/Library/LaunchAgents
   cp AgentKVTMac/Deploy/com.agentkvt.api.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentkvt.api.plist
   launchctl enable gui/$(id -u)/com.agentkvt.api
   launchctl kickstart -k gui/$(id -u)/com.agentkvt.api
   ```

6. Verify the API:

   ```bash
   curl -sS http://127.0.0.1:3000/healthz
   ```

### Day-to-day backend deploy

Run on the server Mac:

```bash
cd /path/to/agentkvt
./bin/deploy_agentkvt_backend.sh origin/main
```

Or remotely:

```bash
./bin/deploy_remote_agentkvt_backend.sh familyagent@<server-ip> origin/main
```

The deploy script creates a backup branch, fetches, merges, runs `prepare_production_db.sh`, restarts the API via `launchctl`, and verifies `/healthz`.

### Bind address

- **LAN + Tailscale:** set `AGENTKVT_BIND_ALL_INTERFACES=1` in `server/.env` so the API binds `0.0.0.0`.
- **Tailscale only:** leave unset; the script defaults to the machine's Tailscale IPv4 if available.

---

## 2. Mac Brain (TestFlight or LaunchAgent)

### TestFlight path (recommended for production)

1. Archive the `AgentKVTMacApp` scheme in Xcode.
2. Upload to App Store Connect.
3. Install TestFlight on the server Mac and install the build.

### Configuration

TestFlight installs do not inherit Xcode scheme env vars. The Mac app reads runtime configuration from:

```
~/.agentkvt/agentkvt-runner.plist
```

Start from [AgentKVTMac/Deploy/agentkvt-runner.plist.sample](../AgentKVTMac/Deploy/agentkvt-runner.plist.sample).

Key configuration values:

```xml
<key>RUN_SCHEDULER</key>
<true/>
<key>OLLAMA_MODEL</key>
<string>llama4:latest</string>
<key>OLLAMA_BASE_URL</key>
<string>http://localhost:11434</string>
<key>SCHEDULER_INTERVAL_SECONDS</key>
<integer>30</integer>
<key>AGENTKVT_API_BASE_URL</key>
<string>http://127.0.0.1:3000</string>
<key>AGENTKVT_WORKSPACE_SLUG</key>
<string>default</string>
<key>AGENTKVT_AGENT_TOKEN</key>
<string>your-agent-token</string>
```

### Secrets

Do **not** store `OLLAMA_API_KEY`, `AGENTKVT_AGENT_TOKEN`, or similar in `~/Library/LaunchAgents/*.plist`. Put secrets in the runner plist instead and restrict permissions:

```bash
chmod 600 ~/.agentkvt/agentkvt-runner.plist
```

### Auto-start at login

Use the LaunchAgent template:

- [AgentKVTMac/Deploy/com.agentkvt.macapp.plist](../AgentKVTMac/Deploy/com.agentkvt.macapp.plist)

### Verify

Tail the log:

```bash
tail -n 200 ~/.agentkvt/logs/agentkvt-macapp.log
```

You should see scheduler startup messages and clock tick lines.

---

## 3. iOS Client (TestFlight)

### API URL configuration

Release builds use `AgentKVTiOS/Info.Release.plist`, which reads `AGENTKVT_API_BASE_URL` and `AGENTKVT_WORKSPACE_SLUG` from `AgentKVTiOS/Config/AgentKVTiOS.release.xcconfig`.

**Local override (gitignored):**

1. Copy `AgentKVTiOS/Config/AgentKVTiOS.release.local.xcconfig.example` to `AgentKVTiOS/Config/AgentKVTiOS.release.local.xcconfig`.
2. Set `AGENTKVT_API_BASE_URL` to `http://your-mac.tail-xxxxx.ts.net:3000`.
3. Archive and upload to TestFlight.

`IOSBackendSettings` resolves configuration in this order: **process environment** (Xcode Run), **app-group `agentkvt-runner.plist`**, then **Info.plist** (Release defaults).

---

## 4. Network / Reachability

| Client location           | Server bind               | iOS `AGENTKVT_API_BASE_URL`         |
|---------------------------|---------------------------|-------------------------------------|
| Same Wi‑Fi as Mac         | `0.0.0.0` or LAN IP       | `http://192.168.x.x:3000`          |
| iPhone on cellular + VPN  | Tailscale IP or `0.0.0.0` | `http://100.x.x.x:3000` or MagicDNS|
| Internet without Tailscale| Not supported in-repo     | Add HTTPS reverse proxy + DNS       |

Install **Tailscale** on the server Mac and on each phone that should reach the API away from home.

---

## 5. Release Discipline

Use one git SHA as the release boundary for both sides:

1. Build and upload the Mac app from a chosen commit.
2. Deploy that same commit to the server backend.
3. Verify the API after the deploy before assuming the TestFlight build is live end-to-end.

---

## Log Locations

| Component | Log path |
|-----------|----------|
| Rails API | `server/log/production.log` |
| Postgres  | `~/.agentkvt/logs/postgres.log` |
| Mac Brain | `~/.agentkvt/logs/agentkvt-macapp.log` |

## Operations

- **Analyze agent logs over SSH:** `./bin/analyze_agent_logs.sh`
  - Defaults to `familyagent@192.168.4.144`; override with `--host` or `AGENTKVT_PROD_HOST`.
  - Add `--raw` to print sampled log excerpts after the summary.
