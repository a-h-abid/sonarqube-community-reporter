#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# shellcheck disable=SC2089,SC2090  # JSON strings stored in variables are intentional
# ==============================================================================
# test_reports.bats — Unit tests for report generator scripts
#
# Covers:
#   generate_json_report  (scripts/lib/report-json.sh)
#   generate_md_report    (scripts/lib/report-md.sh)
#   generate_html_report  (scripts/lib/report-html.sh)
#   generate_xlsx_report  (scripts/lib/report-xlsx.sh)
#   generate_ods_report   (scripts/lib/report-ods.sh)
#
# No real HTTP calls are made — all tests use pre-built report_data JSON.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# shellcheck source=helpers.bash
load 'helpers'

# ---------------------------------------------------------------------------
# Minimal but complete report_data JSON used across all tests
# ---------------------------------------------------------------------------
_REPORT_DATA='{
  "metadata": {
    "projectKey":  "my-project",
    "projectName": "My Project",
    "branch":      "main",
    "sonarUrl":    "http://sonar.example.com",
    "reportDate":  "2024-01-15T10:00:00Z",
    "lastAnalysisDate": "2024-01-14T09:30:00+0000",
    "analysisId":  "AXyz_analysis_456"
  },
  "qualityGate": {
    "status": "OK",
    "conditions": [
      {
        "metric":         "new_reliability_rating",
        "status":         "OK",
        "actualValue":    "1",
        "errorThreshold": "1",
        "comparator":     "GT"
      }
    ]
  },
  "measures": {
    "bugs":                       "2",
    "vulnerabilities":            "1",
    "code_smells":                "15",
    "coverage":                   "78.5",
    "duplicated_lines_density":   "3.2",
    "ncloc":                      "1234",
    "sqale_index":                "120",
    "sqale_debt_ratio":           "2.5",
    "reliability_rating":         "3.0",
    "security_rating":            "2.0",
    "sqale_rating":               "1.0",
    "security_hotspots_reviewed": "100",
    "security_review_rating":     "1.0",
    "alert_status":               "OK",
    "new_bugs":                   "0",
    "new_vulnerabilities":        "0",
    "new_code_smells":            "3",
    "new_coverage":               "85.0",
    "new_duplicated_lines_density": "0.0"
  },
  "issuesSummary": {
    "total": 18,
    "byType":     { "BUG": 2,  "VULNERABILITY": 1,  "CODE_SMELL": 15 },
    "bySeverity": { "BLOCKER": 1, "CRITICAL": 2, "MAJOR": 5, "MINOR": 7, "INFO": 3 }
  },
  "hotspotsSummary": {
    "total": 10, "toReview": 3, "reviewed": 7
  },
  "hotspots": [
    {
      "key": "HS1",
      "status": "TO_REVIEW",
      "vulnerabilityProbability": "HIGH",
      "securityCategory": "sql-injection",
      "message": "Unsanitized SQL query",
      "component": "my-project:src/Db.java",
      "line": 21,
      "rule": "java:S3649",
      "author": "dev1",
      "creationDate": "2024-01-15T09:00:00+0000",
      "updateDate": "2024-01-15T09:00:00+0000"
    },
    {
      "key": "HS2",
      "status": "REVIEWED",
      "vulnerabilityProbability": "MEDIUM",
      "securityCategory": "xss",
      "message": "Template output needs review",
      "component": "my-project:src/Web.java",
      "line": 8,
      "rule": "java:S5131",
      "author": "dev2",
      "creationDate": "2024-01-16T09:00:00+0000",
      "updateDate": "2024-01-16T12:00:00+0000"
    }
  ],
  "issues": [
    {
      "key":          "AXyz111",
      "severity":     "CRITICAL",
      "type":         "BUG",
      "message":      "Null pointer dereference",
      "component":    "my-project:src/Main.java",
      "line":         42,
      "rule":         "java:S2259",
      "effort":       "30min",
      "creationDate": "2024-01-15T10:00:00+0000"
    }
  ]
}'

setup() {
  export _OUTPUT_DIR
  _OUTPUT_DIR=$(mktemp -d)

  # Write report data to a temp file (generators now expect a file path)
  export _REPORT_DATA_FILE
  _REPORT_DATA_FILE=$(mktemp)
  echo "$_REPORT_DATA" > "$_REPORT_DATA_FILE"

  # Source all report libs (they source api.sh internally)
  # shellcheck source=../scripts/lib/report-json.sh
  source "${REPO_ROOT}/scripts/lib/report-json.sh"
  # shellcheck source=../scripts/lib/report-md.sh
  source "${REPO_ROOT}/scripts/lib/report-md.sh"
  # shellcheck source=../scripts/lib/report-html.sh
  source "${REPO_ROOT}/scripts/lib/report-html.sh"
  # shellcheck source=../scripts/lib/report-xlsx.sh
  source "${REPO_ROOT}/scripts/lib/report-xlsx.sh"
  # shellcheck source=../scripts/lib/report-ods.sh
  source "${REPO_ROOT}/scripts/lib/report-ods.sh"
  # shellcheck source=../scripts/lib/report-csv.sh
  source "${REPO_ROOT}/scripts/lib/report-csv.sh"
}

teardown() {
  rm -rf "$_OUTPUT_DIR"
  rm -f "$_REPORT_DATA_FILE"
}

# ===========================================================================
# generate_json_report
# ===========================================================================

@test "generate_json_report: creates a file in output dir" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  # The filepath is printed as the last line; log messages precede it
  [ -f "${lines[-1]}" ]
}

@test "generate_json_report: output file has .json extension" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.json ]]
}

@test "generate_json_report: output is valid JSON" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  run jq '.' "$filepath"
  [ "$status" -eq 0 ]
}

@test "generate_json_report: JSON contains metadata" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  key=$(jq -r '.metadata.projectKey' "$filepath")
  [ "$key" = "my-project" ]
}

@test "generate_json_report: JSON contains last analysis date" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  last_analysis_date=$(jq -r '.metadata.lastAnalysisDate' "$filepath")
  [ "$last_analysis_date" = "2024-01-14T09:30:00+0000" ]
}

@test "generate_json_report: JSON contains qualityGate status" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  qg=$(jq -r '.qualityGate.status' "$filepath")
  [ "$qg" = "OK" ]
}

@test "generate_json_report: JSON contains issues array" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  count=$(jq '.issues | length' "$filepath")
  [ "$count" -eq 1 ]
}

@test "generate_json_report: filename contains project key" {
  run generate_json_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"my-project"* ]]
}

@test "generate_json_report: creates output directory if missing" {
  local new_dir="${_OUTPUT_DIR}/nested/sub"
  run generate_json_report "$_REPORT_DATA_FILE" "$new_dir"
  [ "$status" -eq 0 ]
  [ -d "$new_dir" ]
}

# ===========================================================================
# generate_md_report
# ===========================================================================

@test "generate_md_report: creates a file in output dir" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "${lines[-1]}" ]
}

@test "generate_md_report: output file has .md extension" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.md ]]
}

@test "generate_md_report: report contains project name" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "My Project" "$filepath"
}

@test "generate_md_report: report contains quality gate status" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "PASSED" "$filepath"
}

@test "generate_md_report: report contains bugs metric" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Bugs" "$filepath"
}

@test "generate_md_report: report contains coverage value" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "78.5" "$filepath"
}

@test "generate_md_report: report contains last analysis date" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "2024-01-14T09:30:00+0000" "$filepath"
}

@test "generate_md_report: report contains hotspot section" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -qi "hotspot" "$filepath"
}

@test "generate_md_report: report lists hotspot details with review status" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Security Hotspots Details" "$filepath"
  grep -q '^### 1\. TO_REVIEW hotspot$' "$filepath"
  grep -q '^### 2\. REVIEWED hotspot$' "$filepath"
  grep -q '^- Risk: HIGH$' "$filepath"
  grep -q '^- Component: src/Db.java$' "$filepath"
  grep -q "Unsanitized SQL query" "$filepath"
}

@test "generate_md_report: report contains issues details" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q '^### 1\. CRITICAL BUG$' "$filepath"
  grep -q '^- Component: src/Main.java$' "$filepath"
  grep -q '^- Rule: java:S2259$' "$filepath"
  grep -q "Null pointer dereference" "$filepath"
}

@test "generate_md_report: filename contains project key" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"my-project"* ]]
}

@test "generate_md_report: reliability rating is a letter" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # reliability_rating=3.0 → C
  grep -q "| \*\*Rating\*\* | C |" "$filepath"
}

# ===========================================================================
# generate_html_report
# ===========================================================================

@test "generate_html_report: creates a file in output dir" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "${lines[-1]}" ]
}

@test "generate_html_report: output file has .html extension" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.html ]]
}

@test "generate_html_report: output is non-empty HTML" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "<!DOCTYPE html>" "$filepath"
}

@test "generate_html_report: report contains project name" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "My Project" "$filepath"
}

@test "generate_html_report: quality gate status placeholder is replaced" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # Placeholder {{QG_STATUS}} should not appear in output
  run grep -c '{{QG_STATUS}}' "$filepath"
  [ "$output" = "0" ]
}

@test "generate_html_report: no unreplaced placeholders remain" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # None of the {{...}} placeholders should remain
  run grep -c '{{[A-Z_]*}}' "$filepath"
  [ "$output" = "0" ]
}

@test "generate_html_report: contains bugs value" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q ">2<" "$filepath"
}

@test "generate_html_report: contains sonar URL" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "sonar.example.com" "$filepath"
}

@test "generate_html_report: contains last analysis date" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "2024-01-14T09:30:00+0000" "$filepath"
}

@test "generate_html_report: filename contains project key" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"my-project"* ]]
}

@test "generate_html_report: fails when template file is missing" {
  # Override the template dir path by pointing to a non-existent location
  _REPORT_HTML_SCRIPT_DIR="/nonexistent/path"
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -ne 0 ]
}

@test "generate_html_report: contains issues details table" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Null pointer dereference" "$filepath"
}

@test "generate_html_report: contains hotspot details table with statuses" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Security Hotspots Details" "$filepath"
  grep -q 'class="hotspots-table"' "$filepath"
  grep -q 'hotspots-shell' "$filepath"
  grep -q 'class="hotspot-entry"' "$filepath"
  grep -q 'class="hotspot-summary-row"' "$filepath"
  grep -q 'class="hotspot-detail-row"' "$filepath"
  grep -q "TO_REVIEW" "$filepath"
  grep -q "REVIEWED" "$filepath"
  grep -q "Unsanitized SQL query" "$filepath"
}

@test "generate_html_report: shortens visible component paths in hotspots" {
  local tmp_hotspot_component
  tmp_hotspot_component=$(mktemp)
  echo "$_REPORT_DATA" | jq '
    .hotspots = [
      {
        "key": "HS3", "status": "TO_REVIEW",
        "vulnerabilityProbability": "MEDIUM",
        "securityCategory": "xss",
        "message": "Long path should be shortened in the hotspot summary row",
        "component": "my-project:src/main/java/com/example/deep/repository/DbAccess.java",
        "line": 19,
        "rule": "java:S5131",
        "author": "dev3",
        "creationDate": "2024-01-15T10:00:00+0000",
        "updateDate": "2024-01-15T10:00:00+0000"
      }
    ]
  ' > "$tmp_hotspot_component"
  run generate_html_report "$tmp_hotspot_component" "$_OUTPUT_DIR"
  rm -f "$tmp_hotspot_component"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'title="my-project:src/main/java/com/example/deep/repository/DbAccess.java"' "$filepath"
  grep -q '\.\.\./deep/repository/DbAccess.java' "$filepath"
}

@test "generate_html_report: issues details use summary and detail rows" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'table-shell issues-shell' "$filepath"
  grep -q 'issues-shell' "$filepath"
  grep -q 'class="issues-table"' "$filepath"
  grep -q 'class="issue-entry"' "$filepath"
  grep -q 'class="issue-summary-row"' "$filepath"
  grep -q 'class="issue-detail-row"' "$filepath"
}

@test "generate_html_report: shortens visible component paths in issues" {
  local tmp_component
  tmp_component=$(mktemp)
  echo "$_REPORT_DATA" | jq '
    .issues = [
      {
        "key": "AX2", "severity": "MAJOR", "type": "CODE_SMELL",
        "message": "Long path should be shortened in the summary row",
        "component": "my-project:src/main/java/com/example/deep/service/MainService.java",
        "line": 64,
        "rule": "java:S1192", "effort": "8min",
        "creationDate": "2024-01-15T10:00:00+0000"
      }
    ]
  ' > "$tmp_component"
  run generate_html_report "$tmp_component" "$_OUTPUT_DIR"
  rm -f "$tmp_component"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'title="my-project:src/main/java/com/example/deep/service/MainService.java"' "$filepath"
  grep -q '\.\.\./deep/service/MainService.java' "$filepath"
}

@test "generate_html_report: uses PDF-safe card layout wrappers" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'class="cards cards-6"' "$filepath"
  grep -q 'class="card-wrap pdf-row-start-2"' "$filepath"
  grep -q '\.cards-6 \.card-wrap { width: 25%; }' "$filepath"
  grep -q '\.cards-4 \.card-wrap:nth-child(4n + 1),' "$filepath"
  grep -q '\.cards-5 \.card-wrap:nth-child(5n + 1) { clear: left; }' "$filepath"
  grep -q 'min-height: 136px;' "$filepath"
}

@test "generate_pdf_report: uses print media and desktop viewport for card grids" {
  grep -q -- '--viewport-size 1280x1024' "${REPO_ROOT}/scripts/lib/report-pdf.sh"
  grep -q -- '--print-media-type' "${REPO_ROOT}/scripts/lib/report-pdf.sh"
  grep -q 'pdf-row-start-2 { clear: left !important; }' "${REPO_ROOT}/scripts/lib/report-pdf.sh"
}

@test "generate_html_report: uses PDF-safe issues summary layout" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'class="summary-grid"' "$filepath"
  grep -q 'class="summary-panel"' "$filepath"
}

@test "generate_html_report: issues table handles special characters" {
  local tmp_specials
  tmp_specials=$(mktemp)
  echo "$_REPORT_DATA" | jq '
    .issues = [
      {
        "key": "AX1", "severity": "MAJOR", "type": "BUG",
        "message": "Use || instead of | and & instead of &&",
        "component": "proj:src/Main.java", "line": 10,
        "rule": "java:S101", "effort": "5min",
        "creationDate": "2024-01-15T10:00:00+0000"
      }
    ]
  ' > "$tmp_specials"
  run generate_html_report "$tmp_specials" "$_OUTPUT_DIR"
  rm -f "$tmp_specials"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # Verify the special chars message appears in the output
  grep -q 'Use || instead of | and' "$filepath"
}

# ===========================================================================
# spreadsheet helper data
# ===========================================================================

@test "write_summary_csv: contains KPI rows and excludes quality gate conditions table" {
  local summary_csv
  summary_csv=$(mktemp)
  run write_summary_csv "$_REPORT_DATA_FILE" "$summary_csv"
  [ "$status" -eq 0 ]

  grep -q '"Metric","Value"' "$summary_csv"
  grep -q '"Quality Gate Status","OK"' "$summary_csv"
  grep -q '"Bugs","2"' "$summary_csv"

  # Summary sheet is KPI-only (no condition-level table rows)
  ! grep -q 'new_reliability_rating' "$summary_csv"

  rm -f "$summary_csv"
}

@test "write_issues_csv: includes all issue detail columns" {
  local issues_csv
  issues_csv=$(mktemp)
  run write_issues_csv "$_REPORT_DATA_FILE" "$issues_csv"
  [ "$status" -eq 0 ]

  grep -q '"Key","Severity","Type","Rule","Component","Line","Message","Effort","Creation Date"' "$issues_csv"
  grep -q '"AXyz111","CRITICAL","BUG","java:S2259","my-project:src/Main.java","42","Null pointer dereference","30min","2024-01-15T10:00:00+0000"' "$issues_csv"

  rm -f "$issues_csv"
}

@test "write_hotspots_csv: includes hotspot detail columns and review status" {
  local hotspots_csv
  hotspots_csv=$(mktemp)
  run write_hotspots_csv "$_REPORT_DATA_FILE" "$hotspots_csv"
  [ "$status" -eq 0 ]

  grep -q '"Key","Status","Risk","Rule","Component","Line","Message","Category","Author","Creation Date","Update Date"' "$hotspots_csv"
  grep -q '"HS1","TO_REVIEW","HIGH","java:S3649","my-project:src/Db.java","21","Unsanitized SQL query","sql-injection","dev1","2024-01-15T09:00:00+0000","2024-01-15T09:00:00+0000"' "$hotspots_csv"

  rm -f "$hotspots_csv"
}

# ===========================================================================
# generate_xlsx_report
# ===========================================================================

@test "generate_xlsx_report: creates a file in output dir" {
  if ! command -v ssconvert &>/dev/null; then
    skip "ssconvert is not installed"
  fi

  run generate_xlsx_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "${lines[-1]}" ]
}

@test "generate_xlsx_report: output file has .xlsx extension" {
  if ! command -v ssconvert &>/dev/null; then
    skip "ssconvert is not installed"
  fi

  run generate_xlsx_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.xlsx ]]
}

@test "generate_xlsx_report: contains required three sheets" {
  if ! command -v ssconvert &>/dev/null || ! command -v unzip &>/dev/null; then
    skip "ssconvert or unzip is not installed"
  fi

  run generate_xlsx_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"

  local workbook_xml
  workbook_xml=$(unzip -p "$filepath" xl/workbook.xml)

  [[ "$workbook_xml" == *'name="Overall Summary.csv"'* ]]
  [[ "$workbook_xml" == *'name="Issues Details.csv"'* ]]
  [[ "$workbook_xml" == *'name="Hotspots Details.csv"'* ]]

  local sheet_count
  sheet_count=$(echo "$workbook_xml" | grep -o 'name="[^"]*\.csv"' | wc -l)
  [ "$sheet_count" -eq 3 ]
}

@test "generate_xlsx_report: gracefully skips when ssconvert is unavailable" {
  SSCONVERT_BIN="__missing_ssconvert__" run generate_xlsx_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping XLSX generation"* ]]
}

# ===========================================================================
# generate_ods_report
# ===========================================================================

@test "generate_ods_report: creates a file in output dir" {
  if ! command -v ssconvert &>/dev/null; then
    skip "ssconvert is not installed"
  fi

  run generate_ods_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "${lines[-1]}" ]
}

@test "generate_ods_report: output file has .ods extension" {
  if ! command -v ssconvert &>/dev/null; then
    skip "ssconvert is not installed"
  fi

  run generate_ods_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.ods ]]
}

@test "generate_ods_report: contains required three sheets" {
  if ! command -v ssconvert &>/dev/null || ! command -v unzip &>/dev/null; then
    skip "ssconvert or unzip is not installed"
  fi

  run generate_ods_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"

  local content_xml
  content_xml=$(unzip -p "$filepath" content.xml)

  [[ "$content_xml" == *'table:name="Overall Summary.csv"'* ]]
  [[ "$content_xml" == *'table:name="Issues Details.csv"'* ]]
  [[ "$content_xml" == *'table:name="Hotspots Details.csv"'* ]]

  local sheet_count
  sheet_count=$(echo "$content_xml" | grep -o 'table:name="[^"]*\.csv"' | wc -l)
  [ "$sheet_count" -eq 3 ]
}

@test "generate_ods_report: gracefully skips when ssconvert is unavailable" {
  SSCONVERT_BIN="__missing_ssconvert__" run generate_ods_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping ODS generation"* ]]
}

# ===========================================================================
# generate_csv_report
# ===========================================================================

@test "generate_csv_report: creates three CSV files in output dir" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]

  local csv_files
  csv_files=$(find "$_OUTPUT_DIR" -name "*.csv" | wc -l)
  [ "$csv_files" -eq 3 ]
}

@test "generate_csv_report: all three file paths are printed" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]

  # Last 3 output lines should be file paths that exist
  local n="${#lines[@]}"
  [ -f "${lines[$((n-3))]}" ]
  [ -f "${lines[$((n-2))]}" ]
  [ -f "${lines[$((n-1))]}" ]
}

@test "generate_csv_report: file names contain project key" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *"my-project"* ]]
  [[ "${lines[-2]}" == *"my-project"* ]]
  [[ "${lines[-3]}" == *"my-project"* ]]
}

@test "generate_csv_report: summary CSV has expected headers" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  local summary_file="${lines[$((n-3))]}"
  grep -q '"Metric","Value"' "$summary_file"
}

@test "generate_csv_report: summary CSV contains quality gate status" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  local summary_file="${lines[$((n-3))]}"
  grep -q '"Quality Gate Status","OK"' "$summary_file"
}

@test "generate_csv_report: issues CSV has expected headers" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  local issues_file="${lines[$((n-2))]}"
  grep -q '"Key","Severity","Type","Rule","Component","Line","Message","Effort","Creation Date"' "$issues_file"
}

@test "generate_csv_report: issues CSV contains issue data" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  local issues_file="${lines[$((n-2))]}"
  grep -q '"AXyz111"' "$issues_file"
  grep -q '"CRITICAL"' "$issues_file"
  grep -q '"Null pointer dereference"' "$issues_file"
}

@test "generate_csv_report: hotspots CSV has expected headers" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  local hotspots_file="${lines[$((n-1))]}"
  grep -q '"Key","Status","Risk","Rule","Component","Line","Message","Category","Author","Creation Date","Update Date"' "$hotspots_file"
}

@test "generate_csv_report: hotspots CSV contains hotspot data" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  local hotspots_file="${lines[$((n-1))]}"
  grep -q '"HS1"' "$hotspots_file"
  grep -q '"TO_REVIEW"' "$hotspots_file"
  grep -q '"Unsanitized SQL query"' "$hotspots_file"
}

@test "generate_csv_report: summary filename ends with _summary.csv" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  [[ "${lines[$((n-3))]}" == *_summary.csv ]]
}

@test "generate_csv_report: issues filename ends with _issues.csv" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  [[ "${lines[$((n-2))]}" == *_issues.csv ]]
}

@test "generate_csv_report: hotspots filename ends with _hotspots.csv" {
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local n="${#lines[@]}"
  [[ "${lines[$((n-1))]}" == *_hotspots.csv ]]
}
