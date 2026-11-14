#!/usr/bin/env bash
# railway-start: Railway entrypoint for New API.
#
# Written for this community template (see NOTICE.md). It runs the upstream
# New API binary unmodified and only prepares its environment:
#   1. Deploy-form values never fail the deploy: invalid values are replaced by
#      safe defaults with a warning (template STANDARD rule 29).
#   2. Waits for Postgres and Redis, because New API exits at startup when
#      either is unreachable.
#   3. First-run security: upstream leaves a fresh instance uninitialized, and
#      the first visitor of /setup becomes root. This script starts New API on
#      127.0.0.1 only, completes the setup with NEW_API_ROOT_USERNAME and
#      NEW_API_ROOT_PASSWORD through upstream's own /api/setup endpoint, then
#      restarts it on the public port. The setup page is never reachable
#      from outside.
#   4. Optional root password reset (NEW_API_RESET_ROOT_PASSWORD=true).
set -uo pipefail
export LC_ALL=C.UTF-8

readonly DEFAULT_PORT=3000
readonly DEFAULT_ROOT_USERNAME=root
readonly DEFAULT_WAIT_SECONDS=600
readonly BOOT_ATTEMPTS=5
NEW_API_BIN=${NEW_API_BIN:-/new-api}

log() { printf '[railway-start] %s\n' "$*" >&2; }
warn() { printf '[railway-start] WARNING: %s\n' "$*" >&2; }

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

is_true() {
  case "$(lower "$1")" in
    true | 1 | yes | on) return 0 ;;
    *) return 1 ;;
  esac
}

valid_port() {
  [[ $1 =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

valid_username() {
  # Upstream's setup accepts at most 12 characters. Restricting the character
  # set keeps the value safe to embed in JSON without an encoder.
  [[ $1 =~ ^[A-Za-z0-9_.@-]{1,12}$ ]]
}

valid_password() {
  # Upstream requires 8 to 128 characters. Control characters are refused so
  # the value can be embedded in JSON with simple escaping.
  local value=$1
  ((${#value} >= 8 && ${#value} <= 128)) && [[ ! $value =~ [[:cntrl:]] ]]
}

json_escape() {
  local value=${1//\\/\\\\}
  printf '%s' "${value//\"/\\\"}"
}

random_password() {
  local value
  value=$(head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
  printf '%s' "$value"
}

is_postgres_dsn() {
  [[ ${1:-} == postgres://* || ${1:-} == postgresql://* ]]
}

# Prints "host port" for a redis:// or rediss:// URL (default port 6379).
redis_host_port() {
  local rest=${1#*://}
  rest=${rest##*@}
  rest=${rest%%/*}
  rest=${rest%%\?*}
  local host port=6379
  if [[ $rest == \[* ]]; then
    host=${rest%%]*}
    host=${host#[}
    [[ $rest == *]:* ]] && port=${rest##*]:}
  else
    host=${rest%%:*}
    [[ $rest == *:* ]] && port=${rest##*:}
  fi
  printf '%s %s' "$host" "$port"
}

# Keeps only https origins that upstream's NormalizeOrigin accepts
# (scheme and host, optional port, optional trailing slash).
filter_origins() {
  local raw=$1 item kept=()
  IFS=',' read -ra items <<<"$raw"
  for item in ${items[@]+"${items[@]}"}; do
    item=${item//[[:space:]]/}
    [[ -z $item ]] && continue
    if [[ $item =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?/?$ ]]; then
      kept+=("${item%/}")
    else
      warn "SESSION_COOKIE_TRUSTED_URL: ignoring '$item' (expected https://{host})"
    fi
  done
  local IFS=','
  printf '%s' "${kept[*]+"${kept[*]}"}"
}

sanitize_port() {
  if ! valid_port "${PORT:-}"; then
    [[ -n ${PORT:-} ]] && warn "PORT='${PORT}' is not a valid port; using ${DEFAULT_PORT}"
    PORT=$DEFAULT_PORT
  fi
  export PORT
}

sanitize_secrets() {
  if [[ ${SESSION_SECRET:-} == random_string ]]; then
    warn "SESSION_SECRET is upstream's placeholder 'random_string'; ignoring it"
    unset SESSION_SECRET
  fi
  if [[ -z ${SESSION_SECRET:-} ]]; then
    warn "SESSION_SECRET is empty: logins reset on every restart and replicas cannot share sessions"
  fi
  if [[ -z ${CRYPTO_SECRET:-} ]]; then
    warn "CRYPTO_SECRET is empty: New API falls back to SESSION_SECRET"
  fi
}

sanitize_cookie_settings() {
  local secure=${SESSION_COOKIE_SECURE:-} origins
  origins=$(filter_origins "${SESSION_COOKIE_TRUSTED_URL:-}")
  if [[ -n ${RAILWAY_PUBLIC_DOMAIN:-} ]]; then
    local own
    own="https://$(lower "$RAILWAY_PUBLIC_DOMAIN")"
    [[ ",$(lower "$origins")," == *",${own},"* ]] || origins=${origins:+$origins,}$own
  fi
  case "$(lower "$secure")" in
    "" | false | 0 | no | off)
      unset SESSION_COOKIE_SECURE SESSION_COOKIE_TRUSTED_URL
      return
      ;;
    true) ;;
    *) warn "SESSION_COOKIE_SECURE='${secure}' is not true/false; using true" ;;
  esac
  if [[ -z $origins ]]; then
    warn "no valid https origin for secure session cookies; using SESSION_COOKIE_SECURE=false"
    unset SESSION_COOKIE_SECURE SESSION_COOKIE_TRUSTED_URL
    return
  fi
  export SESSION_COOKIE_SECURE=true SESSION_COOKIE_TRUSTED_URL=$origins
}

sanitize_root_account() {
  ROOT_USERNAME=${NEW_API_ROOT_USERNAME:-}
  if ! valid_username "$ROOT_USERNAME"; then
    warn "NEW_API_ROOT_USERNAME must be 1-12 characters of A-Z a-z 0-9 _ . @ -; using '${DEFAULT_ROOT_USERNAME}'"
    ROOT_USERNAME=$DEFAULT_ROOT_USERNAME
  fi
  ROOT_PASSWORD=${NEW_API_ROOT_PASSWORD:-}
  ROOT_PASSWORD_VALID=true
  if ! valid_password "$ROOT_PASSWORD"; then
    ROOT_PASSWORD_VALID=false
  fi
  # The root password must not be inherited by New API itself.
  unset NEW_API_ROOT_PASSWORD
}

sanitize_wait_seconds() {
  WAIT_SECONDS=${NEW_API_WAIT_SECONDS:-$DEFAULT_WAIT_SECONDS}
  if ! [[ $WAIT_SECONDS =~ ^[0-9]{1,5}$ ]]; then
    warn "NEW_API_WAIT_SECONDS='${WAIT_SECONDS}' is not a number; using ${DEFAULT_WAIT_SECONDS}"
    WAIT_SECONDS=$DEFAULT_WAIT_SECONDS
  fi
}

default_node_name() {
  if [[ -z ${NODE_NAME:-} && -n ${RAILWAY_REPLICA_ID:-} ]]; then
    export NODE_NAME="railway-${RAILWAY_REPLICA_ID:0:8}"
  fi
}

psql_run() {
  psql -X -q -t -A -v ON_ERROR_STOP=1 -d "$SQL_DSN" "$@"
}

wait_for_postgres() {
  is_postgres_dsn "${SQL_DSN:-}" || return 0
  local deadline=$((SECONDS + WAIT_SECONDS))
  until pg_isready -q -t 5 -d "$SQL_DSN"; do
    if ((SECONDS >= deadline)); then
      warn "Postgres is not accepting connections after ${WAIT_SECONDS}s; starting anyway"
      return 0
    fi
    log "waiting for Postgres..."
    sleep 3
  done
  log "Postgres is ready"
}

wait_for_redis() {
  [[ -n ${REDIS_CONN_STRING:-} ]] || return 0
  local host port
  read -r host port <<<"$(redis_host_port "$REDIS_CONN_STRING")"
  if [[ -z $host ]] || ! valid_port "$port"; then
    warn "cannot read host and port from REDIS_CONN_STRING; not waiting for Redis"
    return 0
  fi
  local deadline=$((SECONDS + WAIT_SECONDS))
  until timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; do
    if ((SECONDS >= deadline)); then
      warn "Redis is not reachable after ${WAIT_SECONDS}s; starting anyway"
      return 0
    fi
    log "waiting for Redis..."
    sleep 3
  done
  log "Redis is ready"
}

# 0 = Postgres says the setup is done; 1 = not done or unknown.
setup_recorded_in_db() {
  is_postgres_dsn "${SQL_DSN:-}" || return 1
  [[ $(psql_run -c 'SELECT 1 FROM setups LIMIT 1' 2>/dev/null) == 1 ]]
}

local_url() { printf 'http://127.0.0.1:%s%s' "$PORT" "$1"; }

wait_for_local_api() {
  local pid=$1 deadline=$((SECONDS + 300))
  until wget -q -T 5 -O /dev/null "$(local_url /api/status)"; do
    kill -0 "$pid" 2>/dev/null || return 1
    ((SECONDS >= deadline)) && return 1
    sleep 1
  done
}

post_setup() {
  local password=$1 body_file response
  body_file=$(mktemp)
  chmod 600 "$body_file"
  printf '{"username":"%s","password":"%s","confirmPassword":"%s","SelfUseModeEnabled":false,"DemoSiteEnabled":false}' \
    "$(json_escape "$ROOT_USERNAME")" "$(json_escape "$password")" "$(json_escape "$password")" >"$body_file"
  response=$(wget -q -T 30 -O - --header='Content-Type: application/json' --post-file="$body_file" "$(local_url /api/setup)")
  rm -f "$body_file"
  [[ $response =~ \"success\":[[:space:]]*true ]] && return 0
  warn "setup was refused: $(printf '%s' "$response" | tr -d '\n' | head -c 300)"
  return 1
}

# Runs New API on loopback once and completes the first-run setup.
# Sets INITIALIZED_NOW=true when this boot created the root account.
bootstrap_on_loopback() {
  local pid status password
  HOST=127.0.0.1 "$NEW_API_BIN" --log-dir= &
  pid=$!
  trap 'kill -TERM "$pid" 2>/dev/null; wait "$pid"; exit 143' TERM INT
  if ! wait_for_local_api "$pid"; then
    kill -TERM "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    trap - TERM INT
    return 1
  fi
  status=$(wget -q -T 10 -O - "$(local_url /api/setup)")
  local result=0
  if [[ $status =~ \"status\":[[:space:]]*true ]]; then
    log "New API is already initialized"
  else
    password=$ROOT_PASSWORD
    if [[ $ROOT_PASSWORD_VALID != true ]]; then
      warn "NEW_API_ROOT_PASSWORD must be 8-128 characters without control characters."
      warn "The root account is created with a random password that is not stored anywhere."
      warn "To log in: set NEW_API_ROOT_PASSWORD to a valid value and NEW_API_RESET_ROOT_PASSWORD=true, then redeploy."
      password=$(random_password)
    fi
    if post_setup "$password"; then
      log "root account '${ROOT_USERNAME}' created; setup completed on loopback"
      INITIALIZED_NOW=true
    else
      result=1
    fi
  fi
  kill -TERM "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  trap - TERM INT
  return "$result"
}

ensure_initialized() {
  INITIALIZED_NOW=false
  if setup_recorded_in_db; then
    log "setup already recorded in Postgres"
    return 0
  fi
  local attempt
  for ((attempt = 1; attempt <= BOOT_ATTEMPTS; attempt++)); do
    bootstrap_on_loopback && return 0
    warn "first-run setup attempt ${attempt}/${BOOT_ATTEMPTS} failed; retrying in $((attempt * 5))s"
    sleep $((attempt * 5))
  done
  return 1
}

apply_initial_options() {
  [[ $INITIALIZED_NOW == true ]] || return 0
  local register=false
  is_true "${NEW_API_REGISTER_ENABLED:-false}" && register=true
  if ! is_postgres_dsn "${SQL_DSN:-}"; then
    log "self-registration stays at upstream's default (SQL_DSN is not Postgres)"
    return 0
  fi
  if psql_run -v value="$register" >/dev/null <<'SQL'; then
INSERT INTO options ("key", value) VALUES ('RegisterEnabled', :'value')
ON CONFLICT ("key") DO UPDATE SET value = EXCLUDED.value;
SQL
    log "self-registration enabled: ${register} (change it later under Settings)"
  else
    warn "could not store the self-registration setting; check it under Settings"
  fi
}

reset_root_password() {
  is_true "${NEW_API_RESET_ROOT_PASSWORD:-false}" || return 0
  if [[ $ROOT_PASSWORD_VALID != true ]] || ((${#ROOT_PASSWORD} > 72)); then
    warn "NEW_API_RESET_ROOT_PASSWORD=true needs NEW_API_ROOT_PASSWORD with 8-72 characters; no reset"
    return 0
  fi
  if ! is_postgres_dsn "${SQL_DSN:-}"; then
    warn "NEW_API_RESET_ROOT_PASSWORD works with Postgres only; no reset"
    return 0
  fi
  local updated
  if updated=$(psql_run -v pw="$ROOT_PASSWORD" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
WITH changed AS (
  UPDATE users SET password = crypt(:'pw', gen_salt('bf', 10))
  WHERE role = 100 AND deleted_at IS NULL
  RETURNING username
)
SELECT string_agg(username, ',') FROM changed;
SQL
  ); then
    log "root password reset for: ${updated:-no root user found}. Set NEW_API_RESET_ROOT_PASSWORD=false again."
  else
    warn "root password reset failed"
  fi
}

main() {
  sanitize_port
  sanitize_secrets
  sanitize_cookie_settings
  sanitize_root_account
  sanitize_wait_seconds
  default_node_name
  wait_for_postgres
  wait_for_redis
  if ! ensure_initialized; then
    # Never expose an uninitialized instance: its setup page would be public.
    warn "first-run setup did not complete; exiting so Railway restarts the service"
    exit 1
  fi
  apply_initial_options
  reset_root_password
  unset ROOT_PASSWORD
  log "starting New API on port ${PORT}"
  exec "$NEW_API_BIN" --log-dir= "$@"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  main "$@"
fi
