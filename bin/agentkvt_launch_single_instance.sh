#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?usage: $0 <runner|macapp> <command...>}"
shift

if [[ "$#" -eq 0 ]]; then
  echo "usage: $0 <runner|macapp> <command...>" >&2
  exit 64
fi

WEBHOOK_PORT="${WEBHOOK_PORT:-8765}"
STATE_DIR="${HOME}/.agentkvt/run"
PID_FILE="${STATE_DIR}/agentkvt-${MODE}.pid"
mkdir -p "${STATE_DIR}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '[%s] [agentkvt-launch:%s] %s\n' "$(timestamp)" "${MODE}" "$*"
}

cleanup() {
  rm -f "${PID_FILE}"
}

trap cleanup EXIT INT TERM

if [[ -f "${PID_FILE}" ]]; then
  existing_pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
    log "Previous ${MODE} instance still recorded as PID ${existing_pid}; sending SIGTERM."
    kill -TERM "${existing_pid}" 2>/dev/null || true
  fi
fi

"$(dirname "$0")/agentkvt_cleanup_webhook_owner.sh" "${WEBHOOK_PORT}"

log "Launching: $*"
"$@" &
child_pid="$!"
printf '%s\n' "${child_pid}" > "${PID_FILE}"
wait "${child_pid}"
