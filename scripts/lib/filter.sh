#!/usr/bin/env bash
# ==============================================================================
# filter.sh — Post-fetch filtering of the report's issue list.
#
# Limits which issues are SHOWN in every report format without changing what is
# fetched from SonarQube. Operates on the shared report data JSON after metrics
# collection, so all generators (JSON, MD, HTML, PDF, CSV, XLSX, ODS, SARIF)
# inherit an identical, smaller issue list. Hotspots and summary counts are left
# untouched (see jq/filter-issues.jq).
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_FILTER_SH_LOADED:-}" ]] && return 0
_FILTER_SH_LOADED=1

set -euo pipefail

_FILTER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/api.sh
source "${_FILTER_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# apply_issue_filters <report_data_file>
#   Applies SEVERITY_THRESHOLD / ISSUE_TYPES / MAX_ISSUES to the .issues array
#   of the report data. Writes the filtered data to a new temp file and echoes
#   its path. When no filter is configured, echoes the input path unchanged
#   (no copy, no work). Returns 1 on failure.
# ---------------------------------------------------------------------------
apply_issue_filters() {
  local input_file="$1"

  # Fast path: nothing to do when no filter is active.
  if [[ -z "${SEVERITY_THRESHOLD:-}" ]] && [[ -z "${ISSUE_TYPES:-}" ]] \
     && [[ -z "${MAX_ISSUES:-}" ]]; then
    echo "$input_file"
    return 0
  fi

  local out_file
  out_file=$(create_temp_file) || return 1

  if ! jq \
      --arg severityThreshold "${SEVERITY_THRESHOLD:-}" \
      --arg issueTypes "${ISSUE_TYPES:-}" \
      --arg maxIssues "${MAX_ISSUES:-}" \
      -f "${_FILTER_SCRIPT_DIR}/jq/filter-issues.jq" \
      "$input_file" > "$out_file"; then
    log_error "Failed to apply issue filters"
    rm -f "$out_file"
    return 1
  fi

  echo "$out_file"
}
