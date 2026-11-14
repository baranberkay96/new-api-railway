#!/usr/bin/env bash
# Tests for railway-start.sh (bash 3.2+). Run: bash test/railway-start.test.sh
# External commands (wget, psql, pg_isready, the New API binary) are replaced
# by shell functions and a fake binary, so nothing is downloaded or started.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../railway-start.sh
source "$HERE/../railway-start.sh"
set +e

PASS=0
FAIL=0
check() {
  local name=$1
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$name"
  fi
}
not() { ! "$@"; }
equals() { [[ $1 == "$2" ]] || { printf '  expected [%s] got [%s]\n' "$2" "$1"; return 1; }; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
log() { :; }
warn() { printf '%s\n' "$*" >>"$TMP/warnings"; }
sleep() { :; }

# --- validators -------------------------------------------------------------
check "port 3000 valid" valid_port 3000
check "port 65535 valid" valid_port 65535
check "port 0 invalid" not valid_port 0
check "port 70000 invalid" not valid_port 70000
check "port text invalid" not valid_port abc
check "port empty invalid" not valid_port ""

check "username root valid" valid_username root
check "username with @ . - _ valid" valid_username "a.b-c_d@e"
check "username 13 chars invalid" not valid_username "abcdefghijklm"
check "username with space invalid" not valid_username "my admin"
check "username with quote invalid" not valid_username 'ad"min'
check "username empty invalid" not valid_username ""

check "password 8 chars valid" valid_password "abcdefgh"
check "password 7 chars invalid" not valid_password "abcdefg"
check "password 129 chars invalid" not valid_password "$(printf 'a%.0s' $(seq 1 129))"
check "password 128 chars valid" valid_password "$(printf 'a%.0s' $(seq 1 128))"
check "password with newline invalid" not valid_password $'abcdefgh\nij'
check "password with quotes valid" valid_password 'ab"cd\ef gh'

check "json escape quotes and backslashes" equals "$(json_escape 'a"b\c')" 'a\"b\\c'
check "random password is 32 alphanumerics" bash -c '[[ $1 =~ ^[A-Za-z0-9]{32}$ ]]' _ "$(random_password)"

check "is_true accepts TRUE" is_true TRUE
check "is_true rejects empty" not is_true ""

# --- redis url --------------------------------------------------------------
check "redis url with user and password" equals "$(redis_host_port 'redis://default:p%40ss@redis.railway.internal:6379')" "redis.railway.internal 6379"
check "redis url without port" equals "$(redis_host_port 'redis://:secret@cache')" "cache 6379"
check "redis url with db and query" equals "$(redis_host_port 'rediss://u:p@h.example:6380/2?x=1')" "h.example 6380"
check "redis url with ipv6 literal" equals "$(redis_host_port 'redis://:p@[fd12::1]:6379')" "fd12::1 6379"

# --- port and cookie settings ------------------------------------------------
reset_env() {
  unset PORT SESSION_COOKIE_SECURE SESSION_COOKIE_TRUSTED_URL RAILWAY_PUBLIC_DOMAIN SESSION_SECRET CRYPTO_SECRET
  : >"$TMP/warnings"
}

reset_env; PORT=abc; sanitize_port
check "invalid PORT falls back to 3000" equals "$PORT" 3000
reset_env; PORT=8080; sanitize_port
check "valid PORT kept" equals "$PORT" 8080

reset_env
SESSION_COOKIE_SECURE=true SESSION_COOKIE_TRUSTED_URL="https://app.up.railway.app" RAILWAY_PUBLIC_DOMAIN=app.up.railway.app
sanitize_cookie_settings
check "secure cookie keeps own domain once" equals "${SESSION_COOKIE_TRUSTED_URL:-}" "https://app.up.railway.app"
check "secure cookie stays on" equals "${SESSION_COOKIE_SECURE:-}" true

reset_env
SESSION_COOKIE_SECURE=TRUE SESSION_COOKIE_TRUSTED_URL="https://gw.example.com/, not-a-url, http://plain.example, https://" RAILWAY_PUBLIC_DOMAIN=App.Up.Railway.App
sanitize_cookie_settings
check "invalid origins dropped, railway domain added" equals "${SESSION_COOKIE_TRUSTED_URL:-}" "https://gw.example.com,https://app.up.railway.app"
check "dropped origins are reported" grep -q "not-a-url" "$TMP/warnings"

reset_env
SESSION_COOKIE_SECURE=true SESSION_COOKIE_TRUSTED_URL="https://"
sanitize_cookie_settings
check "no usable origin turns secure cookies off" equals "${SESSION_COOKIE_SECURE:-unset}" unset
check "trusted url removed when secure is off" equals "${SESSION_COOKIE_TRUSTED_URL:-unset}" unset

reset_env
SESSION_COOKIE_SECURE=false SESSION_COOKIE_TRUSTED_URL="https://gw.example.com"
sanitize_cookie_settings
check "secure=false removes trusted url (upstream would exit)" equals "${SESSION_COOKIE_TRUSTED_URL:-unset}" unset

reset_env
SESSION_COOKIE_SECURE=maybe RAILWAY_PUBLIC_DOMAIN=x.up.railway.app
sanitize_cookie_settings
check "unknown secure value treated as true" equals "${SESSION_COOKIE_SECURE:-}" true

reset_env; SESSION_SECRET=random_string; sanitize_secrets
check "placeholder session secret removed" equals "${SESSION_SECRET:-unset}" unset


# --- trusted proxies ------------------------------------------------------------
TRUSTED_PROXIES="100.64.0.0/10, 127.0.0.0/8,::1,10.0.0.0/8,fc00::/7"; sanitize_trusted_proxies
check "valid proxy list kept" equals "$TRUSTED_PROXIES" "100.64.0.0/10,127.0.0.0/8,::1,10.0.0.0/8,fc00::/7"
TRUSTED_PROXIES="100.64.0.0/10,999.1.1.1,10.0.0.0/33,railway,fd12::1::2,2001:db8::/48"; sanitize_trusted_proxies
check "invalid proxies dropped" equals "$TRUSTED_PROXIES" "100.64.0.0/10,2001:db8::/48"
TRUSTED_PROXIES="garbage"; sanitize_trusted_proxies
check "no valid proxy falls back to the Railway default list" equals "$TRUSTED_PROXIES" "$DEFAULT_TRUSTED_PROXIES"
unset TRUSTED_PROXIES; sanitize_trusted_proxies
check "unset proxies get the Railway default list" equals "$TRUSTED_PROXIES" "$DEFAULT_TRUSTED_PROXIES"
TRUSTED_PROXIES=" None "; sanitize_trusted_proxies
check "none kept" equals "$TRUSTED_PROXIES" none
TRUSTED_PROXIES="none,10.0.0.0/8"; sanitize_trusted_proxies
check "none mixed with entries is dropped" equals "$TRUSTED_PROXIES" "10.0.0.0/8"

# --- root account settings ----------------------------------------------------
NEW_API_ROOT_USERNAME="has space" NEW_API_ROOT_PASSWORD="short"
sanitize_root_account
check "invalid username falls back to root" equals "$ROOT_USERNAME" root
check "short password marked invalid" equals "$ROOT_PASSWORD_VALID" false
check "root password not exported to New API" equals "${NEW_API_ROOT_PASSWORD:-unset}" unset

NEW_API_ROOT_USERNAME=admin NEW_API_ROOT_PASSWORD="GoodPassword123"
sanitize_root_account
check "valid username kept" equals "$ROOT_USERNAME" admin
check "valid password kept" equals "$ROOT_PASSWORD_VALID" true

NEW_API_WAIT_SECONDS=soon; sanitize_wait_seconds
check "invalid wait seconds fall back" equals "$WAIT_SECONDS" 600

# --- first-run setup on loopback ------------------------------------------------
# Fake New API binary: records the HOST it was started with, then idles.
cat >"$TMP/new-api" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${HOST:-}" >>"$FAKE_DIR/hosts"
trap 'exit 0' TERM
while :; do /bin/sleep 0.1; done
EOF
chmod +x "$TMP/new-api"
export FAKE_DIR=$TMP
NEW_API_BIN=$TMP/new-api
PORT=3000

# Fake wget: /api/status answers, /api/setup reports $FAKE_SETUP_STATUS,
# POST /api/setup stores the request body and answers $FAKE_POST_RESULT.
wget() {
  local url=${*: -1} post_file="" arg
  for arg in "$@"; do
    case $arg in --post-file=*) post_file=${arg#--post-file=} ;; esac
  done
  case $url in
    */api/status) [[ -s $TMP/hosts ]] || return 4 ;;
    */api/setup)
      if [[ -n $post_file ]]; then
        cp "$post_file" "$TMP/posted"
        printf '{"success":%s}' "$FAKE_POST_RESULT"
      else
        printf '{"data":{"status":%s},"success":true}' "$FAKE_SETUP_STATUS"
      fi
      ;;
  esac
}

: >"$TMP/hosts"; rm -f "$TMP/posted"
FAKE_SETUP_STATUS=false FAKE_POST_RESULT=true
ROOT_USERNAME=root ROOT_PASSWORD='Pa"ss\word99' ROOT_PASSWORD_VALID=true INITIALIZED_NOW=false
bootstrap_on_loopback
check "bootstrap succeeds" equals "$?" 0
check "bootstrap binds loopback only" equals "$(cat "$TMP/hosts")" 127.0.0.1
check "setup body carries escaped password" grep -qF '"password":"Pa\"ss\\word99"' "$TMP/posted"
check "setup body carries username" grep -qF '"username":"root"' "$TMP/posted"
check "setup marks this boot as initializing" equals "$INITIALIZED_NOW" true

rm -f "$TMP/posted"; INITIALIZED_NOW=false
FAKE_SETUP_STATUS=true
bootstrap_on_loopback
check "initialized instance is not set up again" not test -f "$TMP/posted"
check "initialized instance is not flagged" equals "$INITIALIZED_NOW" false

rm -f "$TMP/posted"; : >"$TMP/warnings"
FAKE_SETUP_STATUS=false ROOT_PASSWORD=short ROOT_PASSWORD_VALID=false
bootstrap_on_loopback
check "invalid password still completes setup (locked)" equals "$INITIALIZED_NOW" true
check "locked setup does not use the invalid password" not grep -qF '"password":"short"' "$TMP/posted"
check "locked setup explains the reset" grep -q "NEW_API_RESET_ROOT_PASSWORD=true" "$TMP/warnings"

FAKE_SETUP_STATUS=false FAKE_POST_RESULT=false ROOT_PASSWORD_VALID=true ROOT_PASSWORD=GoodPassword123
bootstrap_on_loopback
check "refused setup reports failure" equals "$?" 1

# ensure_initialized retries and gives up without exposing the instance
SQL_DSN="" FAKE_POST_RESULT=false
ensure_initialized
check "ensure_initialized fails after retries" equals "$?" 1

# Postgres already records the setup: no loopback boot at all
: >"$TMP/hosts"
psql() { printf '1\n'; }
SQL_DSN="postgresql://u:p@db:5432/railway"
ensure_initialized
check "recorded setup skips loopback boot" equals "$(cat "$TMP/hosts")" ""
unset -f psql

# --- options and password reset -------------------------------------------------
psql() { cat >"$TMP/sql"; printf '%s\n' "$*" >"$TMP/psql_args"; printf 'root\n'; }
INITIALIZED_NOW=true NEW_API_REGISTER_ENABLED=""
apply_initial_options
check "registration closed by default on first boot" grep -q "value=false" "$TMP/psql_args"
rm -f "$TMP/sql"
INITIALIZED_NOW=false
apply_initial_options
check "options untouched on later boots" not test -f "$TMP/sql"

rm -f "$TMP/sql"
NEW_API_RESET_ROOT_PASSWORD=true ROOT_PASSWORD=GoodPassword123 ROOT_PASSWORD_VALID=true
reset_root_password
check "reset hashes with pgcrypto bcrypt" grep -q "gen_salt('bf'" "$TMP/sql"
check "reset passes the password as a psql variable" grep -q "pw=GoodPassword123" "$TMP/psql_args"

rm -f "$TMP/sql"
ROOT_PASSWORD=$(printf 'a%.0s' $(seq 1 80))
reset_root_password
check "reset refuses passwords over 72 bytes" not test -f "$TMP/sql"

rm -f "$TMP/sql"
NEW_API_RESET_ROOT_PASSWORD=false ROOT_PASSWORD=GoodPassword123
reset_root_password
check "no reset unless requested" not test -f "$TMP/sql"

printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
