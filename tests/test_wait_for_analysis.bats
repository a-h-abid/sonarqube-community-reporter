#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_wait_for_analysis.bats — Unit tests for scripts/wait-for-analysis.sh
#
# Covers:
#   extract_task_id_from_report,
#   _poll_by_task_id  (with mocked sonar_api_get),
#   _poll_by_component (with mocked sonar_api_get)
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

# shellcheck source=helpers.bash
load 'helpers'

setup() {
  # Source the wait script (which sources api.sh)
  # shellcheck source=../scripts/wait-for-analysis.sh
  source "${REPO_ROOT}/scripts/wait-for-analysis.sh"

  export SONAR_URL="http://sonar.example.com"
  export SONAR_TOKEN="test-token"
  export SONAR_PROJECT_KEY="my-project"
  export SONAR_TASK_ID=""
  export POLL_INTERVAL="1"
  export POLL_TIMEOUT="5"
  export ANALYSIS_ID=""
}

# ===========================================================================
# extract_task_id_from_report
# ===========================================================================

@test "extract_task_id_from_report: extracts ceTaskId from report file" {
  local tmpfile
  tmpfile=$(mktemp)
  printf 'projectKey=my-project\nceTaskId=AXyz_task_123\nserverUrl=http://sonar.example.com\n' >"$tmpfile"

  run extract_task_id_from_report "$tmpfile"
  [ "$status" -eq 0 ]
  [ "$output" = "AXyz_task_123" ]
  rm -f "$tmpfile"
}

@test "extract_task_id_from_report: fails when file does not exist" {
  run extract_task_id_from_report "/nonexistent/path/report-task.txt"
  [ "$status" -ne 0 ]
}

@test "extract_task_id_from_report: fails when ceTaskId is missing from file" {
  local tmpfile
  tmpfile=$(mktemp)
  printf 'projectKey=my-project\nserverUrl=http://sonar.example.com\n' >"$tmpfile"

  run extract_task_id_from_report "$tmpfile"
  [ "$status" -ne 0 ]
  rm -f "$tmpfile"
}

@test "extract_task_id_from_report: handles file with extra fields" {
  local tmpfile
  tmpfile=$(mktemp)
  printf 'projectKey=my-project\ndashboardUrl=http://example.com\nceTaskId=TASK-999\nanalysisId=ANL-42\n' >"$tmpfile"

  run extract_task_id_from_report "$tmpfile"
  [ "$status" -eq 0 ]
  [ "$output" = "TASK-999" ]
  rm -f "$tmpfile"
}

# ===========================================================================
# _poll_by_task_id — mocked sonar_api_get
# ===========================================================================

@test "_poll_by_task_id: succeeds when task status is SUCCESS" {
  sonar_api_get() { cat "${FIXTURES}/ce_task_success.json"; }
  export -f sonar_api_get

  export SONAR_TASK_ID="AXyz_task_123"
  run _poll_by_task_id 1 10
  [ "$status" -eq 0 ]
}

@test "_poll_by_task_id: sets ANALYSIS_ID on success" {
  sonar_api_get() { cat "${FIXTURES}/ce_task_success.json"; }
  export -f sonar_api_get

  export SONAR_TASK_ID="AXyz_task_123"
  # Run in current shell (not subshell) to capture ANALYSIS_ID
  _poll_by_task_id 1 10
  [ "$ANALYSIS_ID" = "AXyz_analysis_456" ]
}

@test "_poll_by_task_id: fails when task status is FAILED" {
  sonar_api_get() { cat "${FIXTURES}/ce_task_failed.json"; }
  export -f sonar_api_get

  export SONAR_TASK_ID="AXyz_task_123"
  run _poll_by_task_id 1 10
  [ "$status" -ne 0 ]
}

@test "_poll_by_task_id: fails when task status is CANCELED" {
  sonar_api_get() {
    echo '{"task":{"id":"t1","status":"CANCELED"}}'
  }
  export -f sonar_api_get

  export SONAR_TASK_ID="AXyz_task_123"
  run _poll_by_task_id 1 10
  [ "$status" -ne 0 ]
}

@test "_poll_by_task_id: fails when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  export SONAR_TASK_ID="AXyz_task_123"
  run _poll_by_task_id 1 5
  [ "$status" -ne 0 ]
}

@test "_poll_by_task_id: eventually succeeds after PENDING then SUCCESS" {
  export _POLL_CTR
  _POLL_CTR=$(counter_file_new)

  sonar_api_get() {
    local n
    n=$(counter_file_increment "$_POLL_CTR")
    if [[ "$n" -eq 1 ]]; then
      cat "${FIXTURES}/ce_task_pending.json"
    else
      cat "${FIXTURES}/ce_task_success.json"
    fi
  }
  export -f sonar_api_get counter_file_increment

  export SONAR_TASK_ID="AXyz_task_123"
  run _poll_by_task_id 0 30
  rm -f "$_POLL_CTR"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# _poll_by_component — mocked sonar_api_get
# ===========================================================================

@test "_poll_by_component: succeeds when current task is SUCCESS and queue empty" {
  sonar_api_get() { cat "${FIXTURES}/ce_component_success.json"; }
  export -f sonar_api_get

  run _poll_by_component 1 10
  [ "$status" -eq 0 ]
}

@test "_poll_by_component: sets ANALYSIS_ID on success" {
  sonar_api_get() { cat "${FIXTURES}/ce_component_success.json"; }
  export -f sonar_api_get

  _poll_by_component 1 10
  [ "$ANALYSIS_ID" = "AXyz_analysis_789" ]
}

@test "_poll_by_component: fails when SONAR_PROJECT_KEY is empty" {
  SONAR_PROJECT_KEY=""
  run _poll_by_component 1 10
  [ "$status" -ne 0 ]
}

@test "_poll_by_component: fails when latest analysis FAILED" {
  sonar_api_get() {
    echo '{"queue":[],"current":{"id":"t1","status":"FAILED","errorMessage":"Disk full"}}'
  }
  export -f sonar_api_get

  run _poll_by_component 1 10
  [ "$status" -ne 0 ]
}

@test "_poll_by_component: fails when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run _poll_by_component 1 5
  [ "$status" -ne 0 ]
}

@test "_poll_by_component: succeeds with no 'current' key (never analysed)" {
  sonar_api_get() {
    echo '{"queue":[]}'
  }
  export -f sonar_api_get

  run _poll_by_component 1 10
  [ "$status" -eq 0 ]
}

# ===========================================================================
# wait_for_analysis — integration (uses task id or component key)
# ===========================================================================

@test "wait_for_analysis: uses _poll_by_task_id when SONAR_TASK_ID is set" {
  _poll_by_task_id() { echo "poll_by_task_id_called"; }
  _poll_by_component() { echo "poll_by_component_called"; }
  export -f _poll_by_task_id _poll_by_component

  export SONAR_TASK_ID="some-task-id"
  run wait_for_analysis
  [ "$status" -eq 0 ]
  [[ "$output" == *"poll_by_task_id_called"* ]]
}

@test "wait_for_analysis: uses _poll_by_component when SONAR_TASK_ID is empty" {
  _poll_by_task_id() { echo "poll_by_task_id_called"; }
  _poll_by_component() { echo "poll_by_component_called"; }
  export -f _poll_by_task_id _poll_by_component

  export SONAR_TASK_ID=""
  run wait_for_analysis
  [ "$status" -eq 0 ]
  [[ "$output" == *"poll_by_component_called"* ]]
}
