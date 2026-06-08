#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# shellcheck disable=SC2089,SC2090  # JSON strings stored in variables are intentional
# ==============================================================================
# test_api.bats — Unit tests for scripts/lib/api.sh
#
# Covers:
#   rating_to_letter, format_duration, safe_jq,
#   sonar_api_get (with mocked curl),
#   check_connectivity (with mocked sonar_api_get),
#   sonar_api_paginated (with mocked sonar_api_get)
#
# Note: the curl mock captures the -o outfile path and returns the configured
#   $MOCK_CURL_BODY / $MOCK_CURL_STATUS, but does not assert which other flags
#   are passed.  Its purpose is to test the logic above curl, not curl itself.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

# shellcheck source=helpers.bash
load 'helpers'

teardown() {
  [[ -n "${TEST_API_TMP_FILE:-}" ]] && rm -f "$TEST_API_TMP_FILE"
  [[ -n "${TEST_API_BLOCKED_PARENT_FILE:-}" ]] && rm -f "$TEST_API_BLOCKED_PARENT_FILE"
  [[ -n "${TEST_API_BLOCKED_TMP_DIR:-}" ]] && rm -rf "$TEST_API_BLOCKED_TMP_DIR"
  unset TEST_API_TMP_FILE TEST_API_BLOCKED_PARENT_FILE TEST_API_BLOCKED_TMP_DIR
  unset SONAR_REPORT_TMP_DIR
  unset -f mktemp 2>/dev/null || true
}

setup() {
  # Source api.sh — provides all functions under test
  # shellcheck source=../scripts/lib/api.sh
  source "${REPO_ROOT}/scripts/lib/api.sh"

  # Self-contained curl mock: writes $MOCK_CURL_BODY to the -o file and
  # prints $MOCK_CURL_STATUS. Must be self-contained (no helper calls) so
  # that it works correctly when invoked inside bats' run subshell.
  curl() {
    local outfile=""
    local i=0
    local args=("$@")
    while [[ $i -lt ${#args[@]} ]]; do
      if [[ "${args[$i]}" == "-o" ]]; then
        outfile="${args[$((i + 1))]}"
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
    done
    [[ -n "$outfile" ]] && printf '%s' "${MOCK_CURL_BODY:-}" >"$outfile"
    printf '%s' "${MOCK_CURL_STATUS:-200}"
  }
  export -f curl

  # Provide required env vars
  export SONAR_URL="http://sonar.example.com"
  export SONAR_TOKEN="test-token"
  export SONAR_PROJECT_KEY="test-project"
}

# ===========================================================================
# Project-local temp helpers
# ===========================================================================

@test "create_temp_file: creates files under project tmp" {
  local tmp_file
  tmp_file=$(create_temp_file)

  [[ "$tmp_file" == "${REPO_ROOT}/tmp/sonar-report."* ]]
  [ -f "$tmp_file" ]

  rm -f "$tmp_file"
}

@test "create_temp_dir: creates directories under project tmp" {
  local tmp_dir
  tmp_dir=$(create_temp_dir)

  [[ "$tmp_dir" == "${REPO_ROOT}/tmp/sonar-report."* ]]
  [ -d "$tmp_dir" ]

  rm -rf "$tmp_dir"
}

@test "create_temp_file: falls back to system tmp when preferred dir cannot be created" {
  TEST_API_BLOCKED_PARENT_FILE=$(mktemp)

  SONAR_REPORT_TMP_DIR="${TEST_API_BLOCKED_PARENT_FILE}/blocked"

  TEST_API_TMP_FILE=$(create_temp_file)
  local system_tmp_root
  system_tmp_root="${TMPDIR:-/tmp}"
  system_tmp_root="${system_tmp_root%/}"

  [[ "$TEST_API_TMP_FILE" == "${system_tmp_root}/"* ]]
  [[ "$TEST_API_TMP_FILE" != "${TEST_API_BLOCKED_PARENT_FILE}/"* ]]
  [[ "$(basename "$TEST_API_TMP_FILE")" == "sonar-report."* ]]
  [ -f "$TEST_API_TMP_FILE" ]
}

@test "create_temp_file: falls back to system tmp when the preferred dir vanishes before mktemp" {
  TEST_API_BLOCKED_TMP_DIR=$(mktemp -d)
  local preferred_template="${TEST_API_BLOCKED_TMP_DIR}/sonar-report.XXXXXX"
  SONAR_REPORT_TMP_DIR="$TEST_API_BLOCKED_TMP_DIR"

  mktemp() {
    if [[ "${1:-}" == "$preferred_template" ]]; then
      command rm -rf "$TEST_API_BLOCKED_TMP_DIR"
      return 1
    fi
    command mktemp "$@"
  }

  TEST_API_TMP_FILE=$(create_temp_file)
  local system_tmp_root
  system_tmp_root="${TMPDIR:-/tmp}"
  system_tmp_root="${system_tmp_root%/}"

  [[ "$TEST_API_TMP_FILE" == "${system_tmp_root}/"* ]]
  [[ "$TEST_API_TMP_FILE" != "${TEST_API_BLOCKED_TMP_DIR}/"* ]]
  [[ "$(basename "$TEST_API_TMP_FILE")" == "sonar-report."* ]]
  [ -f "$TEST_API_TMP_FILE" ]
}

# ===========================================================================
# rating_to_letter
# ===========================================================================

@test "rating_to_letter: 1 → A" {
  run rating_to_letter "1"
  [ "$status" -eq 0 ]
  [ "$output" = "A" ]
}

@test "rating_to_letter: 2 → B" {
  run rating_to_letter "2"
  [ "$status" -eq 0 ]
  [ "$output" = "B" ]
}

@test "rating_to_letter: 3 → C" {
  run rating_to_letter "3"
  [ "$status" -eq 0 ]
  [ "$output" = "C" ]
}

@test "rating_to_letter: 4 → D" {
  run rating_to_letter "4"
  [ "$status" -eq 0 ]
  [ "$output" = "D" ]
}

@test "rating_to_letter: 5 → E" {
  run rating_to_letter "5"
  [ "$status" -eq 0 ]
  [ "$output" = "E" ]
}

@test "rating_to_letter: float 1.0 → A" {
  run rating_to_letter "1.0"
  [ "$status" -eq 0 ]
  [ "$output" = "A" ]
}

@test "rating_to_letter: float 3.0 → C" {
  run rating_to_letter "3.0"
  [ "$status" -eq 0 ]
  [ "$output" = "C" ]
}

@test "rating_to_letter: 0 → ?" {
  run rating_to_letter "0"
  [ "$status" -eq 0 ]
  [ "$output" = "?" ]
}

@test "rating_to_letter: unknown value → ?" {
  run rating_to_letter "9"
  [ "$status" -eq 0 ]
  [ "$output" = "?" ]
}

@test "rating_to_letter: empty → ?" {
  run rating_to_letter ""
  [ "$status" -eq 0 ]
  [ "$output" = "?" ]
}

# ===========================================================================
# format_duration
# ===========================================================================

@test "format_duration: 0 minutes → 0min" {
  run format_duration "0"
  [ "$status" -eq 0 ]
  [ "$output" = "0min" ]
}

@test "format_duration: 45 minutes → 45min" {
  run format_duration "45"
  [ "$status" -eq 0 ]
  [ "$output" = "45min" ]
}

@test "format_duration: 59 minutes → 59min" {
  run format_duration "59"
  [ "$status" -eq 0 ]
  [ "$output" = "59min" ]
}

@test "format_duration: 60 minutes → 1h 0min" {
  run format_duration "60"
  [ "$status" -eq 0 ]
  [ "$output" = "1h 0min" ]
}

@test "format_duration: 90 minutes → 1h 30min" {
  run format_duration "90"
  [ "$status" -eq 0 ]
  [ "$output" = "1h 30min" ]
}

@test "format_duration: 1440 minutes → 1d 0h" {
  run format_duration "1440"
  [ "$status" -eq 0 ]
  [ "$output" = "1d 0h" ]
}

@test "format_duration: 1500 minutes → 1d 1h" {
  run format_duration "1500"
  [ "$status" -eq 0 ]
  [ "$output" = "1d 1h" ]
}

@test "format_duration: float 120.0 → 2h 0min" {
  run format_duration "120.0"
  [ "$status" -eq 0 ]
  [ "$output" = "2h 0min" ]
}

# ===========================================================================
# safe_jq
# ===========================================================================

@test "safe_jq: extracts existing key" {
  run safe_jq '{"name":"Alice","age":30}' '.name'
  [ "$status" -eq 0 ]
  [ "$output" = "Alice" ]
}

@test "safe_jq: missing key returns default N/A" {
  run safe_jq '{"name":"Alice"}' '.missing'
  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "safe_jq: missing key with custom default" {
  run safe_jq '{"name":"Alice"}' '.missing' "0"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "safe_jq: null value returns default" {
  run safe_jq '{"value":null}' '.value'
  [ "$status" -eq 0 ]
  [ "$output" = "N/A" ]
}

@test "safe_jq: numeric value is extracted" {
  run safe_jq '{"count":42}' '.count'
  [ "$status" -eq 0 ]
  [ "$output" = "42" ]
}

@test "safe_jq: nested key extraction" {
  run safe_jq '{"meta":{"key":"my-project"}}' '.meta.key'
  [ "$status" -eq 0 ]
  [ "$output" = "my-project" ]
}

# ===========================================================================
# sonar_api_get — with mocked curl
# ===========================================================================

@test "sonar_api_get: returns body on HTTP 200" {
  MOCK_CURL_STATUS="200"
  MOCK_CURL_BODY='{"status":"UP"}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY

  run sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  [ "$output" = '{"status":"UP"}' ]
}

@test "sonar_api_get: fails on HTTP 401" {
  MOCK_CURL_STATUS="401"
  MOCK_CURL_BODY='{"errors":[{"msg":"Unauthorized"}]}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY

  run sonar_api_get "system/status"
  [ "$status" -ne 0 ]
}

@test "sonar_api_get: fails on HTTP 404" {
  MOCK_CURL_STATUS="404"
  MOCK_CURL_BODY='{"errors":[{"msg":"Not found"}]}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY

  run sonar_api_get "projects/search"
  [ "$status" -ne 0 ]
}

@test "sonar_api_get: fails on HTTP 500" {
  MOCK_CURL_STATUS="500"
  MOCK_CURL_BODY='Internal Server Error'
  export MOCK_CURL_STATUS MOCK_CURL_BODY

  run sonar_api_get "system/status"
  [ "$status" -ne 0 ]
}

@test "sonar_api_get: error message logged on HTTP 4xx" {
  MOCK_CURL_STATUS="403"
  MOCK_CURL_BODY='{"errors":[{"msg":"Forbidden"}]}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY

  run sonar_api_get "system/status"
  [ "$status" -ne 0 ]
  [[ "$output" == *"403"* ]]
}

# ===========================================================================
# check_connectivity — mocking sonar_api_get
# ===========================================================================

@test "check_connectivity: succeeds when status UP and auth valid" {
  sonar_api_get() {
    case "$1" in
      system/status)          cat "${FIXTURES}/system_status.json" ;;
      authentication/validate) cat "${FIXTURES}/auth_validate.json" ;;
    esac
  }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -eq 0 ]
  [[ "$output" == *"Connected"* ]]
}

@test "check_connectivity: fails when status is not UP" {
  sonar_api_get() {
    case "$1" in
      system/status)           cat "${FIXTURES}/system_status_starting.json" ;;
      authentication/validate) cat "${FIXTURES}/auth_validate.json" ;;
    esac
  }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -ne 0 ]
}

@test "check_connectivity: fails when auth token is invalid" {
  sonar_api_get() {
    case "$1" in
      system/status)           cat "${FIXTURES}/system_status.json" ;;
      authentication/validate) cat "${FIXTURES}/auth_validate_invalid.json" ;;
    esac
  }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -ne 0 ]
}

@test "check_connectivity: fails when SONAR_URL is empty" {
  SONAR_URL=""
  run check_connectivity
  [ "$status" -ne 0 ]
}

@test "check_connectivity: fails when SONAR_TOKEN is empty" {
  SONAR_TOKEN=""
  run check_connectivity
  [ "$status" -ne 0 ]
}

@test "check_connectivity: fails when system/status API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -ne 0 ]
}

# ===========================================================================
# sonar_api_paginated — mocking sonar_api_get
# ===========================================================================

@test "sonar_api_paginated: returns all items from a single page" {
  sonar_api_get() {
    echo '{"issues":[{"key":"A1"},{"key":"A2"}],"paging":{"total":2}}'
  }
  export -f sonar_api_get

  run sonar_api_paginated "issues/search" ".issues" 0 "componentKeys=test"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "sonar_api_paginated: accumulates items across multiple pages" {
  export _CALL_FILE
  _CALL_FILE=$(counter_file_new)

  sonar_api_get() {
    local n
    n=$(counter_file_increment "$_CALL_FILE")
    if [[ "$n" -eq 1 ]]; then
      echo '{"issues":[{"key":"A1"},{"key":"A2"}],"paging":{"total":3}}'
    else
      echo '{"issues":[{"key":"A3"}],"paging":{"total":3}}'
    fi
  }
  export -f sonar_api_get counter_file_increment

  run sonar_api_paginated "issues/search" ".issues" 0 "componentKeys=test"
  rm -f "$_CALL_FILE"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 3 ]
}

@test "sonar_api_paginated: returns empty array when no items" {
  sonar_api_get() {
    echo '{"issues":[],"paging":{"total":0}}'
  }
  export -f sonar_api_get

  run sonar_api_paginated "issues/search" ".issues" 0
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "sonar_api_paginated: respects max_pages limit" {
  export _CALL_FILE2
  _CALL_FILE2=$(counter_file_new)

  sonar_api_get() {
    local n
    n=$(counter_file_increment "$_CALL_FILE2")
    echo '{"issues":[{"key":"A'"$n"'"}],"paging":{"total":999}}'
  }
  # Silence the log_warn about max pages so $output is pure JSON
  log_warn() { :; }
  export -f sonar_api_get log_warn counter_file_increment

  run sonar_api_paginated "issues/search" ".issues" 2 "componentKeys=test"
  rm -f "$_CALL_FILE2"
  [ "$status" -eq 0 ]
  # Should have stopped at 2 pages → 2 items
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "sonar_api_paginated: returns failure when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run sonar_api_paginated "issues/search" ".issues" 0
  [ "$status" -ne 0 ]
}

# ===========================================================================
# detect_sonarcloud
# ===========================================================================

@test "detect_sonarcloud: sets SONAR_CLOUD=true for sonarcloud.io URL" {
  SONAR_URL="https://sonarcloud.io"
  SONAR_CLOUD=false

  detect_sonarcloud

  [ "$SONAR_CLOUD" = "true" ]
}

@test "detect_sonarcloud: sets SONAR_CLOUD=true for subdomain of sonarcloud.io" {
  SONAR_URL="https://api.sonarcloud.io"
  SONAR_CLOUD=false

  detect_sonarcloud

  [ "$SONAR_CLOUD" = "true" ]
}

@test "detect_sonarcloud: does not change SONAR_CLOUD for non-SonarCloud URL" {
  SONAR_URL="http://sonar.example.com"
  SONAR_CLOUD=false

  detect_sonarcloud

  [ "$SONAR_CLOUD" = "false" ]
}

@test "detect_sonarcloud: does not change SONAR_CLOUD for localhost URL" {
  SONAR_URL="http://localhost:9000"
  SONAR_CLOUD=false

  detect_sonarcloud

  [ "$SONAR_CLOUD" = "false" ]
}

@test "detect_sonarcloud: is idempotent — does not reset true to false" {
  SONAR_URL="http://sonar.example.com"
  SONAR_CLOUD=true

  detect_sonarcloud

  [ "$SONAR_CLOUD" = "true" ]
}

@test "detect_sonarcloud: does not set SONAR_CLOUD=true for lookalike domain (sonarcloud.io.example.com)" {
  SONAR_URL="https://sonarcloud.io.example.com"
  SONAR_CLOUD=false

  detect_sonarcloud

  [ "$SONAR_CLOUD" = "false" ]
}

@test "detect_sonarcloud: sets SONAR_CLOUD=true for URL with path and port" {
  SONAR_URL="https://sonarcloud.io:443/path"
  SONAR_CLOUD=false

  detect_sonarcloud

  [ "$SONAR_CLOUD" = "true" ]
}

# ===========================================================================
# sonar_api_get — organization injection
# ===========================================================================

@test "sonar_api_get: does not duplicate organization param when already in endpoint" {
  export _URL_FILE4
  _URL_FILE4=$(mktemp)

  curl() {
    local args=("$@")
    local last_index=$(( ${#args[@]} - 1 ))
    printf '%s' "${args[$last_index]}" >"$_URL_FILE4"
    local outfile=""
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
      if [[ "${args[$i]}" == "-o" ]]; then
        outfile="${args[$((i + 1))]}"
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
    done
    [[ -n "$outfile" ]] && printf '%s' "${MOCK_CURL_BODY:-}" >"$outfile"
    printf '%s' "${MOCK_CURL_STATUS:-200}"
  }
  export -f curl

  MOCK_CURL_STATUS="200"
  MOCK_CURL_BODY='{"status":"OK","conditions":[]}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY
  SONAR_ORGANIZATION="myorg"

  run sonar_api_get "qualitygates/project_status?projectKey=test&organization=myorg"
  local called_url
  called_url=$(cat "$_URL_FILE4")
  rm -f "$_URL_FILE4"
  [ "$status" -eq 0 ]
  # organization= should appear only once
  local count
  count=$(echo "$called_url" | grep -o 'organization=' | wc -l)
  [ "$count" -eq 1 ]
}

@test "sonar_api_get: appends organization param when SONAR_ORGANIZATION is set (no existing query)" {
  export _URL_FILE
  _URL_FILE=$(mktemp)

  curl() {
    local args=("$@")
    local last_index=$(( ${#args[@]} - 1 ))
    printf '%s' "${args[$last_index]}" >"$_URL_FILE"
    local outfile=""
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
      if [[ "${args[$i]}" == "-o" ]]; then
        outfile="${args[$((i + 1))]}"
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
    done
    [[ -n "$outfile" ]] && printf '%s' "${MOCK_CURL_BODY:-}" >"$outfile"
    printf '%s' "${MOCK_CURL_STATUS:-200}"
  }
  export -f curl

  MOCK_CURL_STATUS="200"
  MOCK_CURL_BODY='{"valid":true}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY
  SONAR_ORGANIZATION="myorg"

  run sonar_api_get "authentication/validate"
  local called_url
  called_url=$(cat "$_URL_FILE")
  rm -f "$_URL_FILE"
  [ "$status" -eq 0 ]
  [[ "$called_url" == *"organization=myorg"* ]]
}

@test "sonar_api_get: appends organization param with & when endpoint already has query string" {
  export _URL_FILE2
  _URL_FILE2=$(mktemp)

  curl() {
    local args=("$@")
    local last_index=$(( ${#args[@]} - 1 ))
    printf '%s' "${args[$last_index]}" >"$_URL_FILE2"
    local outfile=""
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
      if [[ "${args[$i]}" == "-o" ]]; then
        outfile="${args[$((i + 1))]}"
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
    done
    [[ -n "$outfile" ]] && printf '%s' "${MOCK_CURL_BODY:-}" >"$outfile"
    printf '%s' "${MOCK_CURL_STATUS:-200}"
  }
  export -f curl

  MOCK_CURL_STATUS="200"
  MOCK_CURL_BODY='{"status":"OK","conditions":[]}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY
  SONAR_ORGANIZATION="my-org"

  run sonar_api_get "qualitygates/project_status?projectKey=test-project"
  local called_url
  called_url=$(cat "$_URL_FILE2")
  rm -f "$_URL_FILE2"
  [ "$status" -eq 0 ]
  [[ "$called_url" == *"&organization=my-org"* ]]
}

@test "sonar_api_get: does not append organization when SONAR_ORGANIZATION is empty" {
  export _URL_FILE3
  _URL_FILE3=$(mktemp)

  curl() {
    local args=("$@")
    local last_index=$(( ${#args[@]} - 1 ))
    printf '%s' "${args[$last_index]}" >"$_URL_FILE3"
    local outfile=""
    local i=0
    while [[ $i -lt ${#args[@]} ]]; do
      if [[ "${args[$i]}" == "-o" ]]; then
        outfile="${args[$((i + 1))]}"
        i=$((i + 2))
      else
        i=$((i + 1))
      fi
    done
    [[ -n "$outfile" ]] && printf '%s' "${MOCK_CURL_BODY:-}" >"$outfile"
    printf '%s' "${MOCK_CURL_STATUS:-200}"
  }
  export -f curl

  MOCK_CURL_STATUS="200"
  MOCK_CURL_BODY='{"status":"UP"}'
  export MOCK_CURL_STATUS MOCK_CURL_BODY
  SONAR_ORGANIZATION=""

  run sonar_api_get "system/status"
  local called_url
  called_url=$(cat "$_URL_FILE3")
  rm -f "$_URL_FILE3"
  [ "$status" -eq 0 ]
  [[ "$called_url" != *"organization="* ]]
}

# ===========================================================================
# check_connectivity — SonarCloud mode
# ===========================================================================

@test "check_connectivity: SonarCloud mode succeeds using only authentication/validate" {
  SONAR_CLOUD=true
  SONAR_URL="https://sonarcloud.io"

  sonar_api_get() {
    case "$1" in
      system/status)           echo "SHOULD_NOT_BE_CALLED"; return 1 ;;
      authentication/validate) cat "${FIXTURES}/auth_validate.json" ;;
    esac
  }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -eq 0 ]
  [[ "$output" != *"SHOULD_NOT_BE_CALLED"* ]]
}

@test "check_connectivity: SonarCloud mode fails when authentication/validate returns invalid" {
  SONAR_CLOUD=true
  SONAR_URL="https://sonarcloud.io"

  sonar_api_get() {
    case "$1" in
      authentication/validate) cat "${FIXTURES}/auth_validate_invalid.json" ;;
    esac
  }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -ne 0 ]
}

@test "check_connectivity: SonarCloud mode logs 'SonarCloud' on success" {
  SONAR_CLOUD=true
  SONAR_URL="https://sonarcloud.io"

  sonar_api_get() {
    case "$1" in
      authentication/validate) cat "${FIXTURES}/auth_validate.json" ;;
    esac
  }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -eq 0 ]
  [[ "$output" == *"SonarCloud"* ]]
}

@test "check_connectivity: SonarCloud mode fails when authentication API call fails" {
  SONAR_CLOUD=true
  SONAR_URL="https://sonarcloud.io"

  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -ne 0 ]
}

@test "check_connectivity: auto-detects SonarCloud from URL and logs SonarCloud" {
  SONAR_CLOUD=false
  SONAR_URL="https://sonarcloud.io"

  sonar_api_get() {
    case "$1" in
      authentication/validate) cat "${FIXTURES}/auth_validate.json" ;;
    esac
  }
  export -f sonar_api_get

  run check_connectivity
  [ "$status" -eq 0 ]
  [[ "$output" == *"SonarCloud"* ]]
}
