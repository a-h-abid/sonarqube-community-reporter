#!/usr/bin/env bash
# ==============================================================================
# portfolio.sh — Multi-project (portfolio) aggregation.
#
# Fetches the unified report data for each project in SONAR_PROJECT_KEYS, applies
# the same display filters per project, then rolls everything up into a single
# portfolio report object (see scripts/lib/jq/portfolio-aggregate.jq). The result
# carries .metadata.reportType == "portfolio" and a .portfolio node that all
# report generators branch on, so a portfolio spans every output format.
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_PORTFOLIO_SH_LOADED:-}" ]] && return 0
_PORTFOLIO_SH_LOADED=1

set -euo pipefail

_PORTFOLIO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/api.sh
source "${_PORTFOLIO_SCRIPT_DIR}/api.sh"
# shellcheck source=scripts/lib/metrics.sh
source "${_PORTFOLIO_SCRIPT_DIR}/metrics.sh"
# shellcheck source=scripts/lib/filter.sh
source "${_PORTFOLIO_SCRIPT_DIR}/filter.sh"

# ---------------------------------------------------------------------------
# fetch_portfolio_metrics
#   Iterates SONAR_PROJECT_KEYS, fetching + filtering each project, then merges
#   the per-project report objects into one portfolio report (printed to stdout).
#   Reuses fetch_all_metrics (per-project, via the SONAR_PROJECT_KEY global) and
#   apply_issue_filters (per-project display filtering). Returns 1 on failure.
# ---------------------------------------------------------------------------
fetch_portfolio_metrics() {
  # SONAR_PROJECT_KEYS is populated by the main script's CLI parsing.
  # shellcheck disable=SC2153
  if [[ "${#SONAR_PROJECT_KEYS[@]}" -lt 1 ]]; then
    log_error "No project keys provided for portfolio aggregation"
    return 1
  fi

  local -a _temps=()        # every temp file we create — cleaned up at the end
  local -a project_files=() # the per-project files fed into the merge
  local key proj_file filtered
  local rc=0

  for key in "${SONAR_PROJECT_KEYS[@]}"; do
    echo "" >&2
    log_info "═══ Project: ${key} ═══"
    SONAR_PROJECT_KEY="$key"

    if ! proj_file=$(create_temp_file); then
      log_error "Failed to create temp file for project: ${key}"
      rc=1
      break
    fi
    _temps+=("$proj_file")

    if ! fetch_all_metrics > "$proj_file"; then
      log_error "Failed to collect analysis data for project: ${key}"
      rc=1
      break
    fi

    # Apply display filters per project (no-op when no filter is configured).
    if ! filtered=$(apply_issue_filters "$proj_file"); then
      log_error "Failed to apply issue filters for project: ${key}"
      rc=1
      break
    fi
    [[ "$filtered" != "$proj_file" ]] && _temps+=("$filtered")
    project_files+=("$filtered")
  done

  if [[ "$rc" -ne 0 ]]; then
    rm -f "${_temps[@]+"${_temps[@]}"}"
    return 1
  fi

  local report_date sonar_cloud_bool="false"
  report_date=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  [[ "${SONAR_CLOUD:-false}" == "true" ]] && sonar_cloud_bool="true"

  local merge_rc=0
  jq -s \
    --arg reportDate "$report_date" \
    --arg sonarUrl "${SONAR_URL:-}" \
    --arg sonarCloud "$sonar_cloud_bool" \
    --arg organization "${SONAR_ORGANIZATION:-}" \
    --arg branch "${SONAR_BRANCH:-main}" \
    -f "${_PORTFOLIO_SCRIPT_DIR}/jq/portfolio-aggregate.jq" \
    "${project_files[@]}" || merge_rc=1

  rm -f "${_temps[@]+"${_temps[@]}"}"

  if [[ "$merge_rc" -ne 0 ]]; then
    log_error "Failed to aggregate portfolio data"
    return 1
  fi
}
