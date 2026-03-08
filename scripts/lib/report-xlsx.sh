#!/usr/bin/env bash
# ==============================================================================
# report-xlsx.sh — Generate XLSX report
# ==============================================================================
[[ -n "${_REPORT_XLSX_SH_LOADED:-}" ]] && return 0
_REPORT_XLSX_SH_LOADED=1

set -euo pipefail

_REPORT_XLSX_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=report-spreadsheet.sh
source "${_REPORT_XLSX_SCRIPT_DIR}/report-spreadsheet.sh"

# ---------------------------------------------------------------------------
# generate_xlsx_report <report_data_file> <output_dir>
# ---------------------------------------------------------------------------
generate_xlsx_report() {
  local report_data_file="$1"
  local output_dir="$2"

  generate_spreadsheet_report "$report_data_file" "$output_dir" "xlsx"
}
