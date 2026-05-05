#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_main.bats — Unit tests for scripts/sonar-report.sh orchestration helpers
#
# Covers:
#   normalize_format, validate_report_formats, validate_params (dry-run mode)
#
# The main script is sourced under test; its main() entrypoint is guarded so it
# does not execute during these tests.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  # shellcheck source=../scripts/sonar-report.sh
  source "${REPO_ROOT}/scripts/sonar-report.sh"

  REQUESTED_FORMATS=()
  REPORT_FORMATS="json"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY=""
  DRY_RUN_FILE=""
}

@test "normalize_format: maps markdown alias to md" {
  run normalize_format " markdown "
  [ "$status" -eq 0 ]
  [ "$output" = "md" ]
}

@test "validate_report_formats: rejects unsupported formats" {
  REPORT_FORMATS="json,invalid"

  run validate_report_formats
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported report format: invalid"* ]]
}

@test "validate_report_formats: rejects empty formats" {
  REPORT_FORMATS="json,,html"

  run validate_report_formats
  [ "$status" -ne 0 ]
  [[ "$output" == *"Empty report format"* ]]
}

@test "validate_report_formats: normalizes aliases and removes duplicates" {
  REPORT_FORMATS="json, markdown, html, json"

  validate_report_formats

  [ "${#REQUESTED_FORMATS[@]}" -eq 3 ]
  [ "${REQUESTED_FORMATS[0]}" = "json" ]
  [ "${REQUESTED_FORMATS[1]}" = "md" ]
  [ "${REQUESTED_FORMATS[2]}" = "html" ]
}

@test "validate_report_formats: accepts csv format" {
  REPORT_FORMATS="csv"

  validate_report_formats

  [ "${#REQUESTED_FORMATS[@]}" -eq 1 ]
  [ "${REQUESTED_FORMATS[0]}" = "csv" ]
}

# ===========================================================================
# validate_params — dry-run mode
# ===========================================================================

@test "validate_params: dry-run mode accepts missing SONAR_TOKEN" {
  local tmp_file
  tmp_file=$(mktemp)
  echo '{"metadata":{"projectKey":"my-project"}}' > "$tmp_file"

  DRY_RUN_FILE="$tmp_file"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY="my-project"
  REPORT_FORMATS="json"

  # validate_params calls exit on failure; must not fail here
  validate_params
  [ "$?" -eq 0 ]

  rm -f "$tmp_file"
}

@test "validate_params: dry-run mode auto-populates project key from file" {
  local tmp_file
  tmp_file=$(mktemp)
  echo '{"metadata":{"projectKey":"auto-project"}}' > "$tmp_file"

  DRY_RUN_FILE="$tmp_file"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY=""
  REPORT_FORMATS="json"

  validate_params

  [ "$SONAR_PROJECT_KEY" = "auto-project" ]

  rm -f "$tmp_file"
}

@test "validate_params: dry-run mode fails when file does not exist" {
  DRY_RUN_FILE="/nonexistent/file.json"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY="my-project"
  REPORT_FORMATS="json"

  run validate_params
  [ "$status" -ne 0 ]
  [[ "$output" == *"Dry-run file not found"* ]]
}

@test "validate_params: dry-run mode fails when file is not valid JSON" {
  local tmp_file
  tmp_file=$(mktemp)
  echo "not json at all" > "$tmp_file"

  DRY_RUN_FILE="$tmp_file"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY="my-project"
  REPORT_FORMATS="json"

  run validate_params
  [ "$status" -ne 0 ]

  rm -f "$tmp_file"
}

# ===========================================================================
# parse_args — new flags
# ===========================================================================

@test "parse_args: --dry-run sets DRY_RUN_FILE" {
  parse_args --dry-run "/tmp/report.json" --project-key "p"
  [ "$DRY_RUN_FILE" = "/tmp/report.json" ]
}

@test "parse_args: --notify-webhook sets NOTIFY_WEBHOOK" {
  parse_args --notify-webhook "https://hooks.example.com/abc" --project-key "p"
  [ "$NOTIFY_WEBHOOK" = "https://hooks.example.com/abc" ]
}