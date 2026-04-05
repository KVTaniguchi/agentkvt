#!/bin/bash
set -euo pipefail

HOST="${AGENTKVT_PROD_HOST:-familyagent@192.168.4.144}"
APP_LINES="${AGENTKVT_ANALYZE_APP_LINES:-2500}"
API_LINES="${AGENTKVT_ANALYZE_API_LINES:-12000}"
POSTGRES_LINES="${AGENTKVT_ANALYZE_POSTGRES_LINES:-500}"
LAUNCHD_LINES="${AGENTKVT_ANALYZE_LAUNCHD_LINES:-200}"
SHOW_RAW=0

usage() {
  cat <<'EOF'
Analyze current AgentKVT production logs over SSH.

Usage:
  ./bin/analyze_agent_logs.sh [options]

Options:
  --host HOST              SSH target. Default: familyagent@192.168.4.144
  --app-lines N            Tail length for app logs. Default: 2500
  --api-lines N            Tail length for Rails API logs. Default: 12000
  --postgres-lines N       Tail length for Postgres logs. Default: 500
  --launchd-lines N        Tail length for launchd stderr. Default: 200
  --raw                    Print raw log excerpts after the summary
  -h, --help               Show this help

Environment:
  AGENTKVT_PROD_HOST       Default SSH target override
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="$2"
      shift 2
      ;;
    --app-lines)
      APP_LINES="$2"
      shift 2
      ;;
    --api-lines)
      API_LINES="$2"
      shift 2
      ;;
    --postgres-lines)
      POSTGRES_LINES="$2"
      shift 2
      ;;
    --launchd-lines)
      LAUNCHD_LINES="$2"
      shift 2
      ;;
    --raw)
      SHOW_RAW=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

for value_name in APP_LINES API_LINES POSTGRES_LINES LAUNCHD_LINES; do
  value="${!value_name}"
  if ! [[ "${value}" =~ ^[0-9]+$ ]] || [ "${value}" -le 0 ]; then
    echo "${value_name} must be a positive integer." >&2
    exit 1
  fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

remote_quote() {
  printf "%q" "$1"
}

ssh_capture() {
  local command="$1"
  ssh "${HOST}" "${command}"
}

fetch_remote_text() {
  local command="$1"
  local output_file="$2"
  if ssh_capture "${command}" >"${output_file}" 2>"${output_file}.err"; then
    rm -f "${output_file}.err"
  else
    cat "${output_file}.err" >&2
    rm -f "${output_file}.err"
    return 1
  fi
}

fetch_remote_tail() {
  local remote_path="$1"
  local lines="$2"
  local output_file="$3"
  local quoted_path
  quoted_path="$(remote_quote "${remote_path}")"
  if ssh_capture "test -f ${quoted_path}" >/dev/null 2>&1; then
    ssh_capture "tail -n ${lines} ${quoted_path}" >"${output_file}" || true
  else
    : >"${output_file}"
  fi
}

count_matches() {
  local pattern="$1"
  local file="$2"
  grep -E -c "${pattern}" "${file}" 2>/dev/null || true
}

print_matches() {
  local label="$1"
  local pattern="$2"
  local file="$3"
  local limit="$4"
  local matches
  matches="$(grep -E "${pattern}" "${file}" 2>/dev/null | tail -n "${limit}" || true)"
  if [ -n "${matches}" ]; then
    echo "  ${label}"
    while IFS= read -r line; do
      echo "    ${line}"
    done <<<"${matches}"
  fi
}

echo "Connecting to ${HOST} and collecting production log slices..." >&2

REMOTE_HOME="$(ssh_capture 'printf "%s" "$HOME"')"
APP_GROUP_LOG="${REMOTE_HOME}/Library/Group Containers/group.com.agentkvt.shared/Library/Logs/agentkvt-mac.log"
HOME_APP_LOG="${REMOTE_HOME}/.agentkvt/logs/agentkvt-macapp.log"
API_LOG="${REMOTE_HOME}/.agentkvt/logs/api.log"
POSTGRES_LOG="${REMOTE_HOME}/.agentkvt/logs/postgres.log"
LAUNCHD_ERR="/tmp/agentkvt-macapp-launchd.err"

fetch_remote_text "hostname; date; whoami" "${TMP_DIR}/host.txt"
fetch_remote_text "curl -sS http://127.0.0.1:3000/healthz || true" "${TMP_DIR}/health.txt"
fetch_remote_text "launchctl list | egrep 'agentkvt|ollama' || true" "${TMP_DIR}/launchctl.txt"
fetch_remote_text "pgrep -fl 'AgentKVTMacApp|AgentKVTMacRunner|ollama|puma|rails' || true" "${TMP_DIR}/processes.txt"

fetch_remote_tail "${APP_GROUP_LOG}" "${APP_LINES}" "${TMP_DIR}/app_group.log"
fetch_remote_tail "${HOME_APP_LOG}" "${APP_LINES}" "${TMP_DIR}/home_app.log"
fetch_remote_tail "${API_LOG}" "${API_LINES}" "${TMP_DIR}/api.log"
fetch_remote_tail "${POSTGRES_LOG}" "${POSTGRES_LINES}" "${TMP_DIR}/postgres.log"
fetch_remote_tail "${LAUNCHD_ERR}" "${LAUNCHD_LINES}" "${TMP_DIR}/launchd.err"

cat "${TMP_DIR}/app_group.log" "${TMP_DIR}/home_app.log" >"${TMP_DIR}/app_combined.log"

host_summary="$(tr '\n' ' ' <"${TMP_DIR}/host.txt" | sed 's/[[:space:]]\+/ /g; s/ $//')"
health_summary="$(tr -d '\n' <"${TMP_DIR}/health.txt")"

route_404_count="$(count_matches 'No route matches \[GET\] "/v1/agent/missions/.*/action_items"' "${TMP_DIR}/api.log")"
blank_422_count="$(count_matches 'Completed 422 Unprocessable Content|Content can.?.?t be blank' "${TMP_DIR}/api.log")"
webhook_port_conflict_count="$(count_matches 'WebhookListener error: .*Address already in use' "${TMP_DIR}/app_combined.log")"
backend_log_failure_count="$(count_matches 'Failed to send backend log' "${TMP_DIR}/app_combined.log")"
session_restart_count="$(count_matches '^===== AgentKVT session started' "${TMP_DIR}/app_combined.log")"
launchservices_open_fail_count="$(count_matches '_LSOpenURLsWithCompletionHandler\(\) failed' "${TMP_DIR}/launchd.err")"
postgres_cached_plan_count="$(count_matches 'cached plan must not change result type' "${TMP_DIR}/postgres.log")"
app_group_sessions="$(count_matches '^===== AgentKVT session started' "${TMP_DIR}/app_group.log")"
home_app_sessions="$(count_matches '^===== AgentKVT session started' "${TMP_DIR}/home_app.log")"

echo
echo "Production Log Analysis"
echo "Host: ${HOST}"
echo "Snapshot: ${host_summary}"
if [ -n "${health_summary}" ]; then
  echo "Health: ${health_summary}"
else
  echo "Health: unavailable"
fi

echo
echo "Services"
if [ -s "${TMP_DIR}/launchctl.txt" ]; then
  sed 's/^/  /' "${TMP_DIR}/launchctl.txt"
else
  echo "  No matching launchctl services found."
fi

if [ -s "${TMP_DIR}/processes.txt" ]; then
  sed 's/^/  /' "${TMP_DIR}/processes.txt"
else
  echo "  No matching processes found."
fi

echo
echo "Key Findings"

finding_count=0

if [ "${route_404_count}" -gt 0 ]; then
  finding_count=$((finding_count + 1))
  echo "${finding_count}. Mission action-item endpoint failures: ${route_404_count} recent 404 route errors on /v1/agent/missions/:id/action_items."
  print_matches "Evidence:" 'Started GET "/v1/agent/missions/.*/action_items"|No route matches \[GET\] "/v1/agent/missions/.*/action_items"' "${TMP_DIR}/api.log" 6
fi

if [ "${blank_422_count}" -gt 0 ]; then
  finding_count=$((finding_count + 1))
  echo "${finding_count}. Backend validation failures: ${blank_422_count} recent log writes were rejected with 422 or blank-content validation."
  print_matches "Evidence:" 'Completed 422 Unprocessable Content|Content can.?.?t be blank|phase" => "assistant_final"|phase" => "outcome"' "${TMP_DIR}/api.log" 8
fi

if [ "${webhook_port_conflict_count}" -gt 0 ] || [ "${launchservices_open_fail_count}" -gt 0 ] || [ "${session_restart_count}" -gt 1 ]; then
  finding_count=$((finding_count + 1))
  echo "${finding_count}. App process churn: ${session_restart_count} recent session start markers, ${webhook_port_conflict_count} webhook bind conflict(s), ${launchservices_open_fail_count} LaunchServices open failure(s)."
  if [ "${app_group_sessions}" -gt 0 ] && [ "${home_app_sessions}" -gt 0 ]; then
    echo "  Both app-group and ~/.agentkvt log targets are active in the sampled window."
  fi
  print_matches "Evidence:" '^===== AgentKVT session started|WebhookListener error: .*Address already in use' "${TMP_DIR}/app_combined.log" 10
  print_matches "Launchd stderr:" '_LSOpenURLsWithCompletionHandler\(\) failed' "${TMP_DIR}/launchd.err" 5
fi

if [ "${backend_log_failure_count}" -gt 0 ]; then
  finding_count=$((finding_count + 1))
  echo "${finding_count}. Runner-to-backend log delivery issues: ${backend_log_failure_count} failed backend log write(s) in app logs."
  print_matches "Evidence:" 'Failed to send backend log|Could not fetch existing actions' "${TMP_DIR}/app_combined.log" 8
fi

if [ "${postgres_cached_plan_count}" -gt 0 ]; then
  finding_count=$((finding_count + 1))
  echo "${finding_count}. Postgres prepared-plan issue: ${postgres_cached_plan_count} recent \"cached plan must not change result type\" error(s)."
  print_matches "Evidence:" 'cached plan must not change result type|STATEMENT:' "${TMP_DIR}/postgres.log" 6
fi

if [ "${finding_count}" -eq 0 ]; then
  echo "1. No known failure signatures were found in the sampled log window."
fi

echo
echo "Quick Stats"
echo "  API 404 route errors: ${route_404_count}"
echo "  API 422 / blank-content errors: ${blank_422_count}"
echo "  Webhook port conflicts: ${webhook_port_conflict_count}"
echo "  Failed backend log writes: ${backend_log_failure_count}"
echo "  App session markers in sample: ${session_restart_count}"
echo "  Postgres cached-plan errors: ${postgres_cached_plan_count}"

if [ "${SHOW_RAW}" -eq 1 ]; then
  echo
  echo "Raw Excerpts"
  for file in host.txt health.txt launchctl.txt processes.txt app_group.log home_app.log api.log postgres.log launchd.err; do
    echo "-- ${file} --"
    if [ -s "${TMP_DIR}/${file}" ]; then
      cat "${TMP_DIR}/${file}"
    else
      echo "(empty)"
    fi
    echo
  done
fi
