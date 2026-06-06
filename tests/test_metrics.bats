#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# shellcheck disable=SC2089,SC2090  # JSON strings stored in variables are intentional
# ==============================================================================
# test_metrics.bats — Unit tests for scripts/lib/metrics.sh
#
# Covers:
#   fetch_quality_gate, fetch_measures, fetch_issues_summary,
#   fetch_hotspots_summary, fetch_all_issues, fetch_all_metrics
#
# sonar_api_get and sonar_api_paginated are mocked so no real HTTP calls occur.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

# shellcheck source=helpers.bash
load 'helpers'

setup() {
  # Source metrics.sh (which also sources api.sh)
  # shellcheck source=../scripts/lib/metrics.sh
  source "${REPO_ROOT}/scripts/lib/metrics.sh"

  export SONAR_URL="http://sonar.example.com"
  export SONAR_TOKEN="test-token"
  export SONAR_PROJECT_KEY="my-project"
  export SONAR_BRANCH=""
  export SONAR_CLOUD=false
  export SONAR_ORGANIZATION=""
}

# ===========================================================================
# fetch_quality_gate
# ===========================================================================

@test "fetch_quality_gate: returns OK status" {
  sonar_api_get() { cat "${FIXTURES}/quality_gate.json"; }
  export -f sonar_api_get

  run fetch_quality_gate
  [ "$status" -eq 0 ]
  status_val=$(echo "$output" | jq -r '.status')
  [ "$status_val" = "OK" ]
}

@test "fetch_quality_gate: returns ERROR status when gate fails" {
  sonar_api_get() { cat "${FIXTURES}/quality_gate_failed.json"; }
  export -f sonar_api_get

  run fetch_quality_gate
  [ "$status" -eq 0 ]
  status_val=$(echo "$output" | jq -r '.status')
  [ "$status_val" = "ERROR" ]
}

@test "fetch_quality_gate: conditions array is present" {
  sonar_api_get() { cat "${FIXTURES}/quality_gate.json"; }
  export -f sonar_api_get

  run fetch_quality_gate
  [ "$status" -eq 0 ]
  cond_count=$(echo "$output" | jq '.conditions | length')
  [ "$cond_count" -gt 0 ]
}

@test "fetch_quality_gate: condition has expected fields" {
  sonar_api_get() { cat "${FIXTURES}/quality_gate.json"; }
  export -f sonar_api_get

  run fetch_quality_gate
  [ "$status" -eq 0 ]
  metric=$(echo "$output" | jq -r '.conditions[0].metric')
  [ "$metric" = "new_reliability_rating" ]
}

@test "fetch_quality_gate: fails when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_quality_gate
  [ "$status" -ne 0 ]
}

@test "fetch_quality_gate: appends branch param when SONAR_BRANCH is set" {
  export SONAR_BRANCH="feature/my-branch"
  export _ENDPOINT_FILE
  _ENDPOINT_FILE=$(mktemp)

  sonar_api_get() {
    echo "$1" >"$_ENDPOINT_FILE"
    cat "${FIXTURES}/quality_gate.json"
  }
  export -f sonar_api_get

  run fetch_quality_gate
  local received_endpoint
  received_endpoint=$(cat "$_ENDPOINT_FILE")
  rm -f "$_ENDPOINT_FILE"
  [ "$status" -eq 0 ]
  [[ "$received_endpoint" == *"branch=feature/my-branch"* ]]
}

# ===========================================================================
# fetch_quality_gate_name
# ===========================================================================

@test "fetch_quality_gate_name: returns the gate name" {
  sonar_api_get() { cat "${FIXTURES}/quality_gate_by_project.json"; }
  export -f sonar_api_get

  run fetch_quality_gate_name
  [ "$status" -eq 0 ]
  [ "$output" = "Sonar way" ]
}

@test "fetch_quality_gate_name: queries get_by_project with project= param" {
  export _ENDPOINT_FILE
  _ENDPOINT_FILE=$(mktemp)

  sonar_api_get() {
    echo "$1" >"$_ENDPOINT_FILE"
    cat "${FIXTURES}/quality_gate_by_project.json"
  }
  export -f sonar_api_get

  run fetch_quality_gate_name
  local received_endpoint
  received_endpoint=$(cat "$_ENDPOINT_FILE")
  rm -f "$_ENDPOINT_FILE"
  [ "$status" -eq 0 ]
  [[ "$received_endpoint" == *"qualitygates/get_by_project?project=my-project"* ]]
}

@test "fetch_quality_gate_name: returns empty when gate name absent" {
  sonar_api_get() { echo '{"qualityGate":{}}'; }
  export -f sonar_api_get

  run fetch_quality_gate_name
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "fetch_quality_gate_name: fails when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_quality_gate_name
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_quality_profiles
# ===========================================================================

@test "fetch_quality_profiles: returns array of profiles" {
  sonar_api_get() { cat "${FIXTURES}/quality_profiles.json"; }
  export -f sonar_api_get

  run fetch_quality_profiles
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "fetch_quality_profiles: projects key, name, language, languageName" {
  sonar_api_get() { cat "${FIXTURES}/quality_profiles.json"; }
  export -f sonar_api_get

  run fetch_quality_profiles
  [ "$status" -eq 0 ]
  name=$(echo "$output" | jq -r '.[0].name')
  language=$(echo "$output" | jq -r '.[0].language')
  language_name=$(echo "$output" | jq -r '.[0].languageName')
  [ "$name" = "Sonar way" ]
  [ "$language" = "java" ]
  [ "$language_name" = "Java" ]
}

@test "fetch_quality_profiles: queries qualityprofiles/search with project= param" {
  export _ENDPOINT_FILE
  _ENDPOINT_FILE=$(mktemp)

  sonar_api_get() {
    echo "$1" >"$_ENDPOINT_FILE"
    cat "${FIXTURES}/quality_profiles.json"
  }
  export -f sonar_api_get

  run fetch_quality_profiles
  local received_endpoint
  received_endpoint=$(cat "$_ENDPOINT_FILE")
  rm -f "$_ENDPOINT_FILE"
  [ "$status" -eq 0 ]
  [[ "$received_endpoint" == *"qualityprofiles/search?project=my-project"* ]]
}

@test "fetch_quality_profiles: returns empty array when no profiles" {
  sonar_api_get() { echo '{"profiles":[]}'; }
  export -f sonar_api_get

  run fetch_quality_profiles
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 0 ]
}

@test "fetch_quality_profiles: fails when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_quality_profiles
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_measures
# ===========================================================================

@test "fetch_measures: returns componentKey" {
  sonar_api_get() { cat "${FIXTURES}/measures.json"; }
  export -f sonar_api_get

  run fetch_measures
  [ "$status" -eq 0 ]
  key=$(echo "$output" | jq -r '.componentKey')
  [ "$key" = "my-project" ]
}

@test "fetch_measures: returns componentName" {
  sonar_api_get() { cat "${FIXTURES}/measures.json"; }
  export -f sonar_api_get

  run fetch_measures
  [ "$status" -eq 0 ]
  name=$(echo "$output" | jq -r '.componentName')
  [ "$name" = "My Project" ]
}

@test "fetch_measures: bugs metric is extracted" {
  sonar_api_get() { cat "${FIXTURES}/measures.json"; }
  export -f sonar_api_get

  run fetch_measures
  [ "$status" -eq 0 ]
  bugs=$(echo "$output" | jq -r '.measures.bugs')
  [ "$bugs" = "2" ]
}

@test "fetch_measures: coverage metric is extracted" {
  sonar_api_get() { cat "${FIXTURES}/measures.json"; }
  export -f sonar_api_get

  run fetch_measures
  [ "$status" -eq 0 ]
  coverage=$(echo "$output" | jq -r '.measures.coverage')
  [ "$coverage" = "78.5" ]
}

@test "fetch_measures: fails when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_measures
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_issues_summary
# ===========================================================================

@test "fetch_issues_summary: returns total count" {
  sonar_api_get() { cat "${FIXTURES}/issues_summary.json"; }
  export -f sonar_api_get

  run fetch_issues_summary
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq -r '.total')
  [ "$total" = "18" ]
}

@test "fetch_issues_summary: byType contains BUG count" {
  sonar_api_get() { cat "${FIXTURES}/issues_summary.json"; }
  export -f sonar_api_get

  run fetch_issues_summary
  [ "$status" -eq 0 ]
  bugs=$(echo "$output" | jq -r '.byType.BUG')
  [ "$bugs" = "2" ]
}

@test "fetch_issues_summary: bySeverity contains CRITICAL count" {
  sonar_api_get() { cat "${FIXTURES}/issues_summary.json"; }
  export -f sonar_api_get

  run fetch_issues_summary
  [ "$status" -eq 0 ]
  critical=$(echo "$output" | jq -r '.bySeverity.CRITICAL')
  [ "$critical" = "2" ]
}

@test "fetch_issues_summary: fails when API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_issues_summary
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_hotspots_summary
# ===========================================================================

@test "fetch_hotspots_summary: total is sum of to_review + reviewed" {
  export _HS_CTR
  _HS_CTR=$(counter_file_new)

  sonar_api_get() {
    local n
    n=$(counter_file_increment "$_HS_CTR")
    if [[ "$n" -eq 1 ]]; then
      cat "${FIXTURES}/hotspots_to_review.json"
    else
      cat "${FIXTURES}/hotspots_reviewed.json"
    fi
  }
  export -f sonar_api_get counter_file_increment

  run fetch_hotspots_summary
  rm -f "$_HS_CTR"
  [ "$status" -eq 0 ]
  total=$(echo "$output" | jq -r '.total')
  [ "$total" = "10" ]
}

@test "fetch_hotspots_summary: toReview count is correct" {
  export _HS_CTR2
  _HS_CTR2=$(counter_file_new)

  sonar_api_get() {
    local n
    n=$(counter_file_increment "$_HS_CTR2")
    if [[ "$n" -eq 1 ]]; then
      cat "${FIXTURES}/hotspots_to_review.json"
    else
      cat "${FIXTURES}/hotspots_reviewed.json"
    fi
  }
  export -f sonar_api_get counter_file_increment

  run fetch_hotspots_summary
  rm -f "$_HS_CTR2"
  [ "$status" -eq 0 ]
  to_review=$(echo "$output" | jq -r '.toReview')
  [ "$to_review" = "3" ]
}

@test "fetch_hotspots_summary: reviewed count is correct" {
  export _HS_CTR3
  _HS_CTR3=$(counter_file_new)

  sonar_api_get() {
    local n
    n=$(counter_file_increment "$_HS_CTR3")
    if [[ "$n" -eq 1 ]]; then
      cat "${FIXTURES}/hotspots_to_review.json"
    else
      cat "${FIXTURES}/hotspots_reviewed.json"
    fi
  }
  export -f sonar_api_get counter_file_increment

  run fetch_hotspots_summary
  rm -f "$_HS_CTR3"
  [ "$status" -eq 0 ]
  reviewed=$(echo "$output" | jq -r '.reviewed')
  [ "$reviewed" = "7" ]
}

@test "fetch_hotspots_summary: fails when first API call fails" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_hotspots_summary
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_all_issues
# ===========================================================================

@test "fetch_all_issues: returns array of issues" {
  sonar_api_paginated() { cat "${FIXTURES}/issues_page1.json" | jq '.issues'; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "fetch_all_issues: issue has expected fields" {
  sonar_api_paginated() { cat "${FIXTURES}/issues_page1.json" | jq '.issues'; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -eq 0 ]
  key=$(echo "$output" | jq -r '.[0].key')
  [ "$key" = "AXyz111" ]
}

@test "fetch_all_issues: issue fields are projected correctly" {
  sonar_api_paginated() { cat "${FIXTURES}/issues_page1.json" | jq '.issues'; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -eq 0 ]
  # Check that only expected keys are present
  has_severity=$(echo "$output" | jq -r '.[0] | has("severity")')
  has_type=$(echo "$output" | jq -r '.[0] | has("type")')
  has_message=$(echo "$output" | jq -r '.[0] | has("message")')
  [ "$has_severity" = "true" ]
  [ "$has_type" = "true" ]
  [ "$has_message" = "true" ]
}

@test "fetch_all_issues: derives startLine and endLine from textRange when present" {
  sonar_api_paginated() { cat "${FIXTURES}/issues_page1.json" | jq '.issues'; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -eq 0 ]
  # AXyz222 has a textRange{startLine:100,endLine:104}
  start=$(echo "$output" | jq -r '.[] | select(.key=="AXyz222") | .startLine')
  end=$(echo "$output" | jq -r '.[] | select(.key=="AXyz222") | .endLine')
  [ "$start" = "100" ]
  [ "$end" = "104" ]
}

@test "fetch_all_issues: startLine/endLine fall back to line when textRange absent" {
  sonar_api_paginated() { cat "${FIXTURES}/issues_page1.json" | jq '.issues'; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -eq 0 ]
  # AXyz111 has no textRange — both should equal line=42
  start=$(echo "$output" | jq -r '.[] | select(.key=="AXyz111") | .startLine')
  end=$(echo "$output" | jq -r '.[] | select(.key=="AXyz111") | .endLine')
  [ "$start" = "42" ]
  [ "$end" = "42" ]
}

@test "fetch_all_issues: keeps existing line field unchanged for back-compat" {
  sonar_api_paginated() { cat "${FIXTURES}/issues_page1.json" | jq '.issues'; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -eq 0 ]
  line1=$(echo "$output" | jq -r '.[] | select(.key=="AXyz111") | .line')
  line2=$(echo "$output" | jq -r '.[] | select(.key=="AXyz222") | .line')
  [ "$line1" = "42" ]
  [ "$line2" = "100" ]
}

@test "fetch_all_issues: returns empty array when no issues" {
  sonar_api_paginated() { echo "[]"; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "fetch_all_issues: fails when paginated call fails" {
  sonar_api_paginated() { return 1; }
  export -f sonar_api_paginated

  run fetch_all_issues
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_all_hotspots
# ===========================================================================

@test "fetch_all_hotspots: returns both to-review and reviewed hotspots" {
  export _HS_LIST_CTR
  _HS_LIST_CTR=$(counter_file_new)

  sonar_api_paginated() {
    local n
    n=$(counter_file_increment "$_HS_LIST_CTR")
    if [[ "$n" -eq 1 ]]; then
      echo '[{"key":"HS1","status":"TO_REVIEW","vulnerabilityProbability":"HIGH","securityCategory":"sql-injection","message":"Review this hotspot","component":"my-project:src/Main.java","line":42,"ruleKey":"java:S3649","creationDate":"2024-01-01T10:00:00+0000","updateDate":"2024-01-01T10:00:00+0000"}]'
    else
      echo '[{"key":"HS2","status":"REVIEWED","vulnerabilityProbability":"MEDIUM","securityCategory":"xss","message":"Reviewed hotspot","component":"my-project:src/Web.java","line":7,"ruleKey":"java:S5131","creationDate":"2024-01-02T10:00:00+0000","updateDate":"2024-01-03T10:00:00+0000"}]'
    fi
  }
  export -f sonar_api_paginated counter_file_increment

  run fetch_all_hotspots
  rm -f "$_HS_LIST_CTR"
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq 'length')
  [ "$count" -eq 2 ]
}

@test "fetch_all_hotspots: preserves review status and rule key" {
  export _HS_LIST_CTR2
  _HS_LIST_CTR2=$(counter_file_new)

  sonar_api_paginated() {
    local n
    n=$(counter_file_increment "$_HS_LIST_CTR2")
    if [[ "$n" -eq 1 ]]; then
      echo '[{"key":"HS1","status":"TO_REVIEW","message":"Review this hotspot","component":"my-project:src/Main.java","line":42,"ruleKey":"java:S3649"}]'
    else
      echo '[{"key":"HS2","status":"REVIEWED","message":"Reviewed hotspot","component":"my-project:src/Web.java","line":7,"ruleKey":"java:S5131"}]'
    fi
  }
  export -f sonar_api_paginated counter_file_increment

  run fetch_all_hotspots
  rm -f "$_HS_LIST_CTR2"
  [ "$status" -eq 0 ]
  first_status=$(echo "$output" | jq -r '.[0].status')
  second_rule=$(echo "$output" | jq -r '.[1].rule')
  [ "$first_status" = "TO_REVIEW" ]
  [ "$second_rule" = "java:S5131" ]
}

@test "fetch_all_hotspots: fails when paginated call fails" {
  sonar_api_paginated() { return 1; }
  export -f sonar_api_paginated

  run fetch_all_hotspots
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_last_analysis_date
# ===========================================================================

@test "fetch_last_analysis_date: returns latest analysis timestamp" {
  sonar_api_get() { echo '{"analyses":[{"key":"AXyz_analysis_456","date":"2024-01-14T09:30:00+0000"}]}'; }
  export -f sonar_api_get

  run fetch_last_analysis_date
  [ "$status" -eq 0 ]
  [ "$output" = "2024-01-14T09:30:00+0000" ]
}

@test "fetch_last_analysis_date: appends branch param when SONAR_BRANCH is set" {
  export SONAR_BRANCH="feature/my-branch"
  export _ENDPOINT_FILE
  _ENDPOINT_FILE=$(mktemp)

  sonar_api_get() {
    echo "$1" >"$_ENDPOINT_FILE"
    echo '{"analyses":[]}'
  }
  export -f sonar_api_get

  run fetch_last_analysis_date
  local received_endpoint
  received_endpoint=$(cat "$_ENDPOINT_FILE")
  rm -f "$_ENDPOINT_FILE"
  [ "$status" -eq 0 ]
  [[ "$received_endpoint" == *"branch=feature/my-branch"* ]]
}

# ===========================================================================
# fetch_all_metrics
# ===========================================================================

@test "fetch_all_metrics: returns complete JSON structure" {
  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{"bugs":"2"}}'; }
  fetch_issues_summary()   { echo '{"total":18,"byType":{"BUG":2},"bySeverity":{"CRITICAL":2}}'; }
  fetch_hotspots_summary() { echo '{"total":10,"toReview":3,"reviewed":7}'; }
  fetch_all_issues()       { echo '[{"key":"AXyz111","severity":"CRITICAL","type":"BUG","message":"test","component":"my-project:Main.java","line":1,"rule":"java:S1","effort":"5min","creationDate":"2024-01-01"}]'; }
  fetch_all_hotspots()     { echo '[{"key":"HS1","status":"TO_REVIEW","message":"hotspot","component":"my-project:Main.java","line":1,"rule":"java:S3649"}]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  # Suppress log output so $output contains only the JSON result
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]

  has_metadata=$(echo "$output" | jq 'has("metadata")')
  has_gate=$(echo "$output" | jq 'has("qualityGate")')
  has_measures=$(echo "$output" | jq 'has("measures")')
  has_issues=$(echo "$output" | jq 'has("issuesSummary")')
  has_hotspots=$(echo "$output" | jq 'has("hotspotsSummary")')
  has_issue_list=$(echo "$output" | jq 'has("issues")')
  has_hotspot_list=$(echo "$output" | jq 'has("hotspots")')

  [ "$has_metadata"   = "true" ]
  [ "$has_gate"       = "true" ]
  [ "$has_measures"   = "true" ]
  [ "$has_issues"     = "true" ]
  [ "$has_hotspots"   = "true" ]
  [ "$has_issue_list" = "true" ]
  [ "$has_hotspot_list" = "true" ]
}

@test "fetch_all_metrics: metadata contains projectKey" {
  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  project_key=$(echo "$output" | jq -r '.metadata.projectKey')
  [ "$project_key" = "my-project" ]
}

@test "fetch_all_metrics: metadata contains lastAnalysisDate" {
  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  last_analysis_date=$(echo "$output" | jq -r '.metadata.lastAnalysisDate')
  [ "$last_analysis_date" = "2024-01-14T09:30:00+0000" ]
}

@test "fetch_all_metrics: fails when fetch_quality_gate fails" {
  fetch_quality_gate()     { return 1; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  log_error() { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok log_error

  run fetch_all_metrics
  [ "$status" -ne 0 ]
}

@test "fetch_all_metrics: fails when fetch_measures fails" {
  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { return 1; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  log_error() { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok log_error

  run fetch_all_metrics
  [ "$status" -ne 0 ]
}

# ===========================================================================
# fetch_all_metrics — SonarCloud mode
# ===========================================================================

@test "fetch_all_metrics: SonarCloud mode does not call fetch_last_analysis_date" {
  export SONAR_CLOUD=true
  export _CALLED_FILE
  _CALLED_FILE=$(mktemp)

  fetch_quality_gate()       { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()           { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()     { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary()   { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()         { echo '[]'; }
  fetch_all_hotspots()       { echo '[]'; }
  fetch_last_analysis_date() { echo "called" >"$_CALLED_FILE"; echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  local was_called
  was_called=$(cat "$_CALLED_FILE")
  rm -f "$_CALLED_FILE"
  [ "$status" -eq 0 ]
  [ -z "$was_called" ]
}

@test "fetch_all_metrics: SonarCloud mode produces empty lastAnalysisDate in metadata" {
  export SONAR_CLOUD=true

  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  last_date=$(echo "$output" | jq -r '.metadata.lastAnalysisDate')
  [ -z "$last_date" ] || [ "$last_date" = "null" ]
}

@test "fetch_all_metrics: SonarCloud mode sets sonarCloud=true in metadata" {
  export SONAR_CLOUD=true

  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  sonar_cloud=$(echo "$output" | jq -r '.metadata.sonarCloud')
  [ "$sonar_cloud" = "true" ]
}

@test "fetch_all_metrics: SonarCloud mode includes organization in metadata" {
  export SONAR_CLOUD=true
  export SONAR_ORGANIZATION="myorg"

  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  org=$(echo "$output" | jq -r '.metadata.organization')
  [ "$org" = "myorg" ]
}

@test "fetch_all_metrics: non-SonarCloud mode calls fetch_last_analysis_date" {
  export SONAR_CLOUD=false
  export _CALLED_FILE2
  _CALLED_FILE2=$(mktemp)

  fetch_quality_gate()       { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()           { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()     { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary()   { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()         { echo '[]'; }
  fetch_all_hotspots()       { echo '[]'; }
  fetch_last_analysis_date() { echo "called" >"$_CALLED_FILE2"; echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  local was_called
  was_called=$(cat "$_CALLED_FILE2")
  rm -f "$_CALLED_FILE2"
  [ "$status" -eq 0 ]
  [ "$was_called" = "called" ]
}

# ===========================================================================
# fetch_all_metrics — enrichment hook
# ===========================================================================

@test "fetch_all_metrics: omits metadata.enrichment when no flags set" {
  unset INCLUDE_RULE_DESCRIPTIONS INCLUDE_CODE_SNIPPETS
  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  has_enrich=$(echo "$output" | jq '.metadata | has("enrichment")')
  [ "$has_enrich" = "false" ]
}

@test "fetch_all_metrics: metadata.enrichment reflects flag state when enabled" {
  export INCLUDE_RULE_DESCRIPTIONS="short"
  export INCLUDE_CODE_SNIPPETS="true"
  export SNIPPET_CONTEXT="5"

  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  rd=$(echo "$output" | jq -r '.metadata.enrichment.ruleDescriptions')
  cs=$(echo "$output" | jq -r '.metadata.enrichment.codeSnippets')
  ctx=$(echo "$output" | jq -r '.metadata.enrichment.snippetContext')
  [ "$rd" = "short" ]
  [ "$cs" = "true" ]
  [ "$ctx" = "5" ]
}

@test "fetch_all_metrics: invokes enrich_issue_objects when INCLUDE_RULE_DESCRIPTIONS set" {
  export INCLUDE_RULE_DESCRIPTIONS="short"
  unset INCLUDE_CODE_SNIPPETS

  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[{"key":"K1","rule":"java:S1","line":1,"startLine":1,"endLine":1,"component":"p:src/A.java"}]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }

  enrich_issue_objects() {
    # Tag the issue so we can verify the enrichment path was taken
    echo "$1" | jq 'map(. + {ruleDescription: {whyText: "from mock"}})'
  }
  enrich_hotspot_objects() { echo "$1"; }
  log_info() { :; }
  log_ok()   { :; }
  log_warn() { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date enrich_issue_objects enrich_hotspot_objects log_info log_ok log_warn

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  why=$(echo "$output" | jq -r '.issues[0].ruleDescription.whyText')
  [ "$why" = "from mock" ]
}

@test "fetch_all_metrics: fails when issue enrichment fails" {
  export INCLUDE_RULE_DESCRIPTIONS="short"
  unset INCLUDE_CODE_SNIPPETS

  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[{"key":"K1","rule":"java:S1","line":1,"startLine":1,"endLine":1,"component":"p:src/A.java"}]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  enrich_issue_objects()   { echo '[ERROR] Response: {"errors":[{"msg":"boom"}]}' >&2; return 1; }
  enrich_hotspot_objects() { echo "$1"; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary \
            fetch_all_issues fetch_all_hotspots fetch_last_analysis_date \
            enrich_issue_objects enrich_hotspot_objects log_info log_ok

  run fetch_all_metrics
  [ "$status" -ne 0 ]
  [[ "$output" == *'Response: {"errors":[{"msg":"boom"}]}'* ]]
  [[ "$output" == *"Failed to enrich issue details"* ]]
}

@test "fetch_all_metrics: does not invoke enrich_issue_objects when flags off" {
  unset INCLUDE_RULE_DESCRIPTIONS INCLUDE_CODE_SNIPPETS

  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[{"key":"K1","rule":"java:S1","line":1,"startLine":1,"endLine":1,"component":"p:src/A.java"}]'; }
  fetch_all_hotspots()     { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }

  # If enrichment path runs, this mock would mutate the issue
  enrich_issue_objects()   { echo '[{"key":"SHOULD_NOT_BE_CALLED"}]'; }
  enrich_hotspot_objects() { echo "$1"; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date enrich_issue_objects enrich_hotspot_objects log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  key=$(echo "$output" | jq -r '.issues[0].key')
  [ "$key" = "K1" ]
}

@test "fetch_all_metrics: non-SonarCloud mode sets sonarCloud=false in metadata" {
  export SONAR_CLOUD=false

  fetch_quality_gate()       { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()           { echo '{"componentName":"My Project","componentKey":"my-project","qualifier":"TRK","measures":{}}'; }
  fetch_issues_summary()     { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary()   { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()         { echo '[]'; }
  fetch_all_hotspots()       { echo '[]'; }
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }
  log_ok()   { :; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary fetch_hotspots_summary fetch_all_issues fetch_all_hotspots fetch_last_analysis_date log_info log_ok

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  sonar_cloud=$(echo "$output" | jq -r '.metadata.sonarCloud')
  [ "$sonar_cloud" = "false" ]
}

# ==============================================================================
# fetch_all_metrics — last-analysis-date and enrichment branches
# ==============================================================================

_mock_basic_fetchers() {
  fetch_quality_gate()     { echo '{"status":"OK","conditions":[]}'; }
  fetch_measures()         { echo '{"componentName":"P","measures":{}}'; }
  fetch_issues_summary()   { echo '{"total":0,"byType":{},"bySeverity":{}}'; }
  fetch_hotspots_summary() { echo '{"total":0,"toReview":0,"reviewed":0}'; }
  fetch_all_issues()       { echo '[]'; }
  fetch_all_hotspots()     { echo '[]'; }
  export -f fetch_quality_gate fetch_measures fetch_issues_summary \
            fetch_hotspots_summary fetch_all_issues fetch_all_hotspots
}

@test "fetch_all_metrics: warns when last analysis date is empty" {
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo ''; }
  export -f fetch_last_analysis_date
  export SONAR_CLOUD=false
  run fetch_all_metrics
  [ "$status" -eq 0 ]
  [[ "$output" == *"Last analysis date is unavailable"* ]]
}

@test "fetch_all_metrics: continues when last analysis date fetch fails" {
  _mock_basic_fetchers
  fetch_last_analysis_date() { return 1; }
  export -f fetch_last_analysis_date
  export SONAR_CLOUD=false
  run fetch_all_metrics
  [ "$status" -eq 0 ]
  [[ "$output" == *"Failed to fetch last analysis date"* ]]
}

@test "fetch_all_metrics: builds enrichment metadata when code snippets enabled" {
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  enrich_issue_objects()   { echo "$1"; }
  enrich_hotspot_objects() { echo "$1"; }
  log_info() { :; }; log_ok() { :; }; log_warn() { :; }
  export -f fetch_last_analysis_date enrich_issue_objects enrich_hotspot_objects \
            log_info log_ok log_warn
  export SONAR_CLOUD=false INCLUDE_CODE_SNIPPETS=true SNIPPET_CONTEXT=3
  run fetch_all_metrics
  [ "$status" -eq 0 ]
  cs=$(echo "$output" | jq -r '.metadata.enrichment.codeSnippets')
  [ "$cs" = "true" ]
}

# ===========================================================================
# fetch_all_metrics — quality profiles & quality gate name
# ===========================================================================

@test "fetch_all_metrics: omits qualityGateName and qualityProfiles when flags off" {
  unset INCLUDE_QUALITY_PROFILES INCLUDE_QUALITY_GATE_NAME
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  log_info() { :; }; log_ok() { :; }
  export -f fetch_last_analysis_date log_info log_ok
  export SONAR_CLOUD=false

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  has_gate_name=$(echo "$output" | jq '.metadata | has("qualityGateName")')
  has_profiles=$(echo "$output" | jq '.metadata | has("qualityProfiles")')
  [ "$has_gate_name" = "false" ]
  [ "$has_profiles" = "false" ]
}

@test "fetch_all_metrics: includes qualityGateName when INCLUDE_QUALITY_GATE_NAME enabled" {
  export INCLUDE_QUALITY_GATE_NAME=true
  unset INCLUDE_QUALITY_PROFILES
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  fetch_quality_gate_name() { echo 'Sonar way'; }
  log_info() { :; }; log_ok() { :; }
  export -f fetch_last_analysis_date fetch_quality_gate_name log_info log_ok
  export SONAR_CLOUD=false

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  gate_name=$(echo "$output" | jq -r '.metadata.qualityGateName')
  [ "$gate_name" = "Sonar way" ]
  has_profiles=$(echo "$output" | jq '.metadata | has("qualityProfiles")')
  [ "$has_profiles" = "false" ]
}

@test "fetch_all_metrics: includes qualityProfiles when INCLUDE_QUALITY_PROFILES enabled" {
  export INCLUDE_QUALITY_PROFILES=true
  unset INCLUDE_QUALITY_GATE_NAME
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  fetch_quality_profiles() { echo '[{"key":"k","name":"Sonar way","language":"java","languageName":"Java"}]'; }
  log_info() { :; }; log_ok() { :; }
  export -f fetch_last_analysis_date fetch_quality_profiles log_info log_ok
  export SONAR_CLOUD=false

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq '.metadata.qualityProfiles | length')
  name=$(echo "$output" | jq -r '.metadata.qualityProfiles[0].name')
  [ "$count" -eq 1 ]
  [ "$name" = "Sonar way" ]
  has_gate_name=$(echo "$output" | jq '.metadata | has("qualityGateName")')
  [ "$has_gate_name" = "false" ]
}

@test "fetch_all_metrics: qualityGateName present but empty when gate-name fetch fails" {
  export INCLUDE_QUALITY_GATE_NAME=true
  unset INCLUDE_QUALITY_PROFILES
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  fetch_quality_gate_name() { return 1; }
  log_info() { :; }; log_ok() { :; }; log_warn() { :; }
  export -f fetch_last_analysis_date fetch_quality_gate_name log_info log_ok log_warn
  export SONAR_CLOUD=false

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  has_gate_name=$(echo "$output" | jq '.metadata | has("qualityGateName")')
  gate_name=$(echo "$output" | jq -r '.metadata.qualityGateName')
  [ "$has_gate_name" = "true" ]
  [ -z "$gate_name" ]
}

@test "fetch_all_metrics: qualityProfiles present but empty when profiles fetch fails" {
  export INCLUDE_QUALITY_PROFILES=true
  unset INCLUDE_QUALITY_GATE_NAME
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  fetch_quality_profiles() { return 1; }
  log_info() { :; }; log_ok() { :; }; log_warn() { :; }
  export -f fetch_last_analysis_date fetch_quality_profiles log_info log_ok log_warn
  export SONAR_CLOUD=false

  run fetch_all_metrics
  [ "$status" -eq 0 ]
  has_profiles=$(echo "$output" | jq '.metadata | has("qualityProfiles")')
  count=$(echo "$output" | jq '.metadata.qualityProfiles | length')
  [ "$has_profiles" = "true" ]
  [ "$count" -eq 0 ]
}

@test "fetch_all_metrics: does not fetch quality data when flags off" {
  unset INCLUDE_QUALITY_PROFILES INCLUDE_QUALITY_GATE_NAME
  export _QCALL_FILE
  _QCALL_FILE=$(mktemp)
  _mock_basic_fetchers
  fetch_last_analysis_date() { echo '2024-01-14T09:30:00+0000'; }
  fetch_quality_gate_name() { echo "called" >>"$_QCALL_FILE"; echo 'X'; }
  fetch_quality_profiles() { echo "called" >>"$_QCALL_FILE"; echo '[]'; }
  log_info() { :; }; log_ok() { :; }
  export -f fetch_last_analysis_date fetch_quality_gate_name fetch_quality_profiles log_info log_ok
  export SONAR_CLOUD=false

  run fetch_all_metrics
  local calls
  calls=$(cat "$_QCALL_FILE")
  rm -f "$_QCALL_FILE"
  [ "$status" -eq 0 ]
  [ -z "$calls" ]
}
