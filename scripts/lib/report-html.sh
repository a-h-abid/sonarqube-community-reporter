#!/usr/bin/env bash
# ==============================================================================
# report-html.sh — Generate styled HTML report from template
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_REPORT_HTML_SH_LOADED:-}" ]] && return 0
_REPORT_HTML_SH_LOADED=1

set -euo pipefail

_REPORT_HTML_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/api.sh
source "${_REPORT_HTML_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# Template rendering helpers
#
# Every value that reaches the HTML report comes from the SonarQube server or
# from a saved report-data file, so it is untrusted. Placeholders are filled by
# awk/render-template.awk, which HTML-escapes scalar values and substitutes
# literally — values never pass through a sed/regex program.
# ---------------------------------------------------------------------------

# _html_link_url <url> — the URL when it is absolute http(s), otherwise "#"
# (keeps javascript:/data: URLs out of the report's links).
_html_link_url() {
  local url="${1:-}"
  if [[ "$url" =~ ^[Hh][Tt][Tt][Pp][Ss]?:// ]]; then
    echo "$url"
  else
    echo "#"
  fi
}

# _html_write_scalars <map_file> <KEY> <value> [<KEY> <value> ...]
#   Writes "KEY<TAB>value" lines (raw values; escaped at render time).
_html_write_scalars() {
  local map_file="$1"
  shift

  : > "$map_file" || return 1
  local value
  while [[ $# -ge 2 ]]; do
    value="${2//[$'\n\r\t']/ }"
    printf '%s\t%s\n' "$1" "$value" >> "$map_file" || return 1
    shift 2
  done
}

# _html_write_block <render_dir> <KEY> <html>
#   Registers a ready-made (already escaped) HTML block for a placeholder.
_html_write_block() {
  local render_dir="$1"
  local key="$2"
  local content="$3"

  printf '%s' "$content" > "${render_dir}/${key}.block" || return 1
  printf '%s\t%s\n' "$key" "${render_dir}/${key}.block" >> "${render_dir}/blocks" || return 1
}

# _html_render_template <tpl_file> <render_dir> <out_file>
#   Fills the template from <render_dir>/scalars and <render_dir>/blocks.
_html_render_template() {
  local tpl_file="$1"
  local render_dir="$2"
  local out_file="$3"

  awk -v sf="${render_dir}/scalars" -v bf="${render_dir}/blocks" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/render-template.awk" \
    "$tpl_file" > "$out_file" || return 1

  if [[ ! -s "$out_file" ]]; then
    log_error "Rendered HTML report is empty (template: ${tpl_file})"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# generate_html_report <report_data_json> <output_dir>
# ---------------------------------------------------------------------------
generate_html_report() {
  local report_data_file="$1"
  local output_dir="$2"

  # Portfolio (multi-project) reports use a dedicated roll-up template.
  if [[ "$(jq -r '.metadata.reportType // "single"' "$report_data_file")" == "portfolio" ]]; then
    generate_html_portfolio_report "$report_data_file" "$output_dir"
    return $?
  fi

  # Read report data from file — avoids passing large JSON as arguments
  local report_data
  report_data=$(< "$report_data_file")

  if ! jq -e 'type == "object"' "$report_data_file" >/dev/null 2>&1; then
    log_error "Report data is not a JSON object: ${report_data_file}"
    return 1
  fi

  # Locate the template — a user-supplied HTML_TEMPLATE overrides the bundled
  # default. Validation of the override (existence/readability) happens up front
  # in validate_enrichment_flags; the guard below also protects direct callers.
  local tpl_file
  if [[ -n "${HTML_TEMPLATE:-}" ]]; then
    tpl_file="$HTML_TEMPLATE"
  else
    local tpl_dir
    tpl_dir="$(cd "${_REPORT_HTML_SCRIPT_DIR}/../../templates" 2>/dev/null && pwd)" || tpl_dir="/opt/sonar-report/templates"
    tpl_file="${tpl_dir}/report.html.tpl"
  fi

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
  qg_conditions_table=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-qg-conditions.jq") || return 1

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

  # Determine rule-description display mode: metadata takes precedence over env.
  local rule_mode
  rule_mode=$(echo "$report_data" | jq -r --arg envMode "${INCLUDE_RULE_DESCRIPTIONS:-}" -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-rule-mode.jq")

  # Hotspots details table
  local hotspots_table
  hotspots_table=$(echo "$report_data" | jq -r -L "${_REPORT_HTML_SCRIPT_DIR}/jq" --arg mode "$rule_mode" -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-hotspots-table.jq") || return 1

  # Issues details table
  local issues_table
  issues_table=$(echo "$report_data" | jq -r -L "${_REPORT_HTML_SCRIPT_DIR}/jq" --arg mode "$rule_mode" -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-issues-table.jq") || return 1

  # Quality gate name (audit metadata) — header row, only when the key is
  # present. Empty value renders as "N/A"; key absent ⇒ no row at all.
  local qg_name_row=""
  if echo "$report_data" | jq -e '.metadata | has("qualityGateName")' >/dev/null 2>&1; then
    local qg_name
    qg_name=$(echo "$report_data" | jq -r '
      (.metadata.qualityGateName // "")
      | (if . == "" then "N/A" else . end)
      | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")')
    qg_name_row="<div class=\"header-info qg-name\">Quality Gate: <strong>${qg_name}</strong></div>"
  fi

  # Quality profiles (audit metadata) — section HTML, or "" when key absent.
  local quality_profiles_section
  quality_profiles_section=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-quality-profiles.jq") || return 1

  # Trend section — rendered only when a baseline comparison was computed.
  local trend_section
  trend_section=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-trend.jq") || return 1

  # Filters-applied note — rendered only when display filters are active.
  local filters_note
  filters_note=$(echo "$report_data" | jq -r '
    def esc: gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
    if (.metadata.filtersApplied // null) != null then
      .metadata.filtersApplied as $f |
      "<div class=\"filters-note\">⚠ Filters applied: " +
      (([ (if ($f.severityThreshold // "") != "" then "severity ≥ " + $f.severityThreshold else empty end),
          (if (($f.issueTypes // []) | length) > 0 then "types " + ($f.issueTypes | join(", ")) else empty end),
          (if ($f.maxIssues // null) != null then "max " + ($f.maxIssues | tostring) else empty end) ]
        | join("; ")) | esc) +
      " — showing " + (($f.issuesShown // 0) | tostring | esc) + " of " + (($f.issuesBeforeFilter // 0) | tostring | esc) +
      " issues. Summary counts reflect the full project.</div>"
    else "" end') || return 1

  # --- Build HTML by filling the template placeholders ---
  # html_render_dir holds the placeholder maps and the rendered page. The name
  # is deliberately specific: bash RETURN traps are shell-wide, so the guard
  # below must not match an unrelated variable in an outer caller's scope.
  local html_render_dir
  html_render_dir=$(create_temp_dir) || return 1
  trap '[[ -n "${html_render_dir:-}" ]] && rm -rf "$html_render_dir"' RETURN

  _html_write_scalars "${html_render_dir}/scalars" \
    PROJECT_NAME "$project_name" \
    PROJECT_KEY "$project_key" \
    BRANCH "$branch" \
    REPORT_DATE "$report_date" \
    LAST_ANALYSIS_DATE "$last_analysis_date" \
    SONAR_URL "$(_html_link_url "$sonar_url")" \
    ANALYSIS_ID "$analysis_id" \
    QG_STATUS "$qg_status" \
    QG_CLASS "$qg_class" \
    BUGS "$bugs" \
    VULNS "$vulns" \
    SMELLS "$smells" \
    COVERAGE "$coverage" \
    DUPLICATION "$duplication" \
    LOC "$loc" \
    TECH_DEBT "$tech_debt" \
    DEBT_RATIO "$debt_ratio" \
    REL_RATING "$rel_rating" \
    SEC_RATING "$sec_rating" \
    MAINT_RATING "$maint_rating" \
    HOTSPOTS_REVIEWED_PCT "$hotspots_reviewed_pct" \
    SEC_REVIEW_RATING "$sec_review_rating" \
    NEW_BUGS "$new_bugs" \
    NEW_VULNS "$new_vulns" \
    NEW_SMELLS "$new_smells" \
    NEW_COVERAGE "$new_coverage" \
    NEW_DUPLICATION "$new_duplication" \
    TOTAL_ISSUES "$total_issues" \
    ISSUE_BUGS "$issue_bugs" \
    ISSUE_VULNS "$issue_vulns" \
    ISSUE_SMELLS "$issue_smells" \
    SEV_BLOCKER "$sev_blocker" \
    SEV_CRITICAL "$sev_critical" \
    SEV_MAJOR "$sev_major" \
    SEV_MINOR "$sev_minor" \
    SEV_INFO "$sev_info" \
    HOTSPOT_TOTAL "$hotspot_total" \
    HOTSPOT_TO_REVIEW "$hotspot_to_review" \
    HOTSPOT_REVIEWED "$hotspot_reviewed" || return 1

  # Multiline HTML blocks (already escaped by the jq programs that build them).
  # The last three are empty when their feature is disabled.
  _html_write_block "$html_render_dir" QG_CONDITIONS_TABLE "$qg_conditions_table" || return 1
  _html_write_block "$html_render_dir" HOTSPOTS_TABLE "$hotspots_table" || return 1
  _html_write_block "$html_render_dir" ISSUES_TABLE "$issues_table" || return 1
  _html_write_block "$html_render_dir" QUALITY_GATE_NAME_ROW "$qg_name_row" || return 1
  _html_write_block "$html_render_dir" QUALITY_PROFILES_SECTION "$quality_profiles_section" || return 1
  _html_write_block "$html_render_dir" TREND_SECTION "$trend_section" || return 1
  _html_write_block "$html_render_dir" FILTERS_NOTE "$filters_note" || return 1

  _html_render_template "$tpl_file" "$html_render_dir" "${html_render_dir}/report.html" || return 1

  # Write final output
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filename="${project_key}_${timestamp}.html"
  local filepath="${output_dir}/${filename}"
  mkdir -p "$output_dir" || return 1

  mv "${html_render_dir}/report.html" "$filepath" || return 1

  log_ok "HTML report → ${filepath}"
  echo "$filepath"
}

# ---------------------------------------------------------------------------
# generate_html_portfolio_report <report_data_json> <output_dir>
#   Renders a portfolio roll-up (org totals, gate counts, worst offenders,
#   per-project comparison, and per-project drill-down) as a styled HTML page.
#   A user-supplied HTML_TEMPLATE overrides the bundled portfolio template.
# ---------------------------------------------------------------------------
generate_html_portfolio_report() {
  local report_data_file="$1"
  local output_dir="$2"

  local report_data
  report_data=$(< "$report_data_file")

  if ! jq -e 'type == "object"' "$report_data_file" >/dev/null 2>&1; then
    log_error "Report data is not a JSON object: ${report_data_file}"
    return 1
  fi

  local tpl_file
  if [[ -n "${HTML_TEMPLATE:-}" ]]; then
    tpl_file="$HTML_TEMPLATE"
  else
    local tpl_dir
    tpl_dir="$(cd "${_REPORT_HTML_SCRIPT_DIR}/../../templates" 2>/dev/null && pwd)" || tpl_dir="/opt/sonar-report/templates"
    tpl_file="${tpl_dir}/portfolio.html.tpl"
  fi

  if [[ ! -f "$tpl_file" ]]; then
    log_error "Portfolio HTML template not found: ${tpl_file}"
    return 1
  fi

  # --- Scalars ---
  local report_date sonar_url organization project_count
  report_date=$(echo "$report_data" | jq -r '.metadata.reportDate // "N/A"')
  sonar_url=$(echo "$report_data" | jq -r '.metadata.sonarUrl // ""')
  organization=$(echo "$report_data" | jq -r '.metadata.organization // ""')
  project_count=$(echo "$report_data" | jq -r '.metadata.projectCount // 0')

  local gates_passed gates_failed gates_other
  gates_passed=$(echo "$report_data" | jq -r '.portfolio.totals.gatesPassed // 0')
  gates_failed=$(echo "$report_data" | jq -r '.portfolio.totals.gatesFailed // 0')
  gates_other=$(echo "$report_data" | jq -r '.portfolio.totals.gatesOther // 0')

  local total_bugs total_vulns total_smells total_issues total_hotspots hotspots_to_review total_loc
  total_bugs=$(echo "$report_data" | jq -r '.portfolio.totals.bugs // 0')
  total_vulns=$(echo "$report_data" | jq -r '.portfolio.totals.vulnerabilities // 0')
  total_smells=$(echo "$report_data" | jq -r '.portfolio.totals.code_smells // 0')
  total_issues=$(echo "$report_data" | jq -r '.portfolio.totals.issues.total // 0')
  total_hotspots=$(echo "$report_data" | jq -r '.portfolio.totals.hotspots.total // 0')
  hotspots_to_review=$(echo "$report_data" | jq -r '.portfolio.totals.hotspots.toReview // 0')
  total_loc=$(echo "$report_data" | jq -r '.portfolio.totals.ncloc // 0')

  local sev_blocker_critical
  sev_blocker_critical=$(echo "$report_data" | jq -r '(.portfolio.totals.issues.bySeverity.BLOCKER // 0) + (.portfolio.totals.issues.bySeverity.CRITICAL // 0)')

  local tech_debt avg_coverage avg_duplication
  tech_debt=$(format_duration "$(echo "$report_data" | jq -r '.portfolio.totals.sqale_index // 0')")
  avg_coverage=$(echo "$report_data" | jq -r 'if .portfolio.aggregates.coverage == null then "N/A" else ((.portfolio.aggregates.coverage | tostring) + "%") end')
  avg_duplication=$(echo "$report_data" | jq -r 'if .portfolio.aggregates.duplicated_lines_density == null then "N/A" else ((.portfolio.aggregates.duplicated_lines_density | tostring) + "%") end')

  # Organization row (only when set)
  local organization_row=""
  if [[ -n "$organization" ]]; then
    local org_esc
    org_esc=$(echo "$organization" | jq -rR 'gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")')
    organization_row="Organization: <strong>${org_esc}</strong> &nbsp;|&nbsp;"
  fi

  # --- Table blocks (multiline → file-based awk replacement) ---
  local worst_table comparison_table project_sections
  worst_table=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-portfolio-worst.jq") || return 1
  comparison_table=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-portfolio-comparison.jq") || return 1
  project_sections=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-portfolio-projects.jq") || return 1

  # --- Fill the template placeholders (see generate_html_report) ---
  local html_render_dir
  html_render_dir=$(create_temp_dir) || return 1
  trap '[[ -n "${html_render_dir:-}" ]] && rm -rf "$html_render_dir"' RETURN

  _html_write_scalars "${html_render_dir}/scalars" \
    PROJECT_COUNT "$project_count" \
    REPORT_DATE "$report_date" \
    SONAR_URL "$(_html_link_url "$sonar_url")" \
    GATES_PASSED "$gates_passed" \
    GATES_FAILED "$gates_failed" \
    GATES_OTHER "$gates_other" \
    TOTAL_BUGS "$total_bugs" \
    TOTAL_VULNS "$total_vulns" \
    TOTAL_SMELLS "$total_smells" \
    TOTAL_ISSUES "$total_issues" \
    TOTAL_HOTSPOTS "$total_hotspots" \
    HOTSPOTS_TO_REVIEW "$hotspots_to_review" \
    TOTAL_LOC "$total_loc" \
    TECH_DEBT "$tech_debt" \
    AVG_COVERAGE "$avg_coverage" \
    AVG_DUPLICATION "$avg_duplication" \
    SEV_BLOCKER_CRITICAL "$sev_blocker_critical" || return 1

  _html_write_block "$html_render_dir" ORGANIZATION_ROW "$organization_row" || return 1
  _html_write_block "$html_render_dir" WORST_OFFENDERS_TABLE "$worst_table" || return 1
  _html_write_block "$html_render_dir" COMPARISON_TABLE "$comparison_table" || return 1
  _html_write_block "$html_render_dir" PER_PROJECT_SECTIONS "$project_sections" || return 1

  _html_render_template "$tpl_file" "$html_render_dir" "${html_render_dir}/report.html" || return 1

  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filepath="${output_dir}/portfolio_${timestamp}.html"
  mkdir -p "$output_dir" || return 1
  mv "${html_render_dir}/report.html" "$filepath" || return 1

  log_ok "HTML report → ${filepath}"
  echo "$filepath"
}
