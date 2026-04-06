#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

DATA_ROOT="${HOME}/.agentkvt"
LOG_DIR="${DATA_ROOT}/logs"
PGDATA="${DATA_ROOT}/postgres"
PGLOG="${LOG_DIR}/postgres.log"

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

if [ -f "${SERVER_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${SERVER_DIR}/.env"
  set +a
fi

RAILS_ENV_EFFECTIVE="${RAILS_ENV:-development}"
echo "AgentKVT Jobs: RAILS_ENV=${RAILS_ENV_EFFECTIVE}" >&2

cd "${SERVER_DIR}"
# PGGSSENCMODE=disable (set above) prevents the libpq GSS-probe segfault on fork.
# Use bundle exec so the same gem set resolves as Puma (avoids GemNotFound when
# bin/jobs shebang picks up a different Ruby than bundle exec rails).
exec bundle exec ruby "${SERVER_DIR}/bin/jobs" start
