#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./bin/deploy_agentkvt_backend.sh [git-ref]

Deploy the Rails backend from the current repo checkout on the server Mac.

Default git-ref: origin/main

What this script does:
- creates a backup branch at the current HEAD
- stashes any local working tree changes
- fetches origin and merges the requested git ref
- runs ./bin/prepare_production_db.sh
- restarts the API via launchd if com.agentkvt.api is installed
- falls back to Puma tmp_restart if the API is already running unmanaged
- verifies /healthz and probes a protected route to catch stale route tables
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_REF="${1:-origin/main}"
LAUNCHD_LABEL="com.agentkvt.api"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agentkvt-backend-deploy.XXXXXX")"
STASHED=0
BACKUP_BRANCH=""

cleanup() {
  rm -rf "${TMP_DIR}"
}

recover() {
  if [ "${STASHED:-0}" -eq 1 ]; then
    printf 'ERROR: Deploy failed after stash — restoring local changes...\n' >&2
    git stash pop || printf 'Could not pop stash automatically. Run: git stash list\n' >&2
  fi
}

trap 'cleanup' EXIT
trap 'recover' ERR

log() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

find_launchd_domain() {
  local candidate
  for candidate in "gui/$(id -u)" "user/$(id -u)"; do
    if launchctl print "${candidate}/${LAUNCHD_LABEL}" >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

wait_for_healthz() {
  local body_file status attempt
  body_file="${TMP_DIR}/healthz.body"

  for attempt in $(seq 1 15); do
    status="$(curl -sS -o "${body_file}" -w '%{http_code}' http://127.0.0.1:3000/healthz || true)"
    if [ "${status}" = "200" ]; then
      printf 'healthz: %s\n' "${status}"
      cat "${body_file}"
      printf '\n'
      return 0
    fi
    sleep 2
  done

  printf 'healthz probe failed after restart.\n' >&2
  if [ -f "${body_file}" ]; then
    cat "${body_file}" >&2 || true
  fi
  return 1
}

probe_runtime_routes() {
  local body_file status
  body_file="${TMP_DIR}/chat_wake.body"
  status="$(curl -sS -o "${body_file}" -w '%{http_code}' http://127.0.0.1:3000/v1/agent/chat_wake || true)"

  case "${status}" in
    200|401)
      printf 'route probe (/v1/agent/chat_wake): %s\n' "${status}"
      return 0
      ;;
    *)
      printf 'Unexpected route probe status: %s\n' "${status}" >&2
      if [ -f "${body_file}" ]; then
        cat "${body_file}" >&2 || true
      fi
      return 1
      ;;
  esac
}

restart_backend() {
  local domain

  if domain="$(find_launchd_domain)"; then
    log "Restarting backend via launchd (${domain}/${LAUNCHD_LABEL})"
    launchctl kickstart -k "${domain}/${LAUNCHD_LABEL}"
    return 0
  fi

  if pgrep -f 'puma .*\[server\]' >/dev/null 2>&1 || pgrep -f 'bin/rails server' >/dev/null 2>&1; then
    log "Restarting existing Puma process via tmp/restart.txt"
    mkdir -p "${REPO_ROOT}/server/tmp"
    touch "${REPO_ROOT}/server/tmp/restart.txt"
    return 0
  fi

  fail "No backend process found. Install ${LAUNCHD_LABEL} or start ./bin/run_agentkvt_api.sh manually."
}

cd "${REPO_ROOT}"

git rev-parse --git-dir >/dev/null 2>&1 || fail "This script must run from a git checkout."
git remote get-url origin >/dev/null 2>&1 || fail "Git remote 'origin' is required."

CURRENT_BRANCH="$(git branch --show-current || true)"
[ -n "${CURRENT_BRANCH}" ] || fail "Detached HEAD is not supported for deploys."

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_BRANCH="backup/pre-deploy-${TIMESTAMP}"

log "Creating restore point ${BACKUP_BRANCH}"
git branch "${BACKUP_BRANCH}"

if [ -n "$(git status --porcelain)" ]; then
  log "Stashing local working tree changes"
  git stash push -u -m "pre-deploy ${TIMESTAMP}"
  STASHED=1
fi

log "Fetching origin"
git fetch origin

git rev-parse --verify "${TARGET_REF}^{commit}" >/dev/null 2>&1 || fail "Git ref not found: ${TARGET_REF}"

log "Merging ${TARGET_REF} into ${CURRENT_BRANCH}"
git merge --no-edit "${TARGET_REF}"

if [ "${STASHED}" -eq 1 ]; then
  log "Restoring stashed local changes"
  git stash pop
fi

log "Preparing production database"
"${REPO_ROOT}/bin/prepare_production_db.sh"

restart_backend

log "Waiting for backend health check"
wait_for_healthz

log "Probing protected runtime route"
probe_runtime_routes

log "Deploy complete"
printf 'Current branch: %s\n' "${CURRENT_BRANCH}"
printf 'Backup branch: %s\n' "${BACKUP_BRANCH}"
printf 'HEAD: %s\n' "$(git rev-parse --short HEAD)"
