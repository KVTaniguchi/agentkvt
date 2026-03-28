# Production server, TestFlight clients, and reachability

This document ties together **Rails production mode + `agentkvt_production`**, **iOS Release/TestFlight API configuration**, and **network reachability** (LAN and Tailscale).

## Deployment boundary

The production setup has two separate deployables:

- the signed/TestFlight macOS app bundle
- the Rails backend running from the repo checkout on the server Mac

Installing a new TestFlight build does **not** update `~/AgentKVTMac`, run Rails migrations, or restart Puma. Treat the backend as its own service with its own deploy flow.

For the repeatable backend deploy path, see [BACKEND_DEPLOYMENT.md](BACKEND_DEPLOYMENT.md).

## 1. Rails production on the Mac server

1. On the server Mac, ensure Postgres is running (same as development).

2. Add production secrets to `server/.env` (this file is gitignored). At minimum:

   - `RAILS_ENV=production`
   - `SECRET_KEY_BASE` — generate with `cd server && bundle exec rails secret`
   - `AGENTKVT_ALLOW_HTTP=1` — required while clients use plain `http://` to Puma (Tailscale/LAN). Omit only if you terminate TLS in front of Rails.
   - `AGENTKVT_AGENT_TOKEN` — same token the Mac runner uses

3. Prepare the production databases (Rails 8 **Solid Cache / Queue / Cable** use separate Postgres DBs in production):

   ```bash
   ./bin/prepare_production_db.sh
   ```

   This runs `rails db:prepare` with `RAILS_ENV=production` so **`agentkvt_production`**, **`agentkvt_production_cache`**, **`agentkvt_production_queue`**, and **`agentkvt_production_cable`** are created and schema-loaded. If those databases do not exist yet, create them first (the bootstrap script’s `createdb` loop includes these names) or rely on `db:create` during `db:prepare`.

4. Listen on an address phones can reach:

   - **LAN + Tailscale:** set `AGENTKVT_BIND_ALL_INTERFACES=1` in `server/.env` so `./bin/run_agentkvt_api.sh` binds `0.0.0.0` (after sourcing `.env`). Clients can use the Mac’s **LAN IP** or **Tailscale IP/hostname** on port `3000`.
   - **Tailscale only:** leave `AGENTKVT_BIND_ALL_INTERFACES` unset; if Tailscale is installed, the script defaults to the machine’s Tailscale IPv4.

5. Start the API:

   ```bash
   ./bin/run_agentkvt_api.sh
   ```

   The script logs `RAILS_ENV`, bind address, and port to stderr.

6. Confirm:

   ```bash
   curl -sS "http://127.0.0.1:3000/healthz"
   ```

   From another device on Tailscale, use `http://<tailscale-ip>:3000/healthz` instead.

### Recommended service management

For long-running production use, install the dedicated backend LaunchAgent template:

- [com.agentkvt.api.plist](../AgentKVTMac/Deploy/com.agentkvt.api.plist)

That keeps the Rails API separate from the TestFlight app lifecycle and gives `./bin/deploy_agentkvt_backend.sh` a stable restart target.

## 2. iOS Release / TestFlight API URL

Release builds use `AgentKVTiOS/Info.Release.plist`, which reads **`AGENTKVT_API_BASE_URL`** and **`AGENTKVT_WORKSPACE_SLUG`** from `AgentKVTiOS/Config/AgentKVTiOS.release.xcconfig`.

- Defaults are set for a LAN server; for **off-LAN TestFlight** users, set a **reachable** base URL (usually Tailscale MagicDNS or Tailscale IP).

**Optional local override (gitignored):**

1. Copy `AgentKVTiOS/Config/AgentKVTiOS.release.local.xcconfig.example` to `AgentKVTiOS/Config/AgentKVTiOS.release.local.xcconfig`.
2. Set `AGENTKVT_API_BASE_URL` to `http://your-mac.tail-xxxxx.ts.net:3000` (or your chosen host).
3. Archive and upload to TestFlight.

`IOSBackendSettings` resolves configuration in this order: **process environment** (Xcode Run), **app-group `agentkvt-runner.plist`**, then **Info.plist** (Release defaults).

## 3. Reachability checklist

| Client location            | Server bind              | iOS `AGENTKVT_API_BASE_URL`        |
|---------------------------|--------------------------|-------------------------------------|
| Same Wi‑Fi as Mac         | `0.0.0.0` or LAN IP      | `http://192.168.x.x:3000`           |
| iPhone on cellular + VPN  | Tailscale IP or `0.0.0.0`| `http://100.x.x.x:3000` or MagicDNS |
| Internet without Tailscale | Not supported in-repo   | Add HTTPS reverse proxy + DNS       |

Install **Tailscale** on the server Mac and on each phone that should reach the API away from home. Use the server’s Tailscale IP or `*.ts.net` name in the Release xcconfig (or local override).

## Mac TestFlight agent

The Mac app does not use Xcode scheme variables when installed from TestFlight. Point it at the same API by editing the app-group plist — see `Docs/MAC_PRODUCTION_DEPLOYMENT.md` and `AgentKVTMac/Deploy/agentkvt-runner.plist.sample`.
