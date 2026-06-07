#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_filtering.bats — Issue display filters (--severity-threshold,
#   --issue-types, --max-issues)
#
# Covers: parse_args wiring, validate_filter_flags normalization/validation,
# the apply_issue_filters transform, and an end-to-end dry-run across formats.
# Filters limit what is SHOWN (the .issues array) without touching hotspots or
# the summary counts.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  # shellcheck source=../scripts/sonar-report.sh
  source "${REPO_ROOT}/scripts/sonar-report.sh"

  # Clean, order-independent state.
  REQUESTED_FORMATS=()
  REPORT_FORMATS="json"; REPORT_OUTPUT_DIR="./reports"
  SONAR_URL="http://sonar.example.com"; SONAR_TOKEN=""; SONAR_PROJECT_KEY=""
  SONAR_BRANCH=""; SONAR_TASK_ID=""; SONAR_ORGANIZATION=""; SONAR_CLOUD="false"
  POLL_INTERVAL="1"; POLL_TIMEOUT="2"; ANALYSIS_ID=""; DRY_RUN_FILE=""
  NOTIFY_WEBHOOK=""; INCLUDE_RULE_DESCRIPTIONS=""; INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"; INCLUDE_QUALITY_PROFILES="false"
  INCLUDE_QUALITY_GATE_NAME="false"; WAIT_FOR_ANALYSIS="false"; FAIL_ON_GATE="false"
  SEVERITY_THRESHOLD=""; ISSUE_TYPES=""; MAX_ISSUES=""

  # Isolate temp files created by apply_issue_filters (parallel-safe).
  export SONAR_REPORT_TMP_DIR
  SONAR_REPORT_TMP_DIR=$(mktemp -d)
  OUT=$(mktemp -d)

  # A report fixture with a mix of severities and types, ordered by severity
  # descending (as the live fetch returns them).
  MIXED="${OUT}/mixed.json"
  jq '.issues = [
    {"key":"B1","severity":"BLOCKER","type":"BUG","component":"my-project:src/A.java","line":1,"rule":"r1","effort":"5min","message":"blocker bug","creationDate":"2024-01-01"},
    {"key":"C1","severity":"CRITICAL","type":"VULNERABILITY","component":"my-project:src/B.java","line":2,"rule":"r2","effort":"5min","message":"critical vuln","creationDate":"2024-01-01"},
    {"key":"M1","severity":"MAJOR","type":"CODE_SMELL","component":"my-project:src/C.java","line":3,"rule":"r3","effort":"5min","message":"major smell","creationDate":"2024-01-01"},
    {"key":"m1","severity":"MINOR","type":"BUG","component":"my-project:src/D.java","line":4,"rule":"r4","effort":"5min","message":"minor bug","creationDate":"2024-01-01"},
    {"key":"I1","severity":"INFO","type":"CODE_SMELL","component":"my-project:src/E.java","line":5,"rule":"r5","effort":"5min","message":"info smell","creationDate":"2024-01-01"}
  ]' "${REPO_ROOT}/tests/fixtures/report_data.json" > "$MIXED"
}

teardown() {
  rm -rf "$OUT" "$SONAR_REPORT_TMP_DIR"
}

# ===========================================================================
# parse_args wiring
# ===========================================================================

@test "parse_args: --severity-threshold sets SEVERITY_THRESHOLD" {
  parse_args --severity-threshold MAJOR --project-key p
  [ "$SEVERITY_THRESHOLD" = "MAJOR" ]
}

@test "parse_args: --issue-types sets ISSUE_TYPES" {
  parse_args --issue-types BUG,VULNERABILITY --project-key p
  [ "$ISSUE_TYPES" = "BUG,VULNERABILITY" ]
}

@test "parse_args: --max-issues sets MAX_ISSUES" {
  parse_args --max-issues 25 --project-key p
  [ "$MAX_ISSUES" = "25" ]
}

# ===========================================================================
# validate_filter_flags
# ===========================================================================

@test "validate_filter_flags: normalizes lowercase severity and issue types" {
  SEVERITY_THRESHOLD="major"; ISSUE_TYPES="bug, vulnerability"; MAX_ISSUES="5"
  validate_filter_flags
  [ "$SEVERITY_THRESHOLD" = "MAJOR" ]
  [ "$ISSUE_TYPES" = "BUG,VULNERABILITY" ]
}

@test "validate_filter_flags: accepts empty (no filters)" {
  run validate_filter_flags
  [ "$status" -eq 0 ]
}

@test "validate_filter_flags: rejects unknown severity" {
  SEVERITY_THRESHOLD="HUGE"
  run validate_filter_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --severity-threshold"* ]]
}

@test "validate_filter_flags: rejects unknown issue type" {
  ISSUE_TYPES="BUG,WIDGET"
  run validate_filter_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid --issue-types"* ]]
}

@test "validate_filter_flags: rejects non-positive max-issues" {
  MAX_ISSUES="0"
  run validate_filter_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "validate_filter_flags: rejects non-numeric max-issues" {
  MAX_ISSUES="abc"
  run validate_filter_flags
  [ "$status" -ne 0 ]
}

# ===========================================================================
# apply_issue_filters — the core transform
# ===========================================================================

@test "apply_issue_filters: no filters returns input unchanged (no-op)" {
  run apply_issue_filters "$MIXED"
  [ "$status" -eq 0 ]
  [ "$output" = "$MIXED" ]
  [ "$(jq '.metadata.filtersApplied' "$MIXED")" = "null" ]
}

@test "apply_issue_filters: severity threshold keeps that level and higher" {
  SEVERITY_THRESHOLD="MAJOR"
  run apply_issue_filters "$MIXED"
  [ "$status" -eq 0 ]
  local f="$output"
  [ "$(jq '.issues | length' "$f")" -eq 3 ]
  jq -e '[.issues[].key] == ["B1","C1","M1"]' "$f"
  [ "$(jq -r '.metadata.filtersApplied.issuesBeforeFilter' "$f")" -eq 5 ]
  [ "$(jq -r '.metadata.filtersApplied.issuesShown' "$f")" -eq 3 ]
}

@test "apply_issue_filters: issue-types keeps only listed types" {
  ISSUE_TYPES="BUG,VULNERABILITY"
  run apply_issue_filters "$MIXED"
  [ "$status" -eq 0 ]
  local f="$output"
  jq -e '[.issues[].key] == ["B1","C1","m1"]' "$f"
  jq -e '.metadata.filtersApplied.issueTypes == ["BUG","VULNERABILITY"]' "$f"
}

@test "apply_issue_filters: max-issues caps to the highest-severity N" {
  MAX_ISSUES="2"
  run apply_issue_filters "$MIXED"
  [ "$status" -eq 0 ]
  local f="$output"
  jq -e '[.issues[].key] == ["B1","C1"]' "$f"
  [ "$(jq -r '.metadata.filtersApplied.maxIssues' "$f")" -eq 2 ]
}

@test "apply_issue_filters: composes severity, type, and cap in order" {
  SEVERITY_THRESHOLD="MAJOR"; ISSUE_TYPES="BUG,VULNERABILITY"; MAX_ISSUES="1"
  run apply_issue_filters "$MIXED"
  [ "$status" -eq 0 ]
  local f="$output"
  jq -e '[.issues[].key] == ["B1"]' "$f"
  [ "$(jq -r '.metadata.filtersApplied.issuesShown' "$f")" -eq 1 ]
}

@test "apply_issue_filters: leaves hotspots and summary counts untouched" {
  SEVERITY_THRESHOLD="BLOCKER"
  run apply_issue_filters "$MIXED"
  [ "$status" -eq 0 ]
  local f="$output"
  [ "$(jq '.issues | length' "$f")" -eq 1 ]
  # Summaries reflect the full project, not the filtered list.
  [ "$(jq -r '.issuesSummary.total' "$f")" -eq 18 ]
  [ "$(jq '.hotspots | length' "$f")" -eq 2 ]
  [ "$(jq -r '.hotspotsSummary.total' "$f")" -eq 10 ]
}

# ===========================================================================
# End-to-end via main() dry-run — filters reach every format
# ===========================================================================

@test "main: dry-run applies filters to json, md, csv, and sarif" {
  run main --dry-run "$MIXED" \
    --severity-threshold MAJOR --issue-types BUG,VULNERABILITY \
    --formats json,md,csv,sarif --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Filters applied"* ]]

  # JSON: filtered detail list, full summary.
  local json_file
  json_file=$(find "$OUT" -name '*.json' ! -name 'mixed.json' | head -1)
  [ "$(jq '.issues | length' "$json_file")" -eq 2 ]
  [ "$(jq -r '.issuesSummary.total' "$json_file")" -eq 18 ]

  # Markdown: note rendered.
  grep -q "Filters applied" "$(find "$OUT" -name '*.md' | head -1)"

  # CSV summary: "Filters Applied" row present.
  grep -rq "Filters Applied" "$OUT"

  # SARIF: machine-readable provenance + filtered issue count.
  local sarif_file
  sarif_file=$(find "$OUT" -name '*.sarif' | head -1)
  [ "$(jq -r '.runs[0].properties.filtersApplied.issuesShown' "$sarif_file")" -eq 2 ]
}
