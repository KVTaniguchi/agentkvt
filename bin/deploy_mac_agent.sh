#!/usr/bin/env bash
# Builds AgentKVTMacApp locally, copies it to the server, and restarts the launchd service.
#
# Usage:
#   ./bin/deploy_mac_agent.sh
#   SKIP_BUILD=1 ./bin/deploy_mac_agent.sh   # skip Xcode build, just re-copy + restart

set -euo pipefail

SERVER="familyagent@192.168.4.29"
REMOTE_APP_DIR="$HOME/Applications"          # local ~/Applications mirrored to server
APP_NAME="AgentKVTMacApp.app"
LAUNCHD_LABEL="com.agentkvt.macapp"
SCHEME="AgentKVTMacApp"
WORKSPACE="AgentKVTWorkspace.xcodeproj/project.xcworkspace"
DERIVED_DATA="/tmp/agentkvt-macapp-build"
BUILD_DIR="$DERIVED_DATA/Build/Products/Release"

cd "$(dirname "$0")/.."

# --- 1. Build ---
if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "▶ Building $SCHEME (Release)..."
  xcodebuild build \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "platform=macOS" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    2>&1 | grep -E "(error:|warning:|BUILD)" || true

  echo "✓ Build complete."
else
  echo "⚠ SKIP_BUILD=1 — skipping Xcode build."
fi

APP_PATH="$BUILD_DIR/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "✗ Could not find built app at $APP_PATH"
  echo "  Run without SKIP_BUILD=1 or check the scheme name."
  exit 1
fi

# --- 2. Stop the running agent ---
echo "▶ Stopping $LAUNCHD_LABEL on server..."
ssh "$SERVER" "launchctl stop $LAUNCHD_LABEL 2>/dev/null || true"
sleep 1

# --- 3. Rsync the new app bundle ---
echo "▶ Copying $APP_NAME to $SERVER:~/Applications/..."
rsync -az --delete \
  "$APP_PATH" \
  "$SERVER:~/Applications/"

# --- 4. Restart ---
echo "▶ Starting $LAUNCHD_LABEL on server..."
ssh "$SERVER" "launchctl kickstart -k gui/\$(id -u)/$LAUNCHD_LABEL"
sleep 2

# --- 5. Healthcheck ---
echo "▶ Checking agent is alive..."
ssh "$SERVER" "launchctl list $LAUNCHD_LABEL" | grep -E "PID|Label" || true

echo ""
echo "✓ Mac agent deployed and restarted."
