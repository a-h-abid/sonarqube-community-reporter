#!/usr/bin/env bash
# ==============================================================================
# notify.sh — Send webhook notification after report generation
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_NOTIFY_SH_LOADED:-}" ]] && return 0
_NOTIFY_SH_LOADED=1

set -euo pipefail

_NOTIFY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_NOTIFY_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# send_webhook_notification <webhook_url> <report_data_file> [<file>...]
#   Posts a JSON summary payload to the given webhook URL.
#   Compatible with Slack Incoming Webhooks, Teams Incoming Webhooks, and any
#   generic HTTP endpoint that accepts a JSON POST body.
#
#   Arguments:
#     webhook_url       — HTTPS URL of the incoming webhook
#     report_data_file  — Path to the report data JSON file
#     [file...]         — Optional list of generated report file paths to name
#                         in the notification body
# ---------------------------------------------------------------------------
send_webhook_notification() {
  local webhook_url="$1"
  local report_data_file="$2"
  shift 2
  local generated_files=("$@")

  log_info "Sending webhook notification ..."

  local project_name project_key branch sonar_url qg_status report_date
  local bugs vulns smells total_issues hotspots_total
  project_name=$(jq -r '.metadata.projectName // .metadata.projectKey' "$report_data_file")
  project_key=$(jq -r '.metadata.projectKey' "$report_data_file")
  branch=$(jq -r '.metadata.branch // "main"' "$report_data_file")
  sonar_url=$(jq -r '.metadata.sonarUrl' "$report_data_file")
  qg_status=$(jq -r '.qualityGate.status // "UNKNOWN"' "$report_data_file")
  report_date=$(jq -r '.metadata.reportDate' "$report_data_file")
  bugs=$(jq -r '.measures.bugs // "0"' "$report_data_file")
  vulns=$(jq -r '.measures.vulnerabilities // "0"' "$report_data_file")
  smells=$(jq -r '.measures.code_smells // "0"' "$report_data_file")
  total_issues=$(jq -r '.issuesSummary.total // 0' "$report_data_file")
  hotspots_total=$(jq -r '.hotspotsSummary.total // 0' "$report_data_file")

  local qg_emoji="⚠️"
  [[ "$qg_status" == "OK" ]]    && qg_emoji="✅"
  [[ "$qg_status" == "ERROR" ]] && qg_emoji="❌"

  # Build a comma-separated list of generated file basenames
  local files_list=""
  local f
  for f in "${generated_files[@]}"; do
    files_list="${files_list}$(basename "$f"), "
  done
  files_list="${files_list%, }"

  # Build a generic JSON payload compatible with Slack Incoming Webhooks.
  # Teams webhooks also accept a simple {"text": "..."} payload.
  local payload
  payload=$(jq -n \
    --arg project_name   "$project_name" \
    --arg project_key    "$project_key" \
    --arg branch         "$branch" \
    --arg sonar_url      "$sonar_url" \
    --arg qg_emoji       "$qg_emoji" \
    --arg qg_status      "$qg_status" \
    --arg report_date    "$report_date" \
    --argjson bugs       "$bugs" \
    --argjson vulns      "$vulns" \
    --argjson smells     "$smells" \
    --argjson total      "$total_issues" \
    --argjson hotspots   "$hotspots_total" \
    --arg files          "$files_list" \
    '{
      text: (
        "*SonarQube Report — " + $project_name + "*\n" +
        "Project: `" + $project_key + "` | Branch: `" + $branch + "`\n" +
        $qg_emoji + " Quality Gate: *" + $qg_status + "*\n" +
        "Bugs: *" + ($bugs | tostring) + "*" +
        " | Vulnerabilities: *" + ($vulns | tostring) + "*" +
        " | Code Smells: *" + ($smells | tostring) + "*" +
        " | Total Issues: *" + ($total | tostring) + "*" +
        " | Hotspots: *" + ($hotspots | tostring) + "*\n" +
        "Report Date: " + $report_date + "\n" +
        "SonarQube: " + $sonar_url +
        if $files != "" then "\nGenerated: " + $files else "" end
      )
    }')

  local tmpfile
  tmpfile=$(mktemp)
  # Guard prevents the trap from failing when it fires in an outer caller's
  # scope (where $tmpfile is unset) due to bash RETURN traps being shell-wide.
  trap '[[ -n "${tmpfile:-}" ]] && rm -f "$tmpfile"' RETURN

  local http_code
  http_code=$(curl -s -o "$tmpfile" -w '%{http_code}' \
    -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$webhook_url") || {
    log_error "Failed to reach webhook URL: ${webhook_url}"
    return 1
  }

  if [[ "$http_code" -ge 400 ]]; then
    log_error "Webhook returned HTTP ${http_code}: $(cat "$tmpfile")"
    return 1
  fi

  log_ok "Webhook notification sent (HTTP ${http_code})"
}
