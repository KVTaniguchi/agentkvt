#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

DATA_ROOT="${HOME}/.agentkvt"
LOG_DIR="${DATA_ROOT}/logs"
PGDATA="${DATA_ROOT}/postgres"
PGLOG="${LOG_DIR}/postgres.log"

export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/opt/postgresql@16/bin:${PATH}"
USER_GEM_HOME="$(ruby -r rubygems -e 'print Gem.user_dir')"
USER_GEM_BIN="${USER_GEM_HOME}/bin"
export GEM_HOME="${USER_GEM_HOME}"
export GEM_PATH="${USER_GEM_HOME}"
export PATH="${USER_GEM_BIN}:${PATH}"

if [ ! -f "${SERVER_DIR}/config/application.rb" ]; then
  echo "Rails app not found at ${SERVER_DIR}. Run ./bin/bootstrap_agentkvt_backend.sh first." >&2
  exit 1
fi

mkdir -p "${LOG_DIR}"

if ! pg_ctl -D "${PGDATA}" status >/dev/null 2>&1; then
  pg_ctl -D "${PGDATA}" -l "${PGLOG}" start
fi

if command -v tailscale >/dev/null 2>&1; then
  TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
else
  TAILSCALE_IP=""
fi

if [ -f "${SERVER_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${SERVER_DIR}/.env"
  set +a
fi

BIND_IP="${BIND_IP:-${TAILSCALE_IP:-127.0.0.1}}"
PORT="${PORT:-3000}"

cd "${SERVER_DIR}"
exec bundle exec rails server -b "${BIND_IP}" -p "${PORT}"
