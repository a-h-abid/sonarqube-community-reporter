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
