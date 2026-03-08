#!/usr/bin/env bash
# ==============================================================================
# report-spreadsheet.sh — Shared spreadsheet report generation helpers
# ==============================================================================
[[ -n "${_REPORT_SPREADSHEET_SH_LOADED:-}" ]] && return 0
_REPORT_SPREADSHEET_SH_LOADED=1

set -euo pipefail

_REPORT_SPREADSHEET_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_REPORT_SPREADSHEET_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# write_summary_csv <report_data_file> <summary_csv>
#   Writes KPI-only summary rows for the "Overall Summary" sheet.
# ---------------------------------------------------------------------------
write_summary_csv() {
  local report_data_file="$1"
  local summary_csv="$2"

  jq -r '
    ["Metric","Value"],
    ["Project Key", (.metadata.projectKey // "N/A")],
    ["Project Name", (.metadata.projectName // .metadata.projectKey // "N/A")],
    ["Branch", (.metadata.branch // "main")],
    ["Report Date", (.metadata.reportDate // "N/A")],
    ["Last Analysis Date", (.metadata.lastAnalysisDate // "N/A")],
    ["Analysis ID", (.metadata.analysisId // "N/A")],
    ["SonarQube URL", (.metadata.sonarUrl // "N/A")],
    ["Quality Gate Status", (.qualityGate.status // "UNKNOWN")],
    ["Bugs", (.measures.bugs // "0")],
    ["Vulnerabilities", (.measures.vulnerabilities // "0")],
    ["Code Smells", (.measures.code_smells // "0")],
    ["Coverage (%)", (.measures.coverage // "N/A")],
    ["Duplicated Lines Density (%)", (.measures.duplicated_lines_density // "N/A")],
    ["Lines of Code", (.measures.ncloc // "0")],
    ["Technical Debt (min)", (.measures.sqale_index // "0")],
    ["Debt Ratio (%)", (.measures.sqale_debt_ratio // "N/A")],
    ["Reliability Rating", (.measures.reliability_rating // "N/A")],
    ["Security Rating", (.measures.security_rating // "N/A")],
    ["Maintainability Rating", (.measures.sqale_rating // "N/A")],
    ["Security Hotspots Reviewed (%)", (.measures.security_hotspots_reviewed // "N/A")],
    ["Security Review Rating", (.measures.security_review_rating // "N/A")],
    ["New Bugs", (.measures.new_bugs // "N/A")],
    ["New Vulnerabilities", (.measures.new_vulnerabilities // "N/A")],
    ["New Code Smells", (.measures.new_code_smells // "N/A")],
    ["New Coverage (%)", (.measures.new_coverage // "N/A")],
    ["New Duplicated Lines Density (%)", (.measures.new_duplicated_lines_density // "N/A")],
    ["Total Issues", (.issuesSummary.total // 0 | tostring)],
    ["Hotspots Total", (.hotspotsSummary.total // 0 | tostring)],
    ["Hotspots To Review", (.hotspotsSummary.toReview // 0 | tostring)],
    ["Hotspots Reviewed", (.hotspotsSummary.reviewed // 0 | tostring)]
    | @csv
  ' "$report_data_file" > "$summary_csv" || return 1
}

# ---------------------------------------------------------------------------
# write_issues_csv <report_data_file> <issues_csv>
#   Writes all fetched issue rows for the "Issues Details" sheet.
# ---------------------------------------------------------------------------
write_issues_csv() {
  local report_data_file="$1"
  local issues_csv="$2"

  jq -r '
    ["Key","Severity","Type","Rule","Component","Line","Message","Effort","Creation Date"],
    (
      .issues // []
      | .[]
      | [
          (.key // ""),
          (.severity // ""),
          (.type // ""),
          (.rule // ""),
          (.component // ""),
          ((.line // "") | tostring),
          (.message // ""),
          (.effort // ""),
          (.creationDate // "")
        ]
    )
    | @csv
  ' "$report_data_file" > "$issues_csv" || return 1
}

# ---------------------------------------------------------------------------
# generate_spreadsheet_report <report_data_file> <output_dir> <extension>
#   Creates spreadsheet with exactly two sheets:
#   - Overall Summary
#   - Issues Details
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

  local project_key
  project_key=$(jq -r '.metadata.projectKey' "$report_data_file")
  local timestamp
  timestamp=$(date '+%Y%m%d_%H%M%S')
  local filepath="${output_dir}/${project_key}_${timestamp}.${extension}"

  mkdir -p "$output_dir"

  local tmpdir
  tmpdir=$(mktemp -d)
  trap '[[ -n "${tmpdir:-}" ]] && rm -rf "$tmpdir"' RETURN

  local summary_csv="${tmpdir}/Overall Summary.csv"
  local issues_csv="${tmpdir}/Issues Details.csv"

  write_summary_csv "$report_data_file" "$summary_csv" || {
    log_error "Failed to prepare summary sheet data"
    return 1
  }

  write_issues_csv "$report_data_file" "$issues_csv" || {
    log_error "Failed to prepare issues sheet data"
    return 1
  }

  "$ssconvert_bin" --merge-to="$filepath" "$summary_csv" "$issues_csv" >/dev/null 2>&1 || {
    log_error "${ssconvert_bin} failed to generate ${extension^^} report"
    return 1
  }

  log_ok "${extension^^} report → ${filepath}"
  echo "$filepath"
}
