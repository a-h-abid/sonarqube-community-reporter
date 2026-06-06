#!/usr/bin/env bash
# ==============================================================================
# metrics.sh — Fetch SonarQube measures, quality gate, issues, and hotspots
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_METRICS_SH_LOADED:-}" ]] && return 0
_METRICS_SH_LOADED=1

set -euo pipefail

_METRICS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_METRICS_SCRIPT_DIR}/api.sh"
# shellcheck source=rule-details.sh
source "${_METRICS_SCRIPT_DIR}/rule-details.sh"

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

  # kcov-skip-start
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
  # kcov-skip-end
}

# ---------------------------------------------------------------------------
# fetch_quality_gate_name
#   Fetches the name of the quality gate assigned to the project.
#   Output: gate name string, or empty when unavailable.
#   Note: get_by_project uses the `project` query param (not `projectKey`),
#   and is project-level (no branch parameter).
# ---------------------------------------------------------------------------
fetch_quality_gate_name() {
  local project_key="${SONAR_PROJECT_KEY}"

  local response
  response=$(sonar_api_get "qualitygates/get_by_project?project=${project_key}") || return 1

  echo "$response" | jq -r '.qualityGate.name // empty'
}

# ---------------------------------------------------------------------------
# fetch_quality_profiles
#   Fetches the quality profiles associated with the project (one per
#   language used). Output: JSON array of {key, name, language, languageName}.
#   Note: qualityprofiles/search uses the `project` query param and is
#   project-level (no branch parameter).
# ---------------------------------------------------------------------------
fetch_quality_profiles() {
  local project_key="${SONAR_PROJECT_KEY}"

  local response
  response=$(sonar_api_get "qualityprofiles/search?project=${project_key}") || return 1

  # kcov-skip-start
  echo "$response" | jq '[.profiles[]? | {
    key: .key,
    name: .name,
    language: .language,
    languageName: .languageName
  }]'
  # kcov-skip-end
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
  # kcov-skip-start
  echo "$response" | jq '{
    measures: (
      [.component.measures[]? | {(.metric): .value}] | add // {}
    ),
    componentName: .component.name,
    componentKey: .component.key,
    qualifier: .component.qualifier
  }'
  # kcov-skip-end
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

  # kcov-skip-start
  echo "$response" | jq '{
    total: .total,
    byType: (
      [.facets[]? | select(.property == "types") | .values[]? | {(.val): .count}] | add // {}
    ),
    bySeverity: (
      [.facets[]? | select(.property == "severities") | .values[]? | {(.val): .count}] | add // {}
    )
  }'
  # kcov-skip-end
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

  # kcov-skip-start
  echo "$all_issues" | jq '[.[]? | {
    key: .key,
    severity: .severity,
    type: .type,
    message: .message,
    component: .component,
    line: .line,
    startLine: (.textRange.startLine // .line),
    endLine: (.textRange.endLine // .line),
    rule: .rule,
    effort: .effort,
    creationDate: .creationDate
  }]'
  # kcov-skip-end
}

# ---------------------------------------------------------------------------
# fetch_all_hotspots
#   Fetches all security hotspots for both review states.
#   Output: JSON array of hotspot objects.
# ---------------------------------------------------------------------------
fetch_all_hotspots() {
  local project_key="${SONAR_PROJECT_KEY}"

  local base_params=("projectKey=${project_key}")
  [[ -n "${SONAR_BRANCH:-}" ]] && base_params+=("branch=${SONAR_BRANCH}")

  local to_review_params=("${base_params[@]}" "status=TO_REVIEW")
  local reviewed_params=("${base_params[@]}" "status=REVIEWED")

  local to_review_hotspots
  to_review_hotspots=$(sonar_api_paginated "hotspots/search" ".hotspots" 20 "${to_review_params[@]}") || return 1

  local reviewed_hotspots
  reviewed_hotspots=$(sonar_api_paginated "hotspots/search" ".hotspots" 20 "${reviewed_params[@]}") || return 1

  # kcov-skip-start
  {
    echo "$to_review_hotspots"
    echo "$reviewed_hotspots"
  } | jq -s 'add // [] | map({
    key: .key,
    status: .status,
    resolution: (.resolution // ""),
    vulnerabilityProbability: (.vulnerabilityProbability // .probability // ""),
    securityCategory: (.securityCategory // ""),
    message: (.message // .vulnerabilityDescription // ""),
    component: .component,
    line: .line,
    startLine: (.textRange.startLine // .line),
    endLine: (.textRange.endLine // .line),
    rule: (.ruleKey // .rule // ""),
    author: (.author // ""),
    creationDate: (.creationDate // ""),
    updateDate: (.updateDate // "")
  })'
  # kcov-skip-end
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

  log_info "Fetching security hotspot details ..."
  local all_hotspots
  all_hotspots=$(fetch_all_hotspots) || { log_error "Failed to fetch hotspot details"; return 1; }
  log_ok "Hotspot details fetched"

  if [[ -n "${INCLUDE_RULE_DESCRIPTIONS:-}" ]] || [[ "${INCLUDE_CODE_SNIPPETS:-false}" == "true" ]]; then
    log_info "Enriching issue details ..."
    all_issues=$(enrich_issue_objects "$all_issues") || {
      log_error "Failed to enrich issue details"
      return 1
    }
    log_ok "Issues enriched"

    log_info "Enriching hotspot details ..."
    all_hotspots=$(enrich_hotspot_objects "$all_hotspots") || {
      log_error "Failed to enrich hotspot details"
      return 1
    }
    log_ok "Hotspots enriched"
  fi

  local last_analysis_date=""
  if [[ "${SONAR_CLOUD:-false}" == "true" ]]; then
    log_info "Skipping last analysis date (not available on SonarCloud)"
  else
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
  fi

  # Quality gate name — only fetched when INCLUDE_QUALITY_GATE_NAME is enabled.
  # Audit metadata: failures degrade gracefully (logged) and never abort the run.
  local quality_gate_name_json="null"
  if [[ "${INCLUDE_QUALITY_GATE_NAME:-false}" == "true" ]]; then
    log_info "Fetching quality gate name ..."
    local qgn=""
    if qgn=$(fetch_quality_gate_name); then
      log_ok "Quality gate name fetched"
    else
      log_warn "Failed to fetch quality gate name; continuing without it"
      qgn=""
    fi
    quality_gate_name_json=$(jq -n --arg n "$qgn" '$n')
  fi

  # Quality profiles — only fetched when INCLUDE_QUALITY_PROFILES is enabled.
  local quality_profiles_json="null"
  if [[ "${INCLUDE_QUALITY_PROFILES:-false}" == "true" ]]; then
    log_info "Fetching quality profiles ..."
    if quality_profiles_json=$(fetch_quality_profiles); then
      log_ok "Quality profiles fetched"
    else
      log_warn "Failed to fetch quality profiles; continuing without them"
      quality_profiles_json="[]"
    fi
  fi

  # Assemble the complete report data
  local report_date
  report_date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Normalize SONAR_CLOUD to a JSON boolean literal for jq --argjson
  local sonar_cloud_bool="false"
  [[ "${SONAR_CLOUD:-false}" == "true" ]] && sonar_cloud_bool="true"

  # Build enrichment metadata block — only populated when any flag is on.
  local enrichment_json="null"
  if [[ -n "${INCLUDE_RULE_DESCRIPTIONS:-}" ]] || [[ "${INCLUDE_CODE_SNIPPETS:-false}" == "true" ]]; then
    local cs_bool="false"
    [[ "${INCLUDE_CODE_SNIPPETS:-false}" == "true" ]] && cs_bool="true"
    enrichment_json=$(jq -n \
      --arg ruleDescriptions "${INCLUDE_RULE_DESCRIPTIONS:-}" \
      --argjson codeSnippets "$cs_bool" \
      --argjson snippetContext "${SNIPPET_CONTEXT:-3}" \
      '{ruleDescriptions: $ruleDescriptions, codeSnippets: $codeSnippets, snippetContext: $snippetContext}')
  fi

  # Pipe large JSON data via stdin to avoid "Argument list too long" errors
  # when the issues list is large enough to exceed the OS ARG_MAX limit.
  # kcov-skip-start
  {
    echo "$quality_gate"
    echo "$measures"
    echo "$issues_summary"
    echo "$hotspots_summary"
    echo "$all_issues"
    echo "$all_hotspots"
  } | jq -s \
    --arg projectKey "${SONAR_PROJECT_KEY}" \
    --arg branch "${SONAR_BRANCH:-main}" \
    --arg sonarUrl "${SONAR_URL}" \
    --arg reportDate "$report_date" \
    --arg lastAnalysisDate "$last_analysis_date" \
    --arg analysisId "${ANALYSIS_ID:-}" \
    --argjson sonarCloud "$sonar_cloud_bool" \
    --arg organization "${SONAR_ORGANIZATION:-}" \
    --argjson enrichment "$enrichment_json" \
    --argjson qualityGateName "$quality_gate_name_json" \
    --argjson qualityProfiles "$quality_profiles_json" \
    '{
      metadata: ({
        projectKey: $projectKey,
        projectName: .[1].componentName,
        branch: $branch,
        sonarUrl: $sonarUrl,
        reportDate: $reportDate,
        lastAnalysisDate: $lastAnalysisDate,
        analysisId: $analysisId,
        sonarCloud: $sonarCloud,
        organization: $organization
      } + (if $enrichment == null then {} else {enrichment: $enrichment} end)
        + (if $qualityGateName == null then {} else {qualityGateName: $qualityGateName} end)
        + (if $qualityProfiles == null then {} else {qualityProfiles: $qualityProfiles} end)),
      qualityGate: .[0],
      measures: .[1].measures,
      issuesSummary: .[2],
      hotspotsSummary: .[3],
      issues: .[4],
      hotspots: .[5]
    }'
  # kcov-skip-end
}
