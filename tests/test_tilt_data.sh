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

# Invoke the CGI with a controlled ESP32 authentication fixture.
request_tilt() {
  WOMO_ESP32_BASE_URL='http://192.0.2.3' \
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

printf '%s' 'TEST_ONLY' > "$PASSWORD_FILE"
chmod 600 "$PASSWORD_FILE"

request_tilt
grep -Fq '{"available":true,"pitch":1.25,"roll":-2.5}' "$RESPONSE" || fail "valid JSON values were not returned"
grep -Fxq 'http://192.0.2.3/sensor/pitch' "$CURL_LOG" || fail "pitch endpoint was not requested"
grep -Fxq 'http://192.0.2.3/sensor/roll' "$CURL_LOG" || fail "roll endpoint was not requested"

WOMO_TEST_PASSWORD='TEST:slash\_quote"' \
  WOMO_ESP32_PASSWORD='TEST:slash\_quote"' \
  WOMO_DATA_DIR="$TEST_ROOT" \
  WOMO_CGI_USER='user-that-does-not-exist' \
  WOMO_CGI_GROUP='group-that-does-not-exist' \
  "$REPO_ROOT/scripts/set_womo_esp32_password.sh" >/dev/null
WOMO_TEST_CURL_PASSWORD='TEST:slash\\_quote\"' request_tilt
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
WOMO_ESP32_PASSWORD='TEST_ONLY_slash\_quote"' \
WOMO_CGI_USER='user-that-does-not-exist' \
WOMO_CGI_GROUP='group-that-does-not-exist' \
  "$REPO_ROOT/scripts/set_womo_esp32_password.sh" > "$helper_output"

generated_password="$TEST_ROOT/data/esp32-main.password"
[ "$(stat -c '%a' "$generated_password")" = "600" ] || fail "password file permissions are not 600"
[ "$(cat "$generated_password")" = 'TEST_ONLY_slash\_quote"' ] || fail "stored password changed"
! grep -Fq 'TEST_ONLY_' "$helper_output" || fail "password helper printed credential content"

if WOMO_DATA_DIR="$TEST_ROOT/rejected" \
  WOMO_ESP32_PASSWORD="$(printf 'line1\nline2')" \
  WOMO_CGI_USER='user-that-does-not-exist' \
  WOMO_CGI_GROUP='group-that-does-not-exist' \
  "$REPO_ROOT/scripts/set_womo_esp32_password.sh" >/dev/null 2>&1; then
  fail "password helper accepted a line break"
fi

echo "OK: authenticated tilt JSON, unavailable responses, and secret storage verified."
