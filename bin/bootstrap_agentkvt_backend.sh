#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="${REPO_ROOT}/server"
TEMPLATE_DIR="${REPO_ROOT}/templates/server_overlay"

DATA_ROOT="${HOME}/.agentkvt"
LOG_DIR="${DATA_ROOT}/logs"
BACKUP_DIR="${DATA_ROOT}/backups"
PGDATA="${DATA_ROOT}/postgres"
PGLOG="${LOG_DIR}/postgres.log"

RUBY_PREFIX="/opt/homebrew/opt/ruby"
POSTGRES_PREFIX="/opt/homebrew/opt/postgresql@16"

ensure_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required on the server Mac. Install Homebrew first." >&2
  exit 1
fi

brew list ruby >/dev/null 2>&1 || brew install ruby
brew list postgresql@16 >/dev/null 2>&1 || brew install postgresql@16

export PATH="${RUBY_PREFIX}/bin:${POSTGRES_PREFIX}/bin:${PATH}"

ensure_command gem
ensure_command initdb
ensure_command pg_ctl
ensure_command psql
ensure_command createdb

mkdir -p "${LOG_DIR}" "${BACKUP_DIR}"

gem list -i bundler >/dev/null 2>&1 || gem install bundler
gem list -i rails -v 8.0.5 >/dev/null 2>&1 || gem install rails -v 8.0.5

ensure_command bundle
ensure_command rails

if [ ! -f "${PGDATA}/PG_VERSION" ]; then
  mkdir -p "${PGDATA}"
  initdb -D "${PGDATA}"
fi

if ! pg_ctl -D "${PGDATA}" status >/dev/null 2>&1; then
  pg_ctl -D "${PGDATA}" -l "${PGLOG}" start
fi

for db_name in agentkvt_development agentkvt_test agentkvt_production; do
  if ! psql postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${db_name}'" | grep -q 1; then
    createdb "${db_name}"
  fi
done

if [ ! -f "${SERVER_DIR}/config/application.rb" ]; then
  if [ -e "${SERVER_DIR}" ]; then
    echo "Refusing to overwrite existing ${SERVER_DIR}. Move it aside or delete it first." >&2
    exit 1
  fi
  rails _8.0.5_ new "${SERVER_DIR}" --api -d postgresql --skip-git
fi

mkdir -p "${SERVER_DIR}/app/controllers" "${SERVER_DIR}/db/migrate"

cp "${TEMPLATE_DIR}/config/database.yml" "${SERVER_DIR}/config/database.yml"
cp "${TEMPLATE_DIR}/config/routes.rb" "${SERVER_DIR}/config/routes.rb"
cp "${TEMPLATE_DIR}/app/controllers/health_controller.rb" "${SERVER_DIR}/app/controllers/health_controller.rb"
cp "${TEMPLATE_DIR}/.env.example" "${SERVER_DIR}/.env.example"

find "${TEMPLATE_DIR}/db/migrate" -type f -name "*.rb" -exec cp {} "${SERVER_DIR}/db/migrate/" \;

mkdir -p "${SERVER_DIR}/log" "${SERVER_DIR}/tmp" "${SERVER_DIR}/storage"
touch "${SERVER_DIR}/log/.keep" "${SERVER_DIR}/tmp/.keep" "${SERVER_DIR}/storage/.keep"

cd "${SERVER_DIR}"
bundle install
bin/rails db:prepare

cat <<EOF

AgentKVT backend bootstrap complete.

Next steps:
1. Copy server/.env.example to server/.env and fill in secrets.
2. Start the API:

   ${REPO_ROOT}/bin/run_agentkvt_api.sh

3. Verify health:

   curl http://127.0.0.1:3000/healthz

Docs:
  ${REPO_ROOT}/Docs/MAC_BACKEND_PLAN.md
EOF
