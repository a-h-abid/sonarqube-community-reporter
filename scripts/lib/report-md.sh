#!/usr/bin/env bash
# ==============================================================================
# report-md.sh — Generate Markdown report
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_REPORT_MD_SH_LOADED:-}" ]] && return 0
_REPORT_MD_SH_LOADED=1

set -euo pipefail

_REPORT_MD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_REPORT_MD_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# generate_md_report <report_data_json> <output_dir>
# ---------------------------------------------------------------------------
generate_md_report() {
  local report_data_file="$1"
  local output_dir="$2"

  # Read report data from file — avoids passing large JSON as arguments
  local report_data
  report_data=$(< "$report_data_file")

  # Extract metadata
  local project_key project_name branch report_date last_analysis_date sonar_url analysis_id
  project_key=$(echo "$report_data" | jq -r '.metadata.projectKey')
  project_name=$(echo "$report_data" | jq -r '.metadata.projectName // .metadata.projectKey')
  branch=$(echo "$report_data" | jq -r '.metadata.branch // "main"')
  report_date=$(echo "$report_data" | jq -r '.metadata.reportDate')
  last_analysis_date=$(echo "$report_data" | jq -r '.metadata.lastAnalysisDate // "N/A" | if . == "" then "N/A" else . end')
  sonar_url=$(echo "$report_data" | jq -r '.metadata.sonarUrl')
  analysis_id=$(echo "$report_data" | jq -r '.metadata.analysisId // "N/A"')

  # Extract quality gate
  local qg_status
  qg_status=$(echo "$report_data" | jq -r '.qualityGate.status // "UNKNOWN"')
  local qg_badge="❌ FAILED"
  [[ "$qg_status" == "OK" ]] && qg_badge="✅ PASSED"
  [[ "$qg_status" == "NONE" ]] && qg_badge="⚠️ NONE"

  # Extract measures
  local bugs vulns smells coverage duplication loc tech_debt debt_ratio
  local rel_rating sec_rating maint_rating hotspots_reviewed sec_review_rating
  bugs=$(echo "$report_data" | jq -r '.measures.bugs // "0"')
  vulns=$(echo "$report_data" | jq -r '.measures.vulnerabilities // "0"')
  smells=$(echo "$report_data" | jq -r '.measures.code_smells // "0"')
  coverage=$(echo "$report_data" | jq -r '.measures.coverage // "N/A"')
  duplication=$(echo "$report_data" | jq -r '.measures.duplicated_lines_density // "N/A"')
  loc=$(echo "$report_data" | jq -r '.measures.ncloc // "0"')
  tech_debt=$(echo "$report_data" | jq -r '.measures.sqale_index // "0"')
  debt_ratio=$(echo "$report_data" | jq -r '.measures.sqale_debt_ratio // "N/A"')
  rel_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.reliability_rating // "0"')")
  sec_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.security_rating // "0"')")
  maint_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.sqale_rating // "0"')")
  hotspots_reviewed=$(echo "$report_data" | jq -r '.measures.security_hotspots_reviewed // "N/A"')
  sec_review_rating=$(rating_to_letter "$(echo "$report_data" | jq -r '.measures.security_review_rating // "0"')")

  # New code period metrics
  local new_bugs new_vulns new_smells new_coverage new_duplication
  new_bugs=$(echo "$report_data" | jq -r '.measures.new_bugs // "N/A"')
  new_vulns=$(echo "$report_data" | jq -r '.measures.new_vulnerabilities // "N/A"')
  new_smells=$(echo "$report_data" | jq -r '.measures.new_code_smells // "N/A"')
  new_coverage=$(echo "$report_data" | jq -r '.measures.new_coverage // "N/A"')
  new_duplication=$(echo "$report_data" | jq -r '.measures.new_duplicated_lines_density // "N/A"')

  # Format tech debt
  local tech_debt_fmt
  tech_debt_fmt=$(format_duration "$tech_debt")

  # Issues summary
  local total_issues issue_bugs issue_vulns issue_smells
  total_issues=$(echo "$report_data" | jq -r '.issuesSummary.total // 0')
  issue_bugs=$(echo "$report_data" | jq -r '.issuesSummary.byType.BUG // 0')
  issue_vulns=$(echo "$report_data" | jq -r '.issuesSummary.byType.VULNERABILITY // 0')
  issue_smells=$(echo "$report_data" | jq -r '.issuesSummary.byType.CODE_SMELL // 0')

  # Severity breakdown
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

  # Build output file
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filename="${project_key}_${timestamp}.md"
  local filepath="${output_dir}/${filename}"
  mkdir -p "$output_dir"

  cat > "$filepath" <<MARKDOWN
# SonarQube Analysis Report

## Project Information

| Field | Value |
|-------|-------|
| **Project** | ${project_name} (\`${project_key}\`) |
| **Branch** | ${branch} |
| **Report Date** | ${report_date} |
| **Last Analysis Date** | ${last_analysis_date} |
| **Analysis ID** | ${analysis_id} |
| **SonarQube URL** | ${sonar_url} |

---

## Quality Gate: ${qg_badge}

**Status: ${qg_status}**

### Quality Gate Conditions

$(echo "$report_data" | jq -r '
  if (.qualityGate.conditions | length) > 0 then
    "| Metric | Status | Value | Threshold |\n|--------|--------|-------|-----------|\n" +
    ([.qualityGate.conditions[]? |
      "| " + .metric + " | " + .status + " | " + (.actualValue // "N/A") + " | " + (.errorThreshold // "N/A") + " |"
    ] | join("\n"))
  else
    "_No conditions configured._"
  end
')

---

## Overall Metrics

### Reliability

| Metric | Value |
|--------|-------|
| **Rating** | ${rel_rating} |
| **Bugs** | ${bugs} |

### Security

| Metric | Value |
|--------|-------|
| **Rating** | ${sec_rating} |
| **Vulnerabilities** | ${vulns} |
| **Hotspots Reviewed** | ${hotspots_reviewed}% |
| **Security Review Rating** | ${sec_review_rating} |

### Maintainability

| Metric | Value |
|--------|-------|
| **Rating** | ${maint_rating} |
| **Code Smells** | ${smells} |
| **Technical Debt** | ${tech_debt_fmt} |
| **Debt Ratio** | ${debt_ratio}% |

### Coverage & Duplications

| Metric | Value |
|--------|-------|
| **Coverage** | ${coverage}% |
| **Duplications** | ${duplication}% |
| **Lines of Code** | ${loc} |

---

## New Code Period

| Metric | Value |
|--------|-------|
| **New Bugs** | ${new_bugs} |
| **New Vulnerabilities** | ${new_vulns} |
| **New Code Smells** | ${new_smells} |
| **New Coverage** | ${new_coverage}% |
| **New Duplications** | ${new_duplication}% |

---

## Issues Summary

**Total Open Issues: ${total_issues}**

### By Type

| Type | Count |
|------|-------|
| 🐛 Bugs | ${issue_bugs} |
| 🔓 Vulnerabilities | ${issue_vulns} |
| 🔧 Code Smells | ${issue_smells} |

### By Severity

| Severity | Count |
|----------|-------|
| 🔴 Blocker | ${sev_blocker} |
| 🟠 Critical | ${sev_critical} |
| 🟡 Major | ${sev_major} |
| 🔵 Minor | ${sev_minor} |
| ⚪ Info | ${sev_info} |

---

## Security Hotspots

| Status | Count |
|--------|-------|
| **Total** | ${hotspot_total} |
| 🔍 To Review | ${hotspot_to_review} |
| ✅ Reviewed | ${hotspot_reviewed} |

---

## Security Hotspots Details

$(echo "$report_data" | jq -r '
  if (.hotspots | length) > 0 then
    "| # | Status | Risk | Rule | Component | Line | Message |\n|---|--------|------|------|-----------|------|---------|" +
    ([.hotspots | to_entries[]? |
      "| " + ((.key + 1) | tostring) +
      " | " + (.value.status // "?") +
      " | " + (.value.vulnerabilityProbability // "N/A") +
      " | " + (.value.rule // "") +
      " | " + ((.value.component // "") | split(":") | last) +
      " | " + ((.value.line // "") | tostring) +
      " | " + ((.value.message // "") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\\|"; "\\\\|")) + " |"
    ] | join("\n"))
  else
    "_No security hotspots found._"
  end
')

---

## Issues Details

$(echo "$report_data" | jq -r '
  if (.issues | length) > 0 then
    "| # | Severity | Type | Rule | Component | Line | Message | Effort |\n|---|----------|------|------|-----------|------|---------|--------|\n" +
    ([.issues | to_entries[]? |
      "| " + ((.key + 1) | tostring) +
      " | " + (.value.severity // "?") +
      " | " + (.value.type // "?") +
      " | " + (.value.rule // "") +
      " | " + ((.value.component // "") | split(":") | last) +
      " | " + ((.value.line // "") | tostring) +
      " | " + ((.value.message // "") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\\|"; "\\\\|")) +
      " | " + (.value.effort // "N/A") + " |"
    ] | join("\n"))
  else
    "_No open issues found._"
  end
')

---

> Report generated by [sonarqube-community-reporter](https://github.com/a-h-abid/sonarqube-community-reporter) on ${report_date}
MARKDOWN

  log_ok "Markdown report → ${filepath}"
  echo "$filepath"
}
