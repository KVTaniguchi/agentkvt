#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

DATA_ROOT="${HOME}/.agentkvt"
LOG_DIR="${DATA_ROOT}/logs"
PGDATA="${DATA_ROOT}/postgres"
PGLOG="${LOG_DIR}/postgres.log"

# Prefer Homebrew Ruby over /usr/bin/ruby (2.6). Restrictive GEM_HOME + user gem bin
# ordering can leave /usr/bin/bundle in use and mix Homebrew Bundler with system Ruby
# (Gem::Resolver::APISet::GemParser, flaky Puma boot). Same rules as agentkvt_reset_objective_tasks.sh.
export PATH="/opt/homebrew/opt/ruby/bin:/usr/local/opt/ruby/bin:/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:${PATH}"
unset GEM_HOME GEM_PATH || true
RUBY_BIN="$(command -v ruby || true)"
if [[ -z "${RUBY_BIN}" || "${RUBY_BIN}" == /usr/bin/ruby ]]; then
  echo "ERROR: Need Homebrew Ruby on PATH before system Ruby (got: ${RUBY_BIN:-missing})." >&2
  exit 1
fi
export PATH="$(ruby -e 'print Gem.bindir'):${PATH}"
BUNDLE_BIN="$(command -v bundle || true)"
if [[ "${BUNDLE_BIN}" == /usr/bin/bundle ]]; then
  echo "ERROR: Refusing to use system Bundler at /usr/bin/bundle (wrong Ruby). PATH=${PATH}" >&2
  exit 1
fi
# libpq's GSS probe is unsafe after fork on the production macOS host.
# We only talk to the local Postgres instance here, so disable GSS auth.
export PGGSSENCMODE="${PGGSSENCMODE:-disable}"

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

# Binding: explicit BIND_IP wins. Otherwise AGENTKVT_BIND_ALL_INTERFACES=1 listens on 0.0.0.0
# (LAN + Tailscale). If unset, prefer Tailscale IPv4 when available; else localhost only.
if [ -n "${BIND_IP:-}" ]; then
  :
elif [ "${AGENTKVT_BIND_ALL_INTERFACES:-0}" = "1" ]; then
  BIND_IP="0.0.0.0"
elif [ -n "${TAILSCALE_IP:-}" ]; then
  BIND_IP="${TAILSCALE_IP}"
else
  BIND_IP="127.0.0.1"
fi

PORT="${PORT:-3000}"
RAILS_ENV_EFFECTIVE="${RAILS_ENV:-development}"

echo "AgentKVT API: RAILS_ENV=${RAILS_ENV_EFFECTIVE} bind=${BIND_IP} port=${PORT}" >&2

cd "${SERVER_DIR}"
exec bundle exec rails server -b "${BIND_IP}" -p "${PORT}"
