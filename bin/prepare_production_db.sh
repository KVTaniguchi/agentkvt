#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

# Match run_agentkvt_api.sh: Homebrew Ruby + Gem.bindir bundle; avoid GEM_HOME mixing with /usr/bin/bundle
# (Gem::Resolver::APISet::GemParser and flaky db:prepare).
export PATH="/opt/homebrew/opt/ruby/bin:/usr/local/opt/ruby/bin:/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:${PATH}"
unset GEM_HOME GEM_PATH || true
RUBY_BIN="$(command -v ruby || true)"
if [[ -z "${RUBY_BIN}" || "${RUBY_BIN}" == /usr/bin/ruby ]]; then
  echo "ERROR: Need Homebrew Ruby on PATH before system Ruby (got: ${RUBY_BIN:-missing})." >&2
  exit 1
fi
export PATH="$(ruby -e 'print Gem.bindir'):${PATH}"
if [[ "$(command -v bundle || true)" == /usr/bin/bundle ]]; then
  echo "ERROR: Refusing to use system Bundler at /usr/bin/bundle (wrong Ruby). PATH=${PATH}" >&2
  exit 1
fi

if [ ! -f "${SERVER_DIR}/config/application.rb" ]; then
  echo "Rails app not found at ${SERVER_DIR}." >&2
  exit 1
fi

export RAILS_ENV=production

if [ -f "${SERVER_DIR}/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "${SERVER_DIR}/.env"
  set +a
fi

if [ -z "${SECRET_KEY_BASE:-}" ]; then
  echo "SECRET_KEY_BASE is required for RAILS_ENV=production. Add it to server/.env (run: cd server && bundle exec rails secret)." >&2
  exit 1
fi

cd "${SERVER_DIR}"
exec bundle exec rails db:prepare
