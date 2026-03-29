#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

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

# server/.env often sets GEM_HOME / PATH for other tools — that mixes Homebrew Ruby 4 with
# system Ruby 2.6 and triggers Gem::Resolver::APISet::GemParser. Re-apply a clean Bundler
# environment *after* sourcing .env (same idea as run_agentkvt_api.sh, but explicit ruby path).
if [[ -x /opt/homebrew/opt/ruby/bin/ruby ]]; then
  HOMEBREW_RUBY="/opt/homebrew/opt/ruby/bin/ruby"
elif [[ -x /usr/local/opt/ruby/bin/ruby ]]; then
  HOMEBREW_RUBY="/usr/local/opt/ruby/bin/ruby"
else
  echo "ERROR: Homebrew Ruby not found at /opt/homebrew/opt/ruby/bin/ruby or /usr/local/opt/ruby/bin/ruby" >&2
  exit 1
fi

unset GEM_HOME GEM_PATH || true
export PATH="/opt/homebrew/opt/ruby/bin:/usr/local/opt/ruby/bin:/opt/homebrew/opt/postgresql@16/bin:/usr/local/opt/postgresql@16/bin:${PATH}"
export PATH="$("${HOMEBREW_RUBY}" -e 'print Gem.bindir'):${PATH}"

BUNDLE_BIN="$(command -v bundle || true)"
if [[ -z "${BUNDLE_BIN}" || "${BUNDLE_BIN}" == /usr/bin/bundle ]]; then
  echo "ERROR: Need Bundler from Homebrew Ruby (got: ${BUNDLE_BIN:-missing}). PATH=${PATH}" >&2
  exit 1
fi

cd "${SERVER_DIR}"
exec "${HOMEBREW_RUBY}" -S bundle exec rails db:prepare
