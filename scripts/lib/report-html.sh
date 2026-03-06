#!/usr/bin/env bash
# ==============================================================================
# report-html.sh — Generate styled HTML report from template
# ==============================================================================
set -euo pipefail

_REPORT_HTML_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_REPORT_HTML_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# generate_html_report <report_data_json> <output_dir>
# ---------------------------------------------------------------------------
generate_html_report() {
  local report_data_file="$1"
  local output_dir="$2"

  # Read report data from file — avoids passing large JSON as arguments
  local report_data
  report_data=$(< "$report_data_file")

  # Locate the template
  local tpl_dir
  tpl_dir="$(cd "${_REPORT_HTML_SCRIPT_DIR}/../../templates" 2>/dev/null && pwd)" || tpl_dir="/opt/sonar-report/templates"
  local tpl_file="${tpl_dir}/report.html.tpl"

  if [[ ! -f "$tpl_file" ]]; then
    log_error "HTML template not found: ${tpl_file}"
    return 1
  fi

  # --- Extract all values from report data ---
  local project_key project_name branch report_date last_analysis_date sonar_url analysis_id
  project_key=$(echo "$report_data" | jq -r '.metadata.projectKey')
  project_name=$(echo "$report_data" | jq -r '.metadata.projectName // .metadata.projectKey')
  branch=$(echo "$report_data" | jq -r '.metadata.branch // "main"')
  report_date=$(echo "$report_data" | jq -r '.metadata.reportDate')
  last_analysis_date=$(echo "$report_data" | jq -r '.metadata.lastAnalysisDate // "N/A" | if . == "" then "N/A" else . end')
  sonar_url=$(echo "$report_data" | jq -r '.metadata.sonarUrl')
  analysis_id=$(echo "$report_data" | jq -r '.metadata.analysisId // "N/A"')

  # Quality gate
  local qg_status qg_class
  qg_status=$(echo "$report_data" | jq -r '.qualityGate.status // "UNKNOWN"')
  case "$qg_status" in
    OK)    qg_class="qg-pass" ;;
    ERROR) qg_class="qg-fail" ;;
    WARN)  qg_class="qg-warn" ;;
    *)     qg_class="qg-none" ;;
  esac

  # Quality gate conditions table
  local qg_conditions_table
  qg_conditions_table=$(echo "$report_data" | jq -r '
    if (.qualityGate.conditions | length) > 0 then
      "<table><tr><th>Metric</th><th>Status</th><th>Value</th><th>Threshold</th></tr>" +
      ([.qualityGate.conditions[]? |
        "<tr><td>" + .metric + "</td>" +
        "<td class=\"cond-" + (.status | ascii_downcase) + "\">" + .status + "</td>" +
        "<td>" + (.actualValue // "N/A") + "</td>" +
        "<td>" + (.errorThreshold // "N/A") + "</td></tr>"
      ] | join("")) +
      "</table>"
    else
      "<p><em>No conditions configured.</em></p>"
    end
  ')

  # Measures
  local bugs vulns smells coverage duplication loc tech_debt debt_ratio
  local rel_rating sec_rating maint_rating hotspots_reviewed_pct sec_review_rating
  bugs=$(echo "$report_data" | jq -r '.measures.bugs // "0"')
  vulns=$(echo "$report_data" | jq -r '.measures.vulnerabilities // "0"')
  smells=$(echo "$report_data" | jq -r '.measures.code_smells // "0"')
  coverage=$(echo "$report_data" | jq -r '.measures.coverage // "N/A"')
  duplication=$(echo "$report_data" | jq -r '.measures.duplicated_lines_density // "N/A"')
  loc=$(echo "$report_data" | jq -r '.measures.ncloc // "0"')
  tech_debt=$(format_duration "$(echo "$report_data" | jq -r '.measures.sqale_index // "0"')")
  debt_ratio=$(echo "$report_data" | jq -r '.measures.sqale_debt_ratio // "N/A"')
  rel_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.reliability_rating // "0"')")
  sec_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.security_rating // "0"')")
  maint_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.sqale_rating // "0"')")
  hotspots_reviewed_pct=$(echo "$report_data" | jq -r '.measures.security_hotspots_reviewed // "N/A"')
  sec_review_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.security_review_rating // "0"')")

  # New code
  local new_bugs new_vulns new_smells new_coverage new_duplication
  new_bugs=$(echo "$report_data" | jq -r '.measures.new_bugs // "N/A"')
  new_vulns=$(echo "$report_data" | jq -r '.measures.new_vulnerabilities // "N/A"')
  new_smells=$(echo "$report_data" | jq -r '.measures.new_code_smells // "N/A"')
  new_coverage=$(echo "$report_data" | jq -r '.measures.new_coverage // "N/A"')
  new_duplication=$(echo "$report_data" | jq -r '.measures.new_duplicated_lines_density // "N/A"')

  # Issues summary
  local total_issues issue_bugs issue_vulns issue_smells
  total_issues=$(echo "$report_data" | jq -r '.issuesSummary.total // 0')
  issue_bugs=$(echo "$report_data" | jq -r '.issuesSummary.byType.BUG // 0')
  issue_vulns=$(echo "$report_data" | jq -r '.issuesSummary.byType.VULNERABILITY // 0')
  issue_smells=$(echo "$report_data" | jq -r '.issuesSummary.byType.CODE_SMELL // 0')

  # Severity
  local sev_blocker sev_critical sev_major sev_minor sev_info
  sev_blocker=$(echo "$report_data" | jq -r '.issuesSummary.bySeverity.BLOCKER // 0')
  sev_critical=$(echo "$report_data" | jq -r '.issuesSummary.bySeverity.CRITICAL // 0')
  sev_major=$(echo "$report_data" | jq -r '.issuesSummary.bySeverity.MAJOR // 0')
  sev_minor=$(echo "$report_data" | jq -r '.issuesSummary.bySeverity.MINOR // 0')
  sev_info=$(echo "$report_data" | jq -r '.issuesSummary.bySeverity.INFO // 0')

  # Hotspots
  local hotspot_total hotspot_to_review hotspot_reviewed
  hotspot_total=$(echo "$report_data" | jq -r '.hotspotsSummary.total // 0')
  hotspot_to_review=$(echo "$report_data" | jq -r '.hotspotsSummary.toReview // 0')
  hotspot_reviewed=$(echo "$report_data" | jq -r '.hotspotsSummary.reviewed // 0')

  # Issues details table
  local issues_table
  issues_table=$(echo "$report_data" | jq -r '
    if (.issues | length) > 0 then
      "<div class=\"table-shell\"><table class=\"issues-table\"><tr><th>#</th><th>Severity</th><th>Type</th><th>Rule</th><th>Component</th><th>Line</th><th>Message</th><th>Effort</th></tr>" +
      ([.issues | to_entries[]? |
        "<tr><td>" + ((.key + 1) | tostring) + "</td>" +
        "<td><span class=\"sev sev-" + (.value.severity // "INFO") + "\">" + (.value.severity // "?") + "</span></td>" +
        "<td><span class=\"type-badge\">" + (.value.type // "?") + "</span></td>" +
        "<td>" + (.value.rule // "") + "</td>" +
        "<td>" + ((.value.component // "") | split(":") | last) + "</td>" +
        "<td>" + ((.value.line // "") | tostring) + "</td>" +
        "<td>" + ((.value.message // "") | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")) + "</td>" +
        "<td>" + (.value.effort // "N/A") + "</td></tr>"
      ] | join("")) +
      "</table></div>"
    else
      "<p><em>No open issues found.</em></p>"
    end
  ')

  # --- Build HTML by substituting placeholders ---
  local html
  html=$(cat "$tpl_file")

  # Use sed for each placeholder
  html=$(echo "$html" | sed \
    -e "s|{{PROJECT_NAME}}|${project_name}|g" \
    -e "s|{{PROJECT_KEY}}|${project_key}|g" \
    -e "s|{{BRANCH}}|${branch}|g" \
    -e "s|{{REPORT_DATE}}|${report_date}|g" \
    -e "s|{{LAST_ANALYSIS_DATE}}|${last_analysis_date}|g" \
    -e "s|{{SONAR_URL}}|${sonar_url}|g" \
    -e "s|{{ANALYSIS_ID}}|${analysis_id}|g" \
    -e "s|{{QG_STATUS}}|${qg_status}|g" \
    -e "s|{{QG_CLASS}}|${qg_class}|g" \
    -e "s|{{BUGS}}|${bugs}|g" \
    -e "s|{{VULNS}}|${vulns}|g" \
    -e "s|{{SMELLS}}|${smells}|g" \
    -e "s|{{COVERAGE}}|${coverage}|g" \
    -e "s|{{DUPLICATION}}|${duplication}|g" \
    -e "s|{{LOC}}|${loc}|g" \
    -e "s|{{TECH_DEBT}}|${tech_debt}|g" \
    -e "s|{{DEBT_RATIO}}|${debt_ratio}|g" \
    -e "s|{{REL_RATING}}|${rel_rating}|g" \
    -e "s|{{SEC_RATING}}|${sec_rating}|g" \
    -e "s|{{MAINT_RATING}}|${maint_rating}|g" \
    -e "s|{{HOTSPOTS_REVIEWED_PCT}}|${hotspots_reviewed_pct}|g" \
    -e "s|{{SEC_REVIEW_RATING}}|${sec_review_rating}|g" \
    -e "s|{{NEW_BUGS}}|${new_bugs}|g" \
    -e "s|{{NEW_VULNS}}|${new_vulns}|g" \
    -e "s|{{NEW_SMELLS}}|${new_smells}|g" \
    -e "s|{{NEW_COVERAGE}}|${new_coverage}|g" \
    -e "s|{{NEW_DUPLICATION}}|${new_duplication}|g" \
    -e "s|{{TOTAL_ISSUES}}|${total_issues}|g" \
    -e "s|{{ISSUE_BUGS}}|${issue_bugs}|g" \
    -e "s|{{ISSUE_VULNS}}|${issue_vulns}|g" \
    -e "s|{{ISSUE_SMELLS}}|${issue_smells}|g" \
    -e "s|{{SEV_BLOCKER}}|${sev_blocker}|g" \
    -e "s|{{SEV_CRITICAL}}|${sev_critical}|g" \
    -e "s|{{SEV_MAJOR}}|${sev_major}|g" \
    -e "s|{{SEV_MINOR}}|${sev_minor}|g" \
    -e "s|{{SEV_INFO}}|${sev_info}|g" \
    -e "s|{{HOTSPOT_TOTAL}}|${hotspot_total}|g" \
    -e "s|{{HOTSPOT_TO_REVIEW}}|${hotspot_to_review}|g" \
    -e "s|{{HOTSPOT_REVIEWED}}|${hotspot_reviewed}|g" \
  )

  # Multiline / complex HTML replacements — use file-based awk to avoid
  # sed delimiter issues (|, &) and awk -v escape interpretation (\n, \t).
  local tmpfile
  tmpfile=$(mktemp)
  # Guard prevents the trap from failing when it fires in an outer caller's
  # scope (where $tmpfile is unset) due to bash RETURN traps being shell-wide.
  trap '[[ -n "${tmpfile:-}" ]] && rm -f "$tmpfile" "${tmpfile}.tmp" "${tmpfile}.rep"' RETURN

  echo "$html" > "$tmpfile"

  # Replace conditions table
  printf '%s' "$qg_conditions_table" > "${tmpfile}.rep"
  awk -v ph="{{QG_CONDITIONS_TABLE}}" -v cf="${tmpfile}.rep" '
    index($0, ph) {
      n = index($0, ph)
      prefix = substr($0, 1, n - 1)
      suffix = substr($0, n + length(ph))
      printf "%s", prefix
      while ((getline line < cf) > 0) printf "%s", line
      close(cf)
      printf "%s\n", suffix
      next
    }
    { print }
  ' "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  # Replace issues details table
  printf '%s' "$issues_table" > "${tmpfile}.rep"
  awk -v ph="{{ISSUES_TABLE}}" -v cf="${tmpfile}.rep" '
    index($0, ph) {
      n = index($0, ph)
      prefix = substr($0, 1, n - 1)
      suffix = substr($0, n + length(ph))
      printf "%s", prefix
      while ((getline line < cf) > 0) printf "%s", line
      close(cf)
      printf "%s\n", suffix
      next
    }
    { print }
  ' "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"
  rm -f "${tmpfile}.rep"

  # Write final output
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filename="${project_key}_${timestamp}.html"
  local filepath="${output_dir}/${filename}"
  mkdir -p "$output_dir"

  mv "$tmpfile" "$filepath"

  log_ok "HTML report → ${filepath}"
  echo "$filepath"
}
