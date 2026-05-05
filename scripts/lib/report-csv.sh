#!/usr/bin/env bash
# ==============================================================================
# report-csv.sh — Generate CSV reports (summary, issues, hotspots)
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_REPORT_CSV_SH_LOADED:-}" ]] && return 0
_REPORT_CSV_SH_LOADED=1

set -euo pipefail

_REPORT_CSV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=report-spreadsheet.sh
source "${_REPORT_CSV_SCRIPT_DIR}/report-spreadsheet.sh"

# ---------------------------------------------------------------------------
# generate_csv_report <report_data_file> <output_dir>
#   Generates three CSV files: summary, issues, and hotspots.
#   Prints one filepath per line for each generated file.
#   No extra dependencies — uses only jq (already required by the tool).
# ---------------------------------------------------------------------------
generate_csv_report() {
  local report_data_file="$1"
  local output_dir="$2"

  local project_key
  project_key=$(jq -r '.metadata.projectKey' "$report_data_file")
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')

  mkdir -p "$output_dir"

  local summary_file="${output_dir}/${project_key}_${timestamp}_summary.csv"
  local issues_file="${output_dir}/${project_key}_${timestamp}_issues.csv"
  local hotspots_file="${output_dir}/${project_key}_${timestamp}_hotspots.csv"

  write_summary_csv "$report_data_file" "$summary_file" || {
    log_error "Failed to generate CSV summary"
    return 1
  }
  log_ok "CSV summary  → ${summary_file}"

  write_issues_csv "$report_data_file" "$issues_file" || {
    log_error "Failed to generate CSV issues"
    return 1
  }
  log_ok "CSV issues   → ${issues_file}"

  write_hotspots_csv "$report_data_file" "$hotspots_file" || {
    log_error "Failed to generate CSV hotspots"
    return 1
  }
  log_ok "CSV hotspots → ${hotspots_file}"

  echo "$summary_file"
  echo "$issues_file"
  echo "$hotspots_file"
}
