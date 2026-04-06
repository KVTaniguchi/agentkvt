> **⚠️ HISTORICAL** — This document has been archived. It describes completed work or superseded architecture. See the active docs in `Docs/` for current information.

# Backend Deployment

This is the repeatable deployment path for the Rails API that runs on the server Mac.

## Separate deployables

AgentKVT production currently has two independent deployables:

- the signed/TestFlight macOS app bundle
- the Rails backend running from the repo checkout at `~/AgentKVTMac`

TestFlight updates only the app bundle. It does **not**:

- update the backend repo checkout
- run Rails migrations
- restart the API process

That backend work needs its own deploy step every time the server-facing code changes.

## One-time setup on the server Mac

1. Make sure the repo lives at `~/AgentKVTMac`.
2. Configure production secrets in `server/.env`.
3. Install the backend LaunchAgent:

   ```bash
   mkdir -p ~/.agentkvt/logs ~/Library/LaunchAgents
   cp AgentKVTMac/Deploy/com.agentkvt.api.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentkvt.api.plist
   launchctl enable gui/$(id -u)/com.agentkvt.api
   launchctl kickstart -k gui/$(id -u)/com.agentkvt.api
   ```

4. Verify the API is responding:

   ```bash
   curl -sS http://127.0.0.1:3000/healthz
   ```

## Day-to-day backend deploy

Run this on the server Mac:

```bash
cd ~/AgentKVTMac
./bin/deploy_agentkvt_backend.sh origin/main
```

Or run it remotely from another machine:

```bash
./bin/deploy_remote_agentkvt_backend.sh familyagent@192.168.4.144 origin/main
```

The server-side deploy script:

- creates a `backup/pre-deploy-*` branch
- stashes dirty local changes before the merge
- fetches `origin`
- merges the requested ref
- runs `./bin/prepare_production_db.sh`
- restarts `com.agentkvt.api` if installed
- falls back to Puma `tmp/restart.txt` if the API is still unmanaged
- verifies `/healthz`
- probes `/v1/agent/chat_wake` so stale route tables show up immediately

## Release discipline

Use one git SHA as the release boundary for both sides:

1. Build and upload the Mac app from a chosen commit.
2. Deploy that same commit, tag, or branch to the server backend.
3. Verify the API after the deploy before assuming the TestFlight build is live end-to-end.

If the app and backend need to evolve together, do not rely on “latest app install” as the deployment event. Treat the backend deploy as a required release step.
