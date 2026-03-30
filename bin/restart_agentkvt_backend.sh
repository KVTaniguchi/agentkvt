#!/bin/bash
# Restart the AgentKVT Rails API and Solid Queue jobs on the production Mac.
#
# Usage:
#   ./bin/restart_agentkvt_backend.sh [user@host]
#
# Defaults to familyagent@192.168.4.144 when no argument is given.
#
# What it restarts:
#   com.agentkvt.api   — Puma / Rails server
#   com.agentkvt.jobs  — Solid Queue worker

set -euo pipefail

REMOTE_HOST="${1:-familyagent@192.168.4.144}"
UID_CMD='id -u'

exec ssh "${REMOTE_HOST}" /bin/bash -lc "
  set -e
  U=\$(${UID_CMD})
  echo '→ restarting com.agentkvt.api ...'
  launchctl kickstart -k gui/\${U}/com.agentkvt.api
  echo '→ restarting com.agentkvt.jobs ...'
  launchctl kickstart -k gui/\${U}/com.agentkvt.jobs
  echo '✓ done — checking health ...'
  sleep 3
  curl -sf http://127.0.0.1:3000/healthz && echo ' healthy' || echo ' healthz not yet ready'
"
