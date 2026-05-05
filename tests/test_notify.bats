#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_notify.bats — Unit tests for scripts/lib/notify.sh
#
# Covers:
#   send_webhook_notification (with mocked curl)
#
# No real HTTP calls are made — curl is replaced with a mock that captures the
# outgoing payload and returns a configurable status code.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# shellcheck source=helpers.bash
load 'helpers'

# ---------------------------------------------------------------------------
# Minimal report_data JSON used across all tests
# ---------------------------------------------------------------------------
_REPORT_DATA='{
  "metadata": {
    "projectKey":       "notify-project",
    "projectName":      "Notify Test Project",
    "branch":           "main",
    "sonarUrl":         "http://sonar.example.com",
    "reportDate":       "2024-06-01T12:00:00Z",
    "lastAnalysisDate": "2024-06-01T11:00:00Z",
    "analysisId":       "ANotify123"
  },
  "qualityGate": { "status": "OK", "conditions": [] },
  "measures": {
    "bugs": "1",
    "vulnerabilities": "2",
    "code_smells": "5"
  },
  "issuesSummary": { "total": 8, "byType": {}, "bySeverity": {} },
  "hotspotsSummary": { "total": 3, "toReview": 1, "reviewed": 2 },
  "issues":   [],
  "hotspots": []
}'

setup() {
  # shellcheck source=../scripts/lib/notify.sh
  source "${REPO_ROOT}/scripts/lib/notify.sh"

  export SONAR_URL="http://sonar.example.com"
  export SONAR_TOKEN="test-token"
  export SONAR_PROJECT_KEY="notify-project"

  export _REPORT_DATA_FILE
  _REPORT_DATA_FILE=$(mktemp)
  echo "$_REPORT_DATA" > "$_REPORT_DATA_FILE"

  export _PAYLOAD_FILE
  _PAYLOAD_FILE=$(mktemp)

  # Default mock: capture the -d payload and return 200.
  export MOCK_CURL_STATUS="200"
  export MOCK_CURL_RESPONSE=""

  curl() {
    local i=0
    local args=("$@")
    local outfile=""
    local payload=""
    while [[ $i -lt ${#args[@]} ]]; do
      case "${args[$i]}" in
        -o) outfile="${args[$((i+1))]}"; i=$((i+2)) ;;
        -d) payload="${args[$((i+1))]}"; i=$((i+2)) ;;
        *) i=$((i+1)) ;;
      esac
    done
    [[ -n "$outfile" ]]   && printf '%s' "${MOCK_CURL_RESPONSE:-}" > "$outfile"
    [[ -n "$payload" ]]   && printf '%s' "$payload" > "$_PAYLOAD_FILE"
    printf '%s' "${MOCK_CURL_STATUS:-200}"
  }
  export -f curl
}

teardown() {
  rm -f "$_REPORT_DATA_FILE" "$_PAYLOAD_FILE"
}

# ===========================================================================
# send_webhook_notification
# ===========================================================================

@test "send_webhook_notification: succeeds with HTTP 200" {
  MOCK_CURL_STATUS="200"
  run send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Webhook notification sent"* ]]
}

@test "send_webhook_notification: fails on HTTP 4xx" {
  MOCK_CURL_STATUS="400"
  MOCK_CURL_RESPONSE="Bad Request"
  run send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Webhook returned HTTP 400"* ]]
}

@test "send_webhook_notification: fails on HTTP 5xx" {
  MOCK_CURL_STATUS="500"
  MOCK_CURL_RESPONSE="Internal Server Error"
  run send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Webhook returned HTTP 500"* ]]
}

@test "send_webhook_notification: payload is valid JSON" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  run jq '.' "$_PAYLOAD_FILE"
  [ "$status" -eq 0 ]
}

@test "send_webhook_notification: payload contains project name" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  local text
  text=$(jq -r '.text' "$_PAYLOAD_FILE")
  [[ "$text" == *"Notify Test Project"* ]]
}

@test "send_webhook_notification: payload contains project key" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  local text
  text=$(jq -r '.text' "$_PAYLOAD_FILE")
  [[ "$text" == *"notify-project"* ]]
}

@test "send_webhook_notification: payload contains quality gate status" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  local text
  text=$(jq -r '.text' "$_PAYLOAD_FILE")
  [[ "$text" == *"OK"* ]]
}

@test "send_webhook_notification: payload uses green emoji for OK gate" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  local text
  text=$(jq -r '.text' "$_PAYLOAD_FILE")
  [[ "$text" == *"✅"* ]]
}

@test "send_webhook_notification: payload uses red emoji for ERROR gate" {
  local tmp_file
  tmp_file=$(mktemp)
  echo "$_REPORT_DATA" | jq '.qualityGate.status = "ERROR"' > "$tmp_file"

  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$tmp_file"
  local text
  text=$(jq -r '.text' "$_PAYLOAD_FILE")
  [[ "$text" == *"❌"* ]]

  rm -f "$tmp_file"
}

@test "send_webhook_notification: payload contains bug count" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  local text
  text=$(jq -r '.text' "$_PAYLOAD_FILE")
  [[ "$text" == *"Bugs"* ]]
  [[ "$text" == *"1"* ]]
}

@test "send_webhook_notification: payload lists generated file names when provided" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE" \
    "/reports/my-project_report.json" "/reports/my-project_report.html"
  local text
  text=$(jq -r '.text' "$_PAYLOAD_FILE")
  [[ "$text" == *"my-project_report.json"* ]]
  [[ "$text" == *"my-project_report.html"* ]]
}

@test "send_webhook_notification: payload has a 'text' field" {
  MOCK_CURL_STATUS="200"
  send_webhook_notification "https://hooks.example.com/test" "$_REPORT_DATA_FILE"
  local has_text
  has_text=$(jq 'has("text")' "$_PAYLOAD_FILE")
  [ "$has_text" = "true" ]
}
