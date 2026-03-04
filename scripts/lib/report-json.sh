#!/usr/bin/env bash
# ==============================================================================
# report-json.sh — Generate JSON report
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# generate_json_report <report_data_json> <output_dir>
# ---------------------------------------------------------------------------
generate_json_report() {
  local report_data="$1"
  local output_dir="$2"

  local project_key
  project_key=$(echo "$report_data" | jq -r '.metadata.projectKey')
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filename="${project_key}_${timestamp}.json"
  local filepath="${output_dir}/${filename}"

  mkdir -p "$output_dir"

  echo "$report_data" | jq '.' > "$filepath"

  log_ok "JSON report → ${filepath}"
  echo "$filepath"
}
