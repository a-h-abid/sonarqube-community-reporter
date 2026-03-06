#!/usr/bin/env bash
# ==============================================================================
# metrics.sh — Fetch SonarQube measures, quality gate, issues, and hotspots
# ==============================================================================
set -euo pipefail

_METRICS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_METRICS_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# Standard metric keys to fetch
# ---------------------------------------------------------------------------
METRIC_KEYS="bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density"
METRIC_KEYS="${METRIC_KEYS},ncloc,sqale_index,sqale_debt_ratio"
METRIC_KEYS="${METRIC_KEYS},reliability_rating,security_rating,sqale_rating"
METRIC_KEYS="${METRIC_KEYS},security_hotspots_reviewed,security_review_rating"
METRIC_KEYS="${METRIC_KEYS},alert_status"
METRIC_KEYS="${METRIC_KEYS},new_bugs,new_vulnerabilities,new_code_smells"
METRIC_KEYS="${METRIC_KEYS},new_coverage,new_duplicated_lines_density"

# ---------------------------------------------------------------------------
# fetch_quality_gate
#   Fetches the quality gate status for the project.
#   Output: JSON object with status and conditions.
# ---------------------------------------------------------------------------
fetch_quality_gate() {
  local project_key="${SONAR_PROJECT_KEY}"
  local branch_param=""
  [[ -n "${SONAR_BRANCH:-}" ]] && branch_param="&branch=${SONAR_BRANCH}"

  local response
  response=$(sonar_api_get "qualitygates/project_status?projectKey=${project_key}${branch_param}") || return 1

  echo "$response" | jq '{
    status: .projectStatus.status,
    conditions: [
      .projectStatus.conditions[]? | {
        metric: .metricKey,
        status: .status,
        actualValue: .actualValue,
        errorThreshold: .errorThreshold,
        comparator: .comparator
      }
    ]
  }'
}

# ---------------------------------------------------------------------------
# fetch_measures
#   Fetches all key metrics for the project.
#   Output: JSON object with metric key-value pairs.
# ---------------------------------------------------------------------------
fetch_measures() {
  local project_key="${SONAR_PROJECT_KEY}"
  local branch_param=""
  [[ -n "${SONAR_BRANCH:-}" ]] && branch_param="&branch=${SONAR_BRANCH}"

  local response
  response=$(sonar_api_get "measures/component?component=${project_key}&metricKeys=${METRIC_KEYS}${branch_param}") || return 1

  # Transform into a convenient key-value map
  echo "$response" | jq '{
    measures: (
      [.component.measures[]? | {(.metric): .value}] | add // {}
    ),
    componentName: .component.name,
    componentKey: .component.key,
    qualifier: .component.qualifier
  }'
}

# ---------------------------------------------------------------------------
# fetch_issues_summary
#   Fetches aggregate issue counts using facets (no bulk issue fetch).
#   Output: JSON object with counts by type and severity.
# ---------------------------------------------------------------------------
fetch_issues_summary() {
  local project_key="${SONAR_PROJECT_KEY}"
  local branch_param=""
  [[ -n "${SONAR_BRANCH:-}" ]] && branch_param="&branch=${SONAR_BRANCH}"

  local response
  response=$(sonar_api_get "issues/search?componentKeys=${project_key}&issueStatuses=OPEN,CONFIRMED&facets=types,severities&ps=1${branch_param}") || return 1

  echo "$response" | jq '{
    total: .total,
    byType: (
      [.facets[]? | select(.property == "types") | .values[]? | {(.val): .count}] | add // {}
    ),
    bySeverity: (
      [.facets[]? | select(.property == "severities") | .values[]? | {(.val): .count}] | add // {}
    )
  }'
}

# ---------------------------------------------------------------------------
# fetch_hotspots_summary
#   Fetches security hotspot counts.
#   Output: JSON object with total, toReview, and reviewed counts.
# ---------------------------------------------------------------------------
fetch_hotspots_summary() {
  local project_key="${SONAR_PROJECT_KEY}"
  local branch_param=""
  [[ -n "${SONAR_BRANCH:-}" ]] && branch_param="&branch=${SONAR_BRANCH}"

  # Fetch TO_REVIEW hotspots count
  local to_review_response
  to_review_response=$(sonar_api_get "hotspots/search?projectKey=${project_key}&status=TO_REVIEW&ps=1${branch_param}") || return 1

  local to_review
  to_review=$(echo "$to_review_response" | jq '.paging.total // 0')

  # Fetch REVIEWED hotspots count
  local reviewed_response
  reviewed_response=$(sonar_api_get "hotspots/search?projectKey=${project_key}&status=REVIEWED&ps=1${branch_param}") || return 1

  local reviewed
  reviewed=$(echo "$reviewed_response" | jq '.paging.total // 0')

  local total=$((to_review + reviewed))

  jq -n --argjson total "$total" \
        --argjson toReview "$to_review" \
        --argjson reviewed "$reviewed" \
    '{total: $total, toReview: $toReview, reviewed: $reviewed}'
}

# ---------------------------------------------------------------------------
# fetch_all_issues
#   Fetches all unresolved issues using pagination, sorted by severity.
#   Output: JSON array of issue objects.
# ---------------------------------------------------------------------------
fetch_all_issues() {
  local project_key="${SONAR_PROJECT_KEY}"

  local params=("componentKeys=${project_key}" "issueStatuses=OPEN,CONFIRMED" "s=SEVERITY" "asc=false")
  [[ -n "${SONAR_BRANCH:-}" ]] && params+=("branch=${SONAR_BRANCH}")

  local all_issues
  all_issues=$(sonar_api_paginated "issues/search" ".issues" 20 "${params[@]}") || return 1

  echo "$all_issues" | jq '[.[]? | {
    key: .key,
    severity: .severity,
    type: .type,
    message: .message,
    component: .component,
    line: .line,
    rule: .rule,
    effort: .effort,
    creationDate: .creationDate
  }]'
}

# ---------------------------------------------------------------------------
# fetch_last_analysis_date
#   Fetches the latest analysis timestamp for the project.
#   Output: ISO-8601 timestamp string, or empty when unavailable.
# ---------------------------------------------------------------------------
fetch_last_analysis_date() {
  local project_key="${SONAR_PROJECT_KEY}"
  local branch_param=""
  [[ -n "${SONAR_BRANCH:-}" ]] && branch_param="&branch=${SONAR_BRANCH}"

  local response
  response=$(sonar_api_get "project_analyses/search?project=${project_key}&ps=1${branch_param}") || return 1

  echo "$response" | jq -r '.analyses[0].date // empty'
}

# ---------------------------------------------------------------------------
# fetch_all_metrics
#   Fetches everything and assembles a unified JSON object.
#   Output: Complete JSON report data.
# ---------------------------------------------------------------------------
fetch_all_metrics() {
  log_info "Fetching quality gate status ..."
  local quality_gate
  quality_gate=$(fetch_quality_gate) || { log_error "Failed to fetch quality gate"; return 1; }
  log_ok "Quality gate fetched"

  log_info "Fetching project measures ..."
  local measures
  measures=$(fetch_measures) || { log_error "Failed to fetch measures"; return 1; }
  log_ok "Measures fetched"

  log_info "Fetching issues summary ..."
  local issues_summary
  issues_summary=$(fetch_issues_summary) || { log_error "Failed to fetch issues"; return 1; }
  log_ok "Issues summary fetched"

  log_info "Fetching security hotspots ..."
  local hotspots_summary
  hotspots_summary=$(fetch_hotspots_summary) || { log_error "Failed to fetch hotspots"; return 1; }
  log_ok "Hotspots summary fetched"

  log_info "Fetching all issues ..."
  local all_issues
  all_issues=$(fetch_all_issues) || { log_error "Failed to fetch issues"; return 1; }
  log_ok "Issues fetched"

  local last_analysis_date=""
  log_info "Fetching last analysis date ..."
  if last_analysis_date=$(fetch_last_analysis_date); then
    if [[ -n "$last_analysis_date" ]]; then
      log_ok "Last analysis date fetched"
    else
      log_warn "Last analysis date is unavailable for this project"
    fi
  else
    log_warn "Failed to fetch last analysis date; continuing without it"
    last_analysis_date=""
  fi

  # Assemble the complete report data
  local report_date
  report_date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Pipe large JSON data via stdin to avoid "Argument list too long" errors
  # when the issues list is large enough to exceed the OS ARG_MAX limit.
  {
    echo "$quality_gate"
    echo "$measures"
    echo "$issues_summary"
    echo "$hotspots_summary"
    echo "$all_issues"
  } | jq -s \
    --arg projectKey "${SONAR_PROJECT_KEY}" \
    --arg branch "${SONAR_BRANCH:-main}" \
    --arg sonarUrl "${SONAR_URL}" \
    --arg reportDate "$report_date" \
    --arg lastAnalysisDate "$last_analysis_date" \
    --arg analysisId "${ANALYSIS_ID:-}" \
    '{
      metadata: {
        projectKey: $projectKey,
        projectName: .[1].componentName,
        branch: $branch,
        sonarUrl: $sonarUrl,
        reportDate: $reportDate,
        lastAnalysisDate: $lastAnalysisDate,
        analysisId: $analysisId
      },
      qualityGate: .[0],
      measures: .[1].measures,
      issuesSummary: .[2],
      hotspotsSummary: .[3],
      issues: .[4]
    }'
}
