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
  qg_conditions_table=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-qg-conditions.jq")

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
  hotspots_table=$(echo "$report_data" | jq -r --arg mode "$rule_mode" -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-hotspots-table.jq")

  # Issues details table
  local issues_table
  issues_table=$(echo "$report_data" | jq -r --arg mode "$rule_mode" -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-issues-table.jq")

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
  quality_profiles_section=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-quality-profiles.jq")

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
      " — showing " + (($f.issuesShown // 0) | tostring) + " of " + (($f.issuesBeforeFilter // 0) | tostring) +
      " issues. Summary counts reflect the full project.</div>"
    else "" end')

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
  tmpfile=$(create_temp_file)
  # Guard prevents the trap from failing when it fires in an outer caller's
  # scope (where $tmpfile is unset) due to bash RETURN traps being shell-wide.
  trap '[[ -n "${tmpfile:-}" ]] && rm -f "$tmpfile" "${tmpfile}.tmp" "${tmpfile}.rep"' RETURN

  echo "$html" > "$tmpfile"

  # Replace conditions table
  printf '%s' "$qg_conditions_table" > "${tmpfile}.rep"
  awk -v ph="{{QG_CONDITIONS_TABLE}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  # Replace hotspots details table
  printf '%s' "$hotspots_table" > "${tmpfile}.rep"
  awk -v ph="{{HOTSPOTS_TABLE}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  # Replace issues details table
  printf '%s' "$issues_table" > "${tmpfile}.rep"
  awk -v ph="{{ISSUES_TABLE}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  # Replace quality gate name header row (empty when the feature is disabled)
  printf '%s' "$qg_name_row" > "${tmpfile}.rep"
  awk -v ph="{{QUALITY_GATE_NAME_ROW}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  # Replace quality profiles section (empty when the feature is disabled)
  printf '%s' "$quality_profiles_section" > "${tmpfile}.rep"
  awk -v ph="{{QUALITY_PROFILES_SECTION}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  # Replace filters-applied note (empty when no display filters are active)
  printf '%s' "$filters_note" > "${tmpfile}.rep"
  awk -v ph="{{FILTERS_NOTE}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"
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
  worst_table=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-portfolio-worst.jq")
  comparison_table=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-portfolio-comparison.jq")
  project_sections=$(echo "$report_data" | jq -r -f "${_REPORT_HTML_SCRIPT_DIR}/jq/html-portfolio-projects.jq")

  # --- Substitute scalar placeholders ---
  local html
  html=$(cat "$tpl_file")
  html=$(echo "$html" | sed \
    -e "s|{{PROJECT_COUNT}}|${project_count}|g" \
    -e "s|{{REPORT_DATE}}|${report_date}|g" \
    -e "s|{{SONAR_URL}}|${sonar_url}|g" \
    -e "s|{{GATES_PASSED}}|${gates_passed}|g" \
    -e "s|{{GATES_FAILED}}|${gates_failed}|g" \
    -e "s|{{GATES_OTHER}}|${gates_other}|g" \
    -e "s|{{TOTAL_BUGS}}|${total_bugs}|g" \
    -e "s|{{TOTAL_VULNS}}|${total_vulns}|g" \
    -e "s|{{TOTAL_SMELLS}}|${total_smells}|g" \
    -e "s|{{TOTAL_ISSUES}}|${total_issues}|g" \
    -e "s|{{TOTAL_HOTSPOTS}}|${total_hotspots}|g" \
    -e "s|{{HOTSPOTS_TO_REVIEW}}|${hotspots_to_review}|g" \
    -e "s|{{TOTAL_LOC}}|${total_loc}|g" \
    -e "s|{{TECH_DEBT}}|${tech_debt}|g" \
    -e "s|{{AVG_COVERAGE}}|${avg_coverage}|g" \
    -e "s|{{AVG_DUPLICATION}}|${avg_duplication}|g" \
    -e "s|{{SEV_BLOCKER_CRITICAL}}|${sev_blocker_critical}|g" \
  )

  local tmpfile
  tmpfile=$(create_temp_file)
  # shellcheck disable=SC2064
  trap '[[ -n "${tmpfile:-}" ]] && rm -f "$tmpfile" "${tmpfile}.tmp" "${tmpfile}.rep"' RETURN
  echo "$html" > "$tmpfile"

  # Organization row contains '|' and '&' — replace via awk (not sed).
  printf '%s' "$organization_row" > "${tmpfile}.rep"
  awk -v ph="{{ORGANIZATION_ROW}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  printf '%s' "$worst_table" > "${tmpfile}.rep"
  awk -v ph="{{WORST_OFFENDERS_TABLE}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  printf '%s' "$comparison_table" > "${tmpfile}.rep"
  awk -v ph="{{COMPARISON_TABLE}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"

  printf '%s' "$project_sections" > "${tmpfile}.rep"
  awk -v ph="{{PER_PROJECT_SECTIONS}}" -v cf="${tmpfile}.rep" \
    -f "${_REPORT_HTML_SCRIPT_DIR}/awk/replace-placeholder.awk" \
    "$tmpfile" > "${tmpfile}.tmp" && mv "${tmpfile}.tmp" "$tmpfile"
  rm -f "${tmpfile}.rep"

  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filepath="${output_dir}/portfolio_${timestamp}.html"
  mkdir -p "$output_dir"
  mv "$tmpfile" "$filepath"

  log_ok "HTML report → ${filepath}"
  echo "$filepath"
}
