#!/usr/bin/env bash
# ==============================================================================
# report-spreadsheet.sh — Shared spreadsheet report generation helpers
# ==============================================================================
[[ -n "${_REPORT_SPREADSHEET_SH_LOADED:-}" ]] && return 0
_REPORT_SPREADSHEET_SH_LOADED=1

set -euo pipefail

_REPORT_SPREADSHEET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_REPORT_SPREADSHEET_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# write_summary_csv <report_data_file> <summary_csv>
#   Writes KPI-only summary rows for the "Overall Summary" sheet.
# ---------------------------------------------------------------------------
write_summary_csv() {
  local report_data_file="$1"
  local summary_csv="$2"

  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-summary.jq" \
    "$report_data_file" > "$summary_csv" || return 1
}

# ---------------------------------------------------------------------------
# write_issues_csv <report_data_file> <issues_csv>
#   Writes all fetched issue rows for the "Issues Details" sheet.
# ---------------------------------------------------------------------------
write_issues_csv() {
  local report_data_file="$1"
  local issues_csv="$2"

  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-issues.jq" \
    "$report_data_file" > "$issues_csv" || return 1
}

# ---------------------------------------------------------------------------
# write_hotspots_csv <report_data_file> <hotspots_csv>
#   Writes all fetched hotspot rows for the "Hotspots Details" sheet.
# ---------------------------------------------------------------------------
write_hotspots_csv() {
  local report_data_file="$1"
  local hotspots_csv="$2"

  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-hotspots.jq" \
    "$report_data_file" > "$hotspots_csv" || return 1
}

# ---------------------------------------------------------------------------
# generate_spreadsheet_report <report_data_file> <output_dir> <extension>
#   Creates spreadsheet with exactly three sheets:
#   - Overall Summary
#   - Issues Details
#   - Hotspots Details
# ---------------------------------------------------------------------------
generate_spreadsheet_report() {
  local report_data_file="$1"
  local output_dir="$2"
  local extension="$3"

  local ssconvert_bin="${SSCONVERT_BIN:-ssconvert}"

  if ! command -v "$ssconvert_bin" &>/dev/null; then
    log_warn "${ssconvert_bin} not found — skipping ${extension^^} generation"
    log_warn "Install: apt-get install -y gnumeric  OR  brew install gnumeric"
    return 0
  fi

  local project_key
  project_key=$(jq -r '.metadata.projectKey' "$report_data_file")
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filepath="${output_dir}/${project_key}_${timestamp}.${extension}"

  mkdir -p "$output_dir"

  local tmpdir
  tmpdir=$(mktemp -d)
  trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' RETURN

  local summary_csv="${tmpdir}/Overall Summary.csv"
  local issues_csv="${tmpdir}/Issues Details.csv"
  local hotspots_csv="${tmpdir}/Hotspots Details.csv"

  write_summary_csv "$report_data_file" "$summary_csv" || {
    log_error "Failed to prepare summary sheet data"
    return 1
  }

  write_issues_csv "$report_data_file" "$issues_csv" || {
    log_error "Failed to prepare issues sheet data"
    return 1
  }

  write_hotspots_csv "$report_data_file" "$hotspots_csv" || {
    log_error "Failed to prepare hotspots sheet data"
    return 1
  }

  "$ssconvert_bin" --merge-to="$filepath" "$summary_csv" "$issues_csv" "$hotspots_csv" >/dev/null 2>&1 || {
    log_error "${ssconvert_bin} failed to generate ${extension^^} report"
    return 1
  }

  log_ok "${extension^^} report → ${filepath}"
  echo "$filepath"
}
