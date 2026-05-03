#!/usr/bin/env bash
# ==============================================================================
# report-json.sh — Generate JSON report
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_REPORT_JSON_SH_LOADED:-}" ]] && return 0
_REPORT_JSON_SH_LOADED=1

set -euo pipefail

_REPORT_JSON_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_REPORT_JSON_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# generate_json_report <report_data_json> <output_dir>
# ---------------------------------------------------------------------------
generate_json_report() {
  local report_data_file="$1"
  local output_dir="$2"

  local project_key
  project_key=$(jq -r '.metadata.projectKey' "$report_data_file")
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filename="${project_key}_${timestamp}.json"
  local filepath="${output_dir}/${filename}"

  mkdir -p "$output_dir"

  jq '.' "$report_data_file" > "$filepath"

  log_ok "JSON report → ${filepath}"
  echo "$filepath"
}
