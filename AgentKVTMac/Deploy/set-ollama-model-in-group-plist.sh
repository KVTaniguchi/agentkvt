#!/usr/bin/env bash
# Update OLLAMA_MODEL in the app-group agentkvt-runner.plist.
#
# Run as an admin on the server Mac. Do NOT run PlistBuddy as root against
# another user's group-container plist — macOS often denies that, and PlistBuddy
# may report "File Doesn't Exist" / "Entry does not exist" while creating a
# useless new file. This script runs Python as the target user so the real
# plist is read and written with correct ownership.
#
# Usage:
#   sudo ./set-ollama-model-in-group-plist.sh familyagent qwen3.6:35b

set -euo pipefail

TARGET_USER="${1:?usage: sudo $0 <macOS-user> [ollama-model]}"
MODEL="${2:-qwen3.6:35b}"
PLIST="/Users/${TARGET_USER}/Library/Group Containers/group.com.agentkvt.shared/Library/Application Support/agentkvt-runner.plist"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Re-run with sudo so we can run the edit as ${TARGET_USER}." >&2
  exit 1
fi

sudo -u "${TARGET_USER}" python3 - "${PLIST}" "${MODEL}" <<'PY'
import plistlib
import sys

path, model = sys.argv[1], sys.argv[2]
with open(path, "rb") as f:
    data = plistlib.load(f)
data["OLLAMA_MODEL"] = model
with open(path, "wb") as f:
    plistlib.dump(data, f)
print("Updated", path)
print("OLLAMA_MODEL =", data["OLLAMA_MODEL"])
PY
