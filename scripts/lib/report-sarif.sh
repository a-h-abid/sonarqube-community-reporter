#!/usr/bin/env bash
# ==============================================================================
# report-sarif.sh — Generate a SARIF 2.1.0 report
#
# Exports issues and TO_REVIEW security hotspots as a single SARIF 2.1.0 JSON
# document, suitable for upload to GitHub's Security tab (code scanning) or any
# other SARIF-aware tooling. Uses only jq — no extra dependencies.
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_REPORT_SARIF_SH_LOADED:-}" ]] && return 0
_REPORT_SARIF_SH_LOADED=1

set -euo pipefail

_REPORT_SARIF_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/api.sh
source "${_REPORT_SARIF_SCRIPT_DIR}/api.sh"

# Tool identity embedded in the SARIF tool.driver block.
_SARIF_TOOL_NAME="SonarQube Community Reporter"
_SARIF_TOOL_URI="https://github.com/a-h-abid/sonarqube-community-reporter"

# ---------------------------------------------------------------------------
# generate_sarif_report <report_data_file> <output_dir>
#   Writes one .sarif file and prints its path as the last line of stdout.
# ---------------------------------------------------------------------------
generate_sarif_report() {
  local report_data_file="$1"
  local output_dir="$2"

  local project_key
  project_key=$(jq -r '.metadata.projectKey // .metadata.reportType // "report"' "$report_data_file")
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filename="${project_key}_${timestamp}.sarif"
  local filepath="${output_dir}/${filename}"

  mkdir -p "$output_dir"

  # Warn about findings that cannot be anchored to a file (dropped from output).
  # In portfolio mode the findings live under .portfolio.projects[]; otherwise
  # they are top-level. Either way, count fileless issues/TO_REVIEW hotspots.
  local dropped
  dropped=$(jq '[ (.portfolio.projects[]? // .) ] | [ .[] | (.issues[]? | select((.component // "") == "")), (.hotspots[]? | select(.status == "TO_REVIEW" and (.component // "") == "")) ] | length' "$report_data_file" 2>/dev/null || echo 0)
  if [[ "${dropped:-0}" -gt 0 ]]; then
    log_warn "SARIF: skipped ${dropped} finding(s) with no file location"
  fi

  jq -f "${_REPORT_SARIF_SCRIPT_DIR}/jq/sarif.jq" \
    --arg toolName "$_SARIF_TOOL_NAME" \
    --arg toolVersion "" \
    --arg toolUri "$_SARIF_TOOL_URI" \
    "$report_data_file" > "$filepath" || {
    log_error "Failed to generate SARIF report"
    return 1
  }

  log_ok "SARIF report → ${filepath}"
  echo "$filepath"
}
