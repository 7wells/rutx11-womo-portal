#!/bin/sh

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/womo-tilt-test.XXXXXX)"
PASSWORD_FILE="$TEST_ROOT/esp32-main.password"
CURL_LOG="$TEST_ROOT/curl.log"
RESPONSE="$TEST_ROOT/response"

# Remove isolated test credentials and responses on every exit.
cleanup() {
  rm -rf "$TEST_ROOT"
}

# Stop the test with a concise failure message.
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Build distinct synthetic credentials at runtime, including quoting-sensitive characters.
make_test_credential() {
  case "$1" in
    install) printf 'TEST_ONLY_install:%s\\_"' "$$" ;;
    curl_config) printf 'TEST_ONLY_install:%s\\\\_\\"' "$$" ;;
    generated) printf 'TEST_ONLY_%s_%s\\_"' "$1" "$$" ;;
    *) fail "unknown test credential role" ;;
  esac
}

# Invoke the CGI with a controlled ESP32 authentication fixture.
request_tilt() {
  WOMO_ESP32_BASE_URL="${WOMO_TEST_BASE_URL-http://example.invalid}" \
  WOMO_PORTAL_CONFIG_FILE="${WOMO_TEST_PORTAL_CONFIG_FILE:-$TEST_ROOT/missing-portal-config.js}" \
  WOMO_ESP32_PASSWORD_FILE="$PASSWORD_FILE" \
  WOMO_CURL_BIN="$REPO_ROOT/tests/fixtures/fake_tilt_curl.sh" \
  WOMO_JSONFILTER_BIN="$REPO_ROOT/tests/fixtures/fake_jsonfilter.sh" \
  WOMO_FAKE_CURL_PASSWORD="${WOMO_TEST_CURL_PASSWORD:-TEST_ONLY}" \
  WOMO_FAKE_TILT_CURL_LOG="$CURL_LOG" \
  WOMO_FAKE_TILT_FAILURE="${WOMO_FAKE_TILT_FAILURE:-}" \
  WOMO_FAKE_PITCH_JSON="${WOMO_FAKE_PITCH_JSON:-}" \
  WOMO_FAKE_ROLL_JSON="${WOMO_FAKE_ROLL_JSON:-}" \
  sh "$REPO_ROOT/web/cgi-bin/tilt.json" > "$RESPONSE"
}

trap cleanup 0 1 2 15

install_credential=$(make_test_credential install)
curl_credential=$(make_test_credential curl_config)
generated_credential=$(make_test_credential generated)

printf '%s' 'TEST_ONLY' > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

request_tilt
grep -Fq '{"available":true,"pitch":1.25,"roll":-2.5}' "$RESPONSE" || fail "valid JSON values were not returned"
grep -Fxq 'http://example.invalid/sensor/pitch' "$CURL_LOG" || fail "pitch endpoint was not requested"
grep -Fxq 'http://example.invalid/sensor/roll' "$CURL_LOG" || fail "roll endpoint was not requested"

printf '%s\n' "  esp32MainUrl: 'http://example.invalid'," > "$TEST_ROOT/portal-config.js"
WOMO_TEST_BASE_URL='' WOMO_TEST_PORTAL_CONFIG_FILE="$TEST_ROOT/portal-config.js" request_tilt
grep -Fq '{"available":true,"pitch":1.25,"roll":-2.5}' "$RESPONSE" || fail "installed ESP32 URL was not used"
WOMO_TEST_BASE_URL='' request_tilt
grep -Fq '{"available":false}' "$RESPONSE" || fail "missing ESP32 URL was not disabled"

WOMO_TEST_PASSWORD="$install_credential" \
  WOMO_ESP32_PASSWORD="$install_credential" \
  WOMO_DATA_DIR="$TEST_ROOT" \
  WOMO_CGI_USER='user-that-does-not-exist' \
  WOMO_CGI_GROUP='group-that-does-not-exist' \
  "$REPO_ROOT/scripts/set_womo_esp32_password.sh" >/dev/null
WOMO_TEST_CURL_PASSWORD="$curl_credential" request_tilt
grep -Fq '{"available":true,"pitch":1.25,"roll":-2.5}' "$RESPONSE" || fail "special password characters changed"

printf '%s' 'TEST_ONLY' > "$PASSWORD_FILE"

WOMO_FAKE_TILT_FAILURE=roll request_tilt
grep -Fq 'Status: 503 Service Unavailable' "$RESPONSE" || fail "ESP32 request failure did not return 503"
grep -Fq '{"available":false}' "$RESPONSE" || fail "ESP32 request failure was not marked unavailable"
! grep -Fq '"pitch"' "$RESPONSE" || fail "partial sensor values leaked into an error response"

WOMO_FAKE_PITCH_JSON='{"state":"invalid"}' request_tilt
grep -Fq '{"available":false}' "$RESPONSE" || fail "missing JSON value was not rejected"

rm -f "$PASSWORD_FILE"
request_tilt
grep -Fq '{"available":false}' "$RESPONSE" || fail "missing credentials were not rejected"

helper_output="$TEST_ROOT/helper-output"
WOMO_DATA_DIR="$TEST_ROOT/data" \
WOMO_ESP32_PASSWORD="$generated_credential" \
WOMO_CGI_USER='user-that-does-not-exist' \
WOMO_CGI_GROUP='group-that-does-not-exist' \
  "$REPO_ROOT/scripts/set_womo_esp32_password.sh" > "$helper_output"

generated_password="$TEST_ROOT/data/esp32-main.password"
[ "$(stat -c '%a' "$generated_password")" = "600" ] || fail "password file permissions are not 600"
[ "$(cat "$generated_password")" = "$generated_credential" ] || fail "stored password changed"
! grep -Fq 'TEST_ONLY_' "$helper_output" || fail "password helper printed credential content"

if WOMO_DATA_DIR="$TEST_ROOT/rejected" \
  WOMO_ESP32_PASSWORD="$(printf 'line1\nline2')" \
  WOMO_CGI_USER='user-that-does-not-exist' \
  WOMO_CGI_GROUP='group-that-does-not-exist' \
  "$REPO_ROOT/scripts/set_womo_esp32_password.sh" >/dev/null 2>&1; then
  fail "password helper accepted a line break"
fi

echo "OK: authenticated tilt JSON, unavailable responses, and secret storage verified."
