#!/usr/bin/env bash
# ==============================================================================
# report-csv.sh — Generate CSV reports (summary, issues, hotspots)
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_REPORT_CSV_SH_LOADED:-}" ]] && return 0
_REPORT_CSV_SH_LOADED=1

set -euo pipefail

_REPORT_CSV_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/report-spreadsheet.sh
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

  # Portfolio (multi-project) reports emit a different set of CSV files.
  if [[ "$(jq -r '.metadata.reportType // "single"' "$report_data_file")" == "portfolio" ]]; then
    generate_csv_portfolio_report "$report_data_file" "$output_dir"
    return $?
  fi

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

# ---------------------------------------------------------------------------
# generate_csv_portfolio_report <report_data_file> <output_dir>
#   Generates five portfolio CSV files: summary, comparison, worst offenders,
#   issues (Project column), hotspots (Project column). One filepath per line.
# ---------------------------------------------------------------------------
generate_csv_portfolio_report() {
  local report_data_file="$1"
  local output_dir="$2"

  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  mkdir -p "$output_dir"

  local prefix="${output_dir}/portfolio_${timestamp}"
  local summary_file="${prefix}_summary.csv"
  local comparison_file="${prefix}_comparison.csv"
  local worst_file="${prefix}_worst_offenders.csv"
  local issues_file="${prefix}_issues.csv"
  local hotspots_file="${prefix}_hotspots.csv"

  write_portfolio_summary_csv    "$report_data_file" "$summary_file"    || { log_error "Failed to generate portfolio CSV summary"; return 1; }
  log_ok "CSV summary      → ${summary_file}"
  write_portfolio_comparison_csv "$report_data_file" "$comparison_file" || { log_error "Failed to generate portfolio CSV comparison"; return 1; }
  log_ok "CSV comparison   → ${comparison_file}"
  write_portfolio_worst_csv      "$report_data_file" "$worst_file"      || { log_error "Failed to generate portfolio CSV worst offenders"; return 1; }
  log_ok "CSV worst        → ${worst_file}"
  write_portfolio_issues_csv     "$report_data_file" "$issues_file"     || { log_error "Failed to generate portfolio CSV issues"; return 1; }
  log_ok "CSV issues       → ${issues_file}"
  write_portfolio_hotspots_csv   "$report_data_file" "$hotspots_file"   || { log_error "Failed to generate portfolio CSV hotspots"; return 1; }
  log_ok "CSV hotspots     → ${hotspots_file}"

  echo "$summary_file"
  echo "$comparison_file"
  echo "$worst_file"
  echo "$issues_file"
  echo "$hotspots_file"
}
