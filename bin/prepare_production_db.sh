#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"

export PATH="/opt/homebrew/opt/ruby/bin:/opt/homebrew/opt/postgresql@16/bin:${PATH}"
USER_GEM_HOME="$(ruby -r rubygems -e 'print Gem.user_dir')"
USER_GEM_BIN="${USER_GEM_HOME}/bin"
export GEM_HOME="${USER_GEM_HOME}"
export GEM_PATH="${USER_GEM_HOME}"
export PATH="${USER_GEM_BIN}:${PATH}"

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
