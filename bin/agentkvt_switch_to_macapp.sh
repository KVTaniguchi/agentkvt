#!/usr/bin/env bash
# Stop the headless SPM runner (if any) so port 8765 is free, then open the Mac app.
# Only one of {AgentKVTMacRunner, AgentKVTMacApp} should own the webhook listener.
#
# Remote example:
#   ssh familyagent@192.168.4.144 'bash -s' < bin/agentkvt_switch_to_macapp.sh
# Or after cd ~/AgentKVTMac:
#   ./bin/agentkvt_switch_to_macapp.sh

set -euo pipefail

"$(dirname "$0")/agentkvt_cleanup_webhook_owner.sh" 8765

APP="/Applications/AgentKVTMacApp.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: $APP not found." >&2
  exit 1
fi

# open(1) needs a logged-in GUI session; it may no-op over plain SSH.
if "$(dirname "$0")/agentkvt_launch_single_instance.sh" macapp open -a "$APP" 2>/dev/null; then
  echo "OK: launched $APP (runner stopped if it was running)."
else
  echo "Runner stopped. Port 8765 should be free — open AgentKVTMacApp from the Dock, or run in Terminal.app on the Mac:"
  echo "  open -a \"$APP\""
fi
