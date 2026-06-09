#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_portfolio.bats — Unit tests for scripts/lib/portfolio.sh
#
# fetch_portfolio_metrics is exercised with fetch_all_metrics mocked to return
# per-project fixtures (keyed off the SONAR_PROJECT_KEY global), so no network
# calls are made. The merge/ranking jq (portfolio-aggregate.jq) is covered too.
# ==============================================================================

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

setup() {
  # shellcheck source=../scripts/lib/portfolio.sh
  source "${REPO_ROOT}/scripts/lib/portfolio.sh"

  SONAR_URL="http://sonar.example.com"
  SONAR_TOKEN="test-token"
  SONAR_BRANCH=""
  SONAR_CLOUD="false"
  SONAR_ORGANIZATION="acme-org"
  SEVERITY_THRESHOLD=""
  ISSUE_TYPES=""
  MAX_ISSUES=""
  SONAR_PROJECT_KEYS=(proj-a proj-b)

  # Return a different fixture per project key (mirrors the live fetch loop,
  # which sets SONAR_PROJECT_KEY before each fetch_all_metrics call).
  fetch_all_metrics() {
    case "$SONAR_PROJECT_KEY" in
      proj-a) cat "${FIXTURES}/portfolio_project_a.json" ;;
      proj-b) cat "${FIXTURES}/portfolio_project_b.json" ;;
      *)      return 1 ;;
    esac
  }
}

@test "fetch_portfolio_metrics: marks the report as a portfolio with a project count" {
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.metadata.reportType')" = "portfolio" ]
  [ "$(echo "$output" | jq -r '.metadata.projectCount')" = "2" ]
  [ "$(echo "$output" | jq -r '.metadata.projectKeys | join(",")')" = "proj-a,proj-b" ]
}

@test "fetch_portfolio_metrics: sums measures and issue counts across projects" {
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.bugs')" = "11" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.code_smells')" = "120" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.issues.total')" = "136" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.issues.bySeverity.CRITICAL')" = "7" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.ncloc')" = "4000" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.hotspots.total')" = "10" ]
}

@test "fetch_portfolio_metrics: counts passed and failed quality gates" {
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.gatesPassed')" = "1" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.gatesFailed')" = "1" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.gatesOther')" = "0" ]
}

@test "fetch_portfolio_metrics: ncloc-weighted coverage aggregate" {
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  # (40*1000 + 90*3000) / 4000 = 77.5
  [ "$(echo "$output" | jq -r '.portfolio.aggregates.coverage')" = "77.5" ]
}

@test "fetch_portfolio_metrics: worst offenders rank failed gate, then blocker+critical" {
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.portfolio.worstOffenders[0].projectKey')" = "proj-a" ]
  [ "$(echo "$output" | jq -r '.portfolio.worstOffenders[0].gateStatus')" = "ERROR" ]
  [ "$(echo "$output" | jq -r '.portfolio.worstOffenders[0].blockerCritical')" = "10" ]
  [ "$(echo "$output" | jq -r '.portfolio.worstOffenders[1].projectKey')" = "proj-b" ]
}

@test "fetch_portfolio_metrics: retains full per-project detail for drill-down" {
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.portfolio.projects | length')" = "2" ]
  [ "$(echo "$output" | jq -r '.portfolio.projects[0].issues | length')" = "1" ]
  [ "$(echo "$output" | jq -r '.portfolio.projects[0].hotspots[0].key')" = "A-HS1" ]
}

@test "fetch_portfolio_metrics: applies display filters per project" {
  SEVERITY_THRESHOLD="BLOCKER"
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  # proj-a keeps its BLOCKER issue; proj-b's lone CRITICAL issue is filtered out.
  [ "$(echo "$output" | jq -r '.portfolio.projects[0].issues | length')" = "1" ]
  [ "$(echo "$output" | jq -r '.portfolio.projects[1].issues | length')" = "0" ]
  # Per-project filter metadata is preserved.
  [ "$(echo "$output" | jq -r '.portfolio.projects[1].metadata.filtersApplied.severityThreshold')" = "BLOCKER" ]
}

@test "fetch_portfolio_metrics: fails when a project's fetch fails" {
  SONAR_PROJECT_KEYS=(proj-a missing-project)
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to collect analysis data for project: missing-project"* ]]
}

@test "fetch_portfolio_metrics: single key still produces a one-project portfolio" {
  SONAR_PROJECT_KEYS=(proj-a)
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.metadata.projectCount')" = "1" ]
  [ "$(echo "$output" | jq -r '.portfolio.totals.gatesFailed')" = "1" ]
}

@test "fetch_portfolio_metrics: errors when no project keys are set" {
  SONAR_PROJECT_KEYS=()
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"No project keys provided"* ]]
}

@test "fetch_portfolio_metrics: errors when a temp file cannot be created" {
  create_temp_file() { return 1; }
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to create temp file"* ]]
}

@test "fetch_portfolio_metrics: errors when per-project filtering fails" {
  apply_issue_filters() { return 1; }
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to apply issue filters"* ]]
}

@test "fetch_portfolio_metrics: errors when the aggregation merge fails" {
  # The merge is the only jq call in this function (no filters configured),
  # so failing jq isolates the merge-failure branch.
  jq() { return 1; }
  run --separate-stderr fetch_portfolio_metrics
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to aggregate portfolio data"* ]]
}
