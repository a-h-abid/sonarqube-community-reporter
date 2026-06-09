#!/usr/bin/env bash
# ==============================================================================
# report-spreadsheet.sh — Shared spreadsheet report generation helpers
# ==============================================================================
[[ -n "${_REPORT_SPREADSHEET_SH_LOADED:-}" ]] && return 0
_REPORT_SPREADSHEET_SH_LOADED=1

set -euo pipefail

_REPORT_SPREADSHEET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/api.sh
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
# Portfolio spreadsheet sheet writers (one jq program each).
# ---------------------------------------------------------------------------
write_portfolio_summary_csv() {
  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-portfolio-summary.jq" "$1" > "$2" || return 1
}
write_portfolio_comparison_csv() {
  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-portfolio-comparison.jq" "$1" > "$2" || return 1
}
write_portfolio_worst_csv() {
  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-portfolio-worst.jq" "$1" > "$2" || return 1
}
write_portfolio_issues_csv() {
  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-portfolio-issues.jq" "$1" > "$2" || return 1
}
write_portfolio_hotspots_csv() {
  jq -r -f "${_REPORT_SPREADSHEET_SCRIPT_DIR}/jq/spreadsheet-portfolio-hotspots.jq" "$1" > "$2" || return 1
}

# ---------------------------------------------------------------------------
# generate_spreadsheet_report <report_data_file> <output_dir> <extension>
#   Creates a spreadsheet. Single-project reports get three sheets (Overall
#   Summary, Issues Details, Hotspots Details). Portfolio reports get five
#   (Portfolio Summary, Project Comparison, Worst Offenders, Issues Details,
#   Hotspots Details — the detail sheets carry a leading Project column).
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

  local report_type
  report_type=$(jq -r '.metadata.reportType // "single"' "$report_data_file")

  local project_key
  project_key=$(jq -r '.metadata.projectKey // .metadata.reportType // "report"' "$report_data_file")
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filepath="${output_dir}/${project_key}_${timestamp}.${extension}"

  mkdir -p "$output_dir"

  local tmpdir
  tmpdir=$(create_temp_dir)
  trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' RETURN

  local -a sheets=()

  if [[ "$report_type" == "portfolio" ]]; then
    local p_summary="${tmpdir}/Portfolio Summary.csv"
    local p_comparison="${tmpdir}/Project Comparison.csv"
    local p_worst="${tmpdir}/Worst Offenders.csv"
    local p_issues="${tmpdir}/Issues Details.csv"
    local p_hotspots="${tmpdir}/Hotspots Details.csv"

    write_portfolio_summary_csv    "$report_data_file" "$p_summary"    || { log_error "Failed to prepare portfolio summary sheet"; return 1; }
    write_portfolio_comparison_csv "$report_data_file" "$p_comparison" || { log_error "Failed to prepare comparison sheet"; return 1; }
    write_portfolio_worst_csv      "$report_data_file" "$p_worst"      || { log_error "Failed to prepare worst-offenders sheet"; return 1; }
    write_portfolio_issues_csv     "$report_data_file" "$p_issues"     || { log_error "Failed to prepare issues sheet"; return 1; }
    write_portfolio_hotspots_csv   "$report_data_file" "$p_hotspots"   || { log_error "Failed to prepare hotspots sheet"; return 1; }

    sheets=("$p_summary" "$p_comparison" "$p_worst" "$p_issues" "$p_hotspots")
  else
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

    sheets=("$summary_csv" "$issues_csv" "$hotspots_csv")
  fi

  "$ssconvert_bin" --merge-to="$filepath" "${sheets[@]}" >/dev/null 2>&1 || {
    log_error "${ssconvert_bin} failed to generate ${extension^^} report"
    return 1
  }

  log_ok "${extension^^} report → ${filepath}"
  echo "$filepath"
}
