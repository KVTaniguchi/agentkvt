#!/usr/bin/env bash
# Reset stuck objective tasks (in_progress -> pending) using the same DB as the
# running API, then POST /v1/objectives/:id/run_now to re-enqueue.
#
# Run on the server Mac from your AgentKVT repo clone (e.g. ~/AgentKVTMac).
# Loads server/.env the same way as ./bin/run_agentkvt_api.sh so you do not hit
# an empty development database by mistake.
#
# Usage:
#   ./bin/agentkvt_reset_objective_tasks.sh <objective_uuid>
#   ./bin/agentkvt_reset_objective_tasks.sh <uuid> --workspace-slug default
#   ./bin/agentkvt_reset_objective_tasks.sh <uuid> --api-base http://127.0.0.1:3000
#   ./bin/agentkvt_reset_objective_tasks.sh <uuid> --skip-run-now
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

OBJECTIVE_ID=""
API_BASE="${AGENTKVT_RESET_API_BASE:-http://127.0.0.1:3000}"
WORKSPACE_SLUG="${AGENTKVT_WORKSPACE_SLUG:-default}"
SKIP_RUN_NOW=0

usage() {
  sed -n '1,20p' "$0" | tail -n +2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --workspace-slug)
      WORKSPACE_SLUG="${2:?}"
      shift 2
      ;;
    --api-base)
      API_BASE="${2:?}"
      shift 2
      ;;
    --skip-run-now)
      SKIP_RUN_NOW=1
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
    *)
      if [[ -n "${OBJECTIVE_ID}" ]]; then
        echo "Unexpected extra argument: $1" >&2
        exit 1
      fi
      OBJECTIVE_ID="$1"
      shift
      ;;
  esac
done

if [[ -z "${OBJECTIVE_ID}" ]]; then
  echo "Usage: $0 <objective_uuid> [options]" >&2
  exit 1
fi

if [[ ! -f "${SERVER_DIR}/config/application.rb" ]]; then
  echo "Rails app not found at ${SERVER_DIR}." >&2
  exit 1
fi

# Match ./bin/run_agentkvt_api.sh so bundle/rails/psql agree with production.
export PATH="/opt/homebrew/opt/ruby/bin:/usr/local/opt/ruby/bin:/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:${PATH}"
USER_GEM_HOME="$(ruby -r rubygems -e 'print Gem.user_dir')"
export GEM_HOME="${USER_GEM_HOME}"
export GEM_PATH="${USER_GEM_HOME}"
export PATH="${USER_GEM_HOME}/bin:${PATH}"
export PGGSSENCMODE="${PGGSSENCMODE:-disable}"

if [[ -f "${SERVER_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${SERVER_DIR}/.env"
  set +a
fi

cd "${SERVER_DIR}"

echo "==> DB (rails runner) — reset in_progress -> pending for objective ${OBJECTIVE_ID}"
bundle exec rails runner \
  "o=Objective.find('${OBJECTIVE_ID}'); n=o.tasks.where(status: 'in_progress').update_all(status: 'pending', result_summary: nil); puts \"Updated rows: #{n} (in_progress -> pending)\""

if [[ "${SKIP_RUN_NOW}" -eq 1 ]]; then
  echo "==> Skipping POST run_now (--skip-run-now)"
  exit 0
fi

echo "==> API — POST ${API_BASE}/v1/objectives/${OBJECTIVE_ID}/run_now"
curl -sS -X POST "${API_BASE}/v1/objectives/${OBJECTIVE_ID}/run_now" \
  -H "X-Workspace-Slug: ${WORKSPACE_SLUG}" \
  -H "Accept: application/json" \
  -o /dev/null \
  -w "HTTP %{http_code}\n"

echo "==> API — task snapshot"
curl -sS "${API_BASE}/v1/objectives/${OBJECTIVE_ID}" \
  -H "X-Workspace-Slug: ${WORKSPACE_SLUG}" \
  -H "Accept: application/json" \
| python3 -c 'import sys,json;d=json.load(sys.stdin);o=d["objective"];print(o["goal"].splitlines()[0]);print("status:",o["status"]);
for t in d.get("tasks",[]): print(" ",t["status"],t["id"])'

echo "Done."
