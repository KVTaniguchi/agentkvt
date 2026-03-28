#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./bin/deploy_remote_agentkvt_backend.sh user@host [git-ref] [remote-repo]

Run the server-side backend deploy script over SSH.

Examples:
  ./bin/deploy_remote_agentkvt_backend.sh familyagent@192.168.4.144
  ./bin/deploy_remote_agentkvt_backend.sh familyagent@192.168.4.144 origin/main
  ./bin/deploy_remote_agentkvt_backend.sh familyagent@192.168.4.144 ee73d45 ~/AgentKVTMac
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

REMOTE_HOST="${1:-}"
TARGET_REF="${2:-origin/main}"
REMOTE_REPO="${3:-~/AgentKVTMac}"

[ -n "${REMOTE_HOST}" ] || {
  usage
  exit 1
}

if [ $# -ge 3 ]; then
  REMOTE_CD_TARGET="$(printf '%q' "${REMOTE_REPO}")"
else
  REMOTE_CD_TARGET='~/AgentKVTMac'
fi

REMOTE_COMMAND="cd ${REMOTE_CD_TARGET} && ./bin/deploy_agentkvt_backend.sh $(printf '%q' "${TARGET_REF}")"

exec ssh "${REMOTE_HOST}" /bin/bash -lc "${REMOTE_COMMAND}"
