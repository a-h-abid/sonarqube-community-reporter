#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_main.bats — Unit tests for scripts/sonar-report.sh orchestration helpers
#
# Covers:
#   normalize_format, validate_report_formats
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