#!/usr/bin/env bash
set -euo pipefail

WEBHOOK_PORT="${1:-8765}"
WAIT_SECONDS="${AGENTKVT_PORT_WAIT_SECONDS:-30}"
STATE_DIR="${HOME}/.agentkvt/run"
REPELLENT_FILE="${STATE_DIR}/webhook-port-${WEBHOOK_PORT}.repellent"

mkdir -p "${STATE_DIR}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '[%s] [agentkvt-cleanup] %s\n' "$(timestamp)" "$*"
}

listener_pids() {
  lsof -nP -iTCP:"${WEBHOOK_PORT}" -sTCP:LISTEN -t 2>/dev/null | awk '!seen[$0]++'
}

command_for_pid() {
  ps -p "$1" -o command= 2>/dev/null || true
}

is_agentkvt_owner() {
  local cmd
  cmd="$(command_for_pid "$1")"
  [[ "${cmd}" == *"AgentKVTMacRunner"* || "${cmd}" == *"AgentKVTMacApp"* || "${cmd}" == *"com.agentkvt"* ]]
}

write_repellent() {
  cat > "${REPELLENT_FILE}" <<EOF
timestamp=$(timestamp)
port=${WEBHOOK_PORT}
note=Port conflict detected; waited for stale owner to release the webhook socket.
EOF
}

remove_repellent() {
  rm -f "${REPELLENT_FILE}"
}

port_is_clear() {
  [[ -z "$(listener_pids)" ]]
}

if port_is_clear; then
  remove_repellent
  exit 0
fi

write_repellent
log "Webhook port ${WEBHOOK_PORT} is busy; asking stale AgentKVT owner(s) to exit."

for pid in $(listener_pids); do
  if is_agentkvt_owner "${pid}"; then
    log "Sending SIGTERM to PID ${pid}: $(command_for_pid "${pid}")"
    kill -TERM "${pid}" 2>/dev/null || true
  else
    log "Port ${WEBHOOK_PORT} is held by a non-AgentKVT process (PID ${pid}); leaving it alone."
  fi
done

for ((i=0; i<WAIT_SECONDS; i++)); do
  if port_is_clear; then
    remove_repellent
    log "Webhook port ${WEBHOOK_PORT} is clear."
    exit 0
  fi
  sleep 1
done

log "Webhook port ${WEBHOOK_PORT} is still busy after ${WAIT_SECONDS}s."
exit 1
