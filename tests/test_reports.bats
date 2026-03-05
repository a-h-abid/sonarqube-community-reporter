#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# shellcheck disable=SC2089,SC2090  # JSON strings stored in variables are intentional
# ==============================================================================
# test_reports.bats — Unit tests for report generator scripts
#
# Covers:
#   generate_json_report  (scripts/lib/report-json.sh)
#   generate_md_report    (scripts/lib/report-md.sh)
#   generate_html_report  (scripts/lib/report-html.sh)
#
# No real HTTP calls are made — all tests use pre-built report_data JSON.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# shellcheck source=helpers.bash
load 'helpers'

# ---------------------------------------------------------------------------
# Minimal but complete report_data JSON used across all tests
# ---------------------------------------------------------------------------
_REPORT_DATA='{
  "metadata": {
    "projectKey":  "my-project",
    "projectName": "My Project",
    "branch":      "main",
    "sonarUrl":    "http://sonar.example.com",
    "reportDate":  "2024-01-15T10:00:00Z",
    "analysisId":  "AXyz_analysis_456"
  },
  "qualityGate": {
    "status": "OK",
    "conditions": [
      {
        "metric":         "new_reliability_rating",
        "status":         "OK",
        "actualValue":    "1",
        "errorThreshold": "1",
        "comparator":     "GT"
      }
    ]
  },
  "measures": {
    "bugs":                       "2",
    "vulnerabilities":            "1",
    "code_smells":                "15",
    "coverage":                   "78.5",
    "duplicated_lines_density":   "3.2",
    "ncloc":                      "1234",
    "sqale_index":                "120",
    "sqale_debt_ratio":           "2.5",
    "reliability_rating":         "3.0",
    "security_rating":            "2.0",
    "sqale_rating":               "1.0",
    "security_hotspots_reviewed": "100",
    "security_review_rating":     "1.0",
    "alert_status":               "OK",
    "new_bugs":                   "0",
    "new_vulnerabilities":        "0",
    "new_code_smells":            "3",
    "new_coverage":               "85.0",
    "new_duplicated_lines_density": "0.0"
  },
  "issuesSummary": {
    "total": 18,
    "byType":     { "BUG": 2,  "VULNERABILITY": 1,  "CODE_SMELL": 15 },
    "bySeverity": { "BLOCKER": 1, "CRITICAL": 2, "MAJOR": 5, "MINOR": 7, "INFO": 3 }
  },
  "hotspotsSummary": {
    "total": 10, "toReview": 3, "reviewed": 7
  },
  "issues": [
    {
      "key":          "AXyz111",
      "severity":     "CRITICAL",
      "type":         "BUG",
      "message":      "Null pointer dereference",
      "component":    "my-project:src/Main.java",
      "line":         42,
      "rule":         "java:S2259",
      "effort":       "30min",
      "creationDate": "2024-01-15T10:00:00+0000"
    }
  ]
}'

setup() {
  export _OUTPUT_DIR
  _OUTPUT_DIR=$(mktemp -d)

  # Source all report libs (they source api.sh internally)
  # shellcheck source=../scripts/lib/report-json.sh
  source "${REPO_ROOT}/scripts/lib/report-json.sh"
  # shellcheck source=../scripts/lib/report-md.sh
  source "${REPO_ROOT}/scripts/lib/report-md.sh"
  # shellcheck source=../scripts/lib/report-html.sh
  source "${REPO_ROOT}/scripts/lib/report-html.sh"
}

teardown() {
  rm -rf "$_OUTPUT_DIR"
}

# ===========================================================================
# generate_json_report
# ===========================================================================

@test "generate_json_report: creates a file in output dir" {
  run generate_json_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  # The filepath is printed as the last line; log messages precede it
  [ -f "${lines[-1]}" ]
}

@test "generate_json_report: output file has .json extension" {
  run generate_json_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.json ]]
}

@test "generate_json_report: output is valid JSON" {
  run generate_json_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  run jq '.' "$filepath"
  [ "$status" -eq 0 ]
}

@test "generate_json_report: JSON contains metadata" {
  run generate_json_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  key=$(jq -r '.metadata.projectKey' "$filepath")
  [ "$key" = "my-project" ]
}

@test "generate_json_report: JSON contains qualityGate status" {
  run generate_json_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  qg=$(jq -r '.qualityGate.status' "$filepath")
  [ "$qg" = "OK" ]
}

@test "generate_json_report: JSON contains issues array" {
  run generate_json_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  count=$(jq '.issues | length' "$filepath")
  [ "$count" -eq 1 ]
}

@test "generate_json_report: filename contains project key" {
  run generate_json_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"my-project"* ]]
}

@test "generate_json_report: creates output directory if missing" {
  local new_dir="${_OUTPUT_DIR}/nested/sub"
  run generate_json_report "$_REPORT_DATA" "$new_dir"
  [ "$status" -eq 0 ]
  [ -d "$new_dir" ]
}

# ===========================================================================
# generate_md_report
# ===========================================================================

@test "generate_md_report: creates a file in output dir" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "${lines[-1]}" ]
}

@test "generate_md_report: output file has .md extension" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.md ]]
}

@test "generate_md_report: report contains project name" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "My Project" "$filepath"
}

@test "generate_md_report: report contains quality gate status" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "PASSED" "$filepath"
}

@test "generate_md_report: report contains bugs metric" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Bugs" "$filepath"
}

@test "generate_md_report: report contains coverage value" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "78.5" "$filepath"
}

@test "generate_md_report: report contains hotspot section" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -qi "hotspot" "$filepath"
}

@test "generate_md_report: report contains issues details" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Null pointer dereference" "$filepath"
}

@test "generate_md_report: filename contains project key" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"my-project"* ]]
}

@test "generate_md_report: reliability rating is a letter" {
  run generate_md_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # reliability_rating=3.0 → C
  grep -q "| \*\*Rating\*\* | C |" "$filepath"
}

# ===========================================================================
# generate_html_report
# ===========================================================================

@test "generate_html_report: creates a file in output dir" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "${lines[-1]}" ]
}

@test "generate_html_report: output file has .html extension" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.html ]]
}

@test "generate_html_report: output is non-empty HTML" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "<!DOCTYPE html>" "$filepath"
}

@test "generate_html_report: report contains project name" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "My Project" "$filepath"
}

@test "generate_html_report: quality gate status placeholder is replaced" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # Placeholder {{QG_STATUS}} should not appear in output
  run grep -c '{{QG_STATUS}}' "$filepath"
  [ "$output" = "0" ]
}

@test "generate_html_report: no unreplaced placeholders remain" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # None of the {{...}} placeholders should remain
  run grep -c '{{[A-Z_]*}}' "$filepath"
  [ "$output" = "0" ]
}

@test "generate_html_report: contains bugs value" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q ">2<" "$filepath"
}

@test "generate_html_report: contains sonar URL" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "sonar.example.com" "$filepath"
}

@test "generate_html_report: filename contains project key" {
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"my-project"* ]]
}

@test "generate_html_report: fails when template file is missing" {
  # Override the template dir path by pointing to a non-existent location
  _REPORT_HTML_SCRIPT_DIR="/nonexistent/path"
  run generate_html_report "$_REPORT_DATA" "$_OUTPUT_DIR"
  [ "$status" -ne 0 ]
}
