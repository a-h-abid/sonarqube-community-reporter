#!/usr/bin/env bash
# ==============================================================================
# report-ods.sh — Generate ODS report
# ==============================================================================
[[ -n "${_REPORT_ODS_SH_LOADED:-}" ]] && return 0
_REPORT_ODS_SH_LOADED=1

set -euo pipefail

_REPORT_ODS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=report-spreadsheet.sh
source "${_REPORT_ODS_SCRIPT_DIR}/report-spreadsheet.sh"

# ---------------------------------------------------------------------------
# generate_ods_report <report_data_file> <output_dir>
# ---------------------------------------------------------------------------
generate_ods_report() {
  local report_data_file="$1"
  local output_dir="$2"

  generate_spreadsheet_report "$report_data_file" "$output_dir" "ods"
}
