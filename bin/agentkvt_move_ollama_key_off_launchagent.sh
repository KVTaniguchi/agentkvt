#!/usr/bin/env bash
# Move OLLAMA_API_KEY from com.agentkvt.macapp LaunchAgent into ~/.agentkvt/agentkvt-runner.plist
# and remove it from the LaunchAgent plist. LaunchAgents are easy to leak via backups, screenshots,
# and support bundles; runner plist is user-only config and should be chmod 600.
#
# Usage (on the Mac that owns the LaunchAgent):
#   ./bin/agentkvt_move_ollama_key_off_launchagent.sh
#
# Then restart the app agent, e.g.:
#   launchctl kickstart -k "gui/$(id -u)/com.agentkvt.macapp"
set -euo pipefail

LAUNCH_PLIST="${HOME}/Library/LaunchAgents/com.agentkvt.macapp.plist"
RUNNER_PLIST="${HOME}/.agentkvt/agentkvt-runner.plist"

if [[ ! -f "${LAUNCH_PLIST}" ]]; then
  echo "No LaunchAgent at ${LAUNCH_PLIST}; nothing to do." >&2
  exit 0
fi

python3 <<'PY'
import os
import plistlib
from pathlib import Path

home = Path.home()
launch_path = home / "Library/LaunchAgents/com.agentkvt.macapp.plist"
runner_path = home / ".agentkvt/agentkvt-runner.plist"

with launch_path.open("rb") as f:
    launch = plistlib.load(f)

ev = dict(launch.get("EnvironmentVariables") or {})
secret = ev.pop("OLLAMA_API_KEY", None)
if not secret:
    print("No OLLAMA_API_KEY in LaunchAgent EnvironmentVariables; nothing to migrate.")
    raise SystemExit(0)

runner_path.parent.mkdir(parents=True, exist_ok=True)
if runner_path.exists():
    with runner_path.open("rb") as f:
        cfg = plistlib.load(f)
else:
    cfg = {}

if cfg.get("OLLAMA_API_KEY"):
    print("Runner plist already defines OLLAMA_API_KEY; not overwriting. Still removing from LaunchAgent.")
else:
    cfg["OLLAMA_API_KEY"] = secret
    with runner_path.open("wb") as f:
        plistlib.dump(cfg, f)
    os.chmod(runner_path, 0o600)
    print(f"Wrote OLLAMA_API_KEY to {runner_path} (mode 600).")

if ev:
    launch["EnvironmentVariables"] = ev
else:
    launch.pop("EnvironmentVariables", None)

with launch_path.open("wb") as f:
    plistlib.dump(launch, f)

print(f"Removed OLLAMA_API_KEY from {launch_path}. Restart com.agentkvt.macapp when ready.")
PY
