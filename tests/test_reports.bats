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
  # shellcheck source=../scripts/lib/report-sarif.sh
  source "${REPO_ROOT}/scripts/lib/report-sarif.sh"
  # shellcheck source=../scripts/lib/report-pdf.sh
  source "${REPO_ROOT}/scripts/lib/report-pdf.sh"

  # Fake wkhtmltopdf + ssconvert so PDF/spreadsheet success paths are fast and
  # deterministic (the real renderers are slow and depend on xvfb / gnumeric).
  export _FAKE_BIN
  _FAKE_BIN=$(mktemp -d)
  cat > "$_FAKE_BIN/wkhtmltopdf" <<'SH'
#!/usr/bin/env bash
out="${@: -1}"; printf '%%PDF-1.4 fake' > "$out"
SH
  cat > "$_FAKE_BIN/ssconvert" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --merge-to=*) printf 'x' > "${a#--merge-to=}" ;; esac; done
SH
  chmod +x "$_FAKE_BIN/wkhtmltopdf" "$_FAKE_BIN/ssconvert"
}

teardown() {
  rm -rf "$_OUTPUT_DIR"
  rm -f "$_REPORT_DATA_FILE"
  rm -rf "$_FAKE_BIN"
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

@test "generate_json_report: includes quality profiles & gate name when present" {
  local f; f=$(mktemp)
  jq '.metadata.qualityGateName = "Sonar way"
      | .metadata.qualityProfiles = [{"key":"k","name":"Sonar way","language":"java","languageName":"Java"}]' \
    "$_REPORT_DATA_FILE" > "$f"
  run generate_json_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  [ "$(jq -r '.metadata.qualityGateName' "$filepath")" = "Sonar way" ]
  [ "$(jq -r '.metadata.qualityProfiles[0].name' "$filepath")" = "Sonar way" ]
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

@test "generate_md_report: shows line range when endLine > startLine on an issue" {
  local enriched
  enriched=$(mktemp)
  jq '.issues[0] += {startLine: 42, endLine: 47}' "$_REPORT_DATA_FILE" > "$enriched"

  run generate_md_report "$enriched" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q '^- Line: 42-47$' "$filepath"

  rm -f "$enriched"
}

@test "generate_md_report: keeps single line format when endLine == startLine" {
  local enriched
  enriched=$(mktemp)
  jq '.issues[0] += {startLine: 42, endLine: 42}' "$_REPORT_DATA_FILE" > "$enriched"

  run generate_md_report "$enriched" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q '^- Line: 42$' "$filepath"

  rm -f "$enriched"
}

@test "generate_md_report: renders Why section when ruleDescription present (short mode)" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "short", codeSnippets: false, snippetContext: 3}
      | .issues[0] += {ruleDescription: {whyText: "Long version of why.", whyTextShort: "Short why."}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  run generate_md_report "$enriched" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Why is this an issue" "$filepath"
  grep -q "Short why." "$filepath"

  rm -f "$enriched"
}

@test "generate_md_report: full mode uses whyText (not the short)" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "full", codeSnippets: false, snippetContext: 3}
      | .issues[0] += {ruleDescription: {whyText: "Long version of why.", whyTextShort: "Short why."}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  run generate_md_report "$enriched" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Long version of why" "$filepath"

  rm -f "$enriched"
}

@test "generate_md_report: omits Why section when ruleDescription absent" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  ! grep -q "Why is this an issue" "$filepath"
}

@test "generate_md_report: does NOT include How to fix in Markdown" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "short", codeSnippets: false, snippetContext: 3}
      | .issues[0] += {ruleDescription: {whyText: "Why.", whyTextShort: "Why.", howToFixText: "DO THE FIX", howToFixTextShort: "DO THE FIX"}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  run generate_md_report "$enriched" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  ! grep -q "How to fix" "$filepath"
  ! grep -q "DO THE FIX" "$filepath"

  rm -f "$enriched"
}

@test "generate_md_report: hotspot Risk section when ruleDescription.riskText present" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "short", codeSnippets: false, snippetContext: 3}
      | .hotspots[0] += {ruleDescription: {riskText: "SQL injection risk explained."}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  run generate_md_report "$enriched" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "What's the risk" "$filepath"
  grep -q "SQL injection risk explained" "$filepath"

  rm -f "$enriched"
}

# ===========================================================================
# generate_md_report — quality profiles & quality gate name
# ===========================================================================

@test "generate_md_report: shows quality gate name row when present" {
  local f; f=$(mktemp)
  jq '.metadata.qualityGateName = "Sonar way"' "$_REPORT_DATA_FILE" > "$f"
  run generate_md_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -qF '| **Quality Gate** | Sonar way |' "$filepath"
}

@test "generate_md_report: renders Quality Profiles section when present" {
  local f; f=$(mktemp)
  jq '.metadata.qualityProfiles = [
    {"key":"k1","name":"Sonar way","language":"java","languageName":"Java"},
    {"key":"k2","name":"Custom Python","language":"py","languageName":"Python"}
  ]' "$_REPORT_DATA_FILE" > "$f"
  run generate_md_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q '## Quality Profiles' "$filepath"
  grep -qF '| Java | Sonar way |' "$filepath"
  grep -qF '| Python | Custom Python |' "$filepath"
}

@test "generate_md_report: omits quality profiles & gate name when absent" {
  run generate_md_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  run grep -c '## Quality Profiles' "$filepath"
  [ "$output" = "0" ]
  run grep -cF '**Quality Gate**' "$filepath"
  [ "$output" = "0" ]
}

@test "generate_md_report: shows 'no profiles' note when enabled but empty" {
  local f; f=$(mktemp)
  jq '.metadata.qualityProfiles = []' "$_REPORT_DATA_FILE" > "$f"
  run generate_md_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q '## Quality Profiles' "$filepath"
  grep -q 'No quality profiles found' "$filepath"
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

@test "generate_html_report: shows full component path from project root in hotspots" {
  local tmp_hotspot_component
  tmp_hotspot_component=$(mktemp)
  echo "$_REPORT_DATA" | jq '
    .hotspots = [
      {
        "key": "HS3", "status": "TO_REVIEW",
        "vulnerabilityProbability": "MEDIUM",
        "securityCategory": "xss",
        "message": "Full path should be shown in the hotspot summary row",
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
  # Full path from the project root is shown, with no "..." truncation
  grep -q '<span class="hotspot-component-path">src/main/java/com/example/deep/repository/DbAccess.java</span>' "$filepath"
  ! grep -q '\.\.\./deep/repository/DbAccess.java' "$filepath"
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

@test "generate_html_report: renders line range when endLine > startLine in issue" {
  local enriched
  enriched=$(mktemp)
  jq '.issues[0] += {startLine: 42, endLine: 47}' "$_REPORT_DATA_FILE" > "$enriched"

  run generate_html_report "$enriched" "$_OUTPUT_DIR"
  rm -f "$enriched"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q ">42-47<" "$filepath"
}

@test "generate_html_report: renders issue \"Why is this an issue?\" section when ruleDescription present" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "short", codeSnippets: false, snippetContext: 3}
      | .issues[0] += {ruleDescription: {whyHtml: "<p>Because nulls are dangerous.</p>", whyText: "Because nulls are dangerous.", whyTextShort: "Because nulls are dangerous."}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  run generate_html_report "$enriched" "$_OUTPUT_DIR"
  rm -f "$enriched"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "Why is this an issue" "$filepath"
  grep -q "Because nulls are dangerous" "$filepath"
}

@test "generate_html_report: renders \"How to fix it\" section when ruleDescription.howToFixHtml present" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "short", codeSnippets: false, snippetContext: 3}
      | .issues[0] += {ruleDescription: {whyHtml: "<p>w</p>", whyText: "w", whyTextShort: "w", howToFixHtml: "<p>Check for null first.</p>", howToFixText: "Check for null first.", howToFixTextShort: "Check for null first."}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  run generate_html_report "$enriched" "$_OUTPUT_DIR"
  rm -f "$enriched"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "How to fix it" "$filepath"
  grep -q "Check for null first" "$filepath"
}

@test "generate_html_report: renders code snippet block with highlighted lines" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "", codeSnippets: true, snippetContext: 1}
      | .issues[0] += {codeSnippet: {startLine: 40, endLine: 44, lines: [
          {n:40, text:"int x = 0;",        highlighted:false},
          {n:41, text:"if (cond) {",       highlighted:false},
          {n:42, text:"  return x.bar;",   highlighted:true},
          {n:43, text:"}",                  highlighted:false},
          {n:44, text:"// after",            highlighted:false}
        ]}}' "$_REPORT_DATA_FILE" > "$enriched"

  run generate_html_report "$enriched" "$_OUTPUT_DIR"
  rm -f "$enriched"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'class="code-snippet"' "$filepath"
  grep -q 'code-line-hl' "$filepath"
  grep -q "return x.bar" "$filepath"
}

@test "generate_html_report: code snippet escapes HTML in source text" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "", codeSnippets: true, snippetContext: 0}
      | .issues[0] += {codeSnippet: {startLine: 1, endLine: 1, lines: [
          {n:1, text:"if (a<b && c>d)", highlighted:true}
        ]}}' "$_REPORT_DATA_FILE" > "$enriched"

  run generate_html_report "$enriched" "$_OUTPUT_DIR"
  rm -f "$enriched"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "a&lt;b" "$filepath"
  grep -q "c&gt;d" "$filepath"
}

@test "generate_html_report: omits enrichment sections when fields absent (back-compat)" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  ! grep -q "Why is this an issue" "$filepath"
  ! grep -q "How to fix" "$filepath"
  ! grep -q 'class="code-snippet"' "$filepath"
}

@test "generate_html_report: template carries code snippet CSS classes" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # CSS classes for the new section markup
  grep -q '\.code-snippet' "$filepath"
  grep -q '\.code-line-hl' "$filepath"
  grep -q '\.issue-section' "$filepath"
}

@test "generate_html_report: hotspot \"What's the risk?\" section uses riskText when present" {
  local enriched
  enriched=$(mktemp)
  jq '.metadata.enrichment = {ruleDescriptions: "short", codeSnippets: false, snippetContext: 3}
      | .hotspots[0] += {ruleDescription: {riskText: "An attacker could read secrets.", whyHtml: "<p>w</p>", whyText: "w", whyTextShort: "w"}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  run generate_html_report "$enriched" "$_OUTPUT_DIR"
  rm -f "$enriched"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q "What's the risk" "$filepath"
  grep -q "An attacker could read secrets" "$filepath"
}

@test "generate_html_report: shows full component path from project root in issues" {
  local tmp_component
  tmp_component=$(mktemp)
  echo "$_REPORT_DATA" | jq '
    .issues = [
      {
        "key": "AX2", "severity": "MAJOR", "type": "CODE_SMELL",
        "message": "Full path should be shown in the summary row",
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
  # Full path from the project root is shown, with no "..." truncation
  grep -q '<span class="issue-component-path">src/main/java/com/example/deep/service/MainService.java</span>' "$filepath"
  ! grep -q '\.\.\./deep/service/MainService.java' "$filepath"
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
# generate_html_report — quality profiles & quality gate name
# ===========================================================================

@test "generate_html_report: shows quality gate name in header when present" {
  local f; f=$(mktemp)
  jq '.metadata.qualityGateName = "Sonar way"' "$_REPORT_DATA_FILE" > "$f"
  run generate_html_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'class="header-info qg-name"' "$filepath"
  grep -q 'Sonar way' "$filepath"
}

@test "generate_html_report: renders Quality Profiles table when present" {
  local f; f=$(mktemp)
  jq '.metadata.qualityProfiles = [
    {"key":"k1","name":"Sonar way","language":"java","languageName":"Java"},
    {"key":"k2","name":"Custom Python","language":"py","languageName":"Python"}
  ]' "$_REPORT_DATA_FILE" > "$f"
  run generate_html_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q '<h2>Quality Profiles</h2>' "$filepath"
  grep -q 'class="quality-profiles-table"' "$filepath"
  grep -q 'Custom Python' "$filepath"
  grep -q '>Java<' "$filepath"
  grep -q '>Python<' "$filepath"
}

@test "generate_html_report: omits quality profiles & gate name when absent (back-compat)" {
  run generate_html_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  # Assert on the rendered markup (the template keeps an HTML comment regardless).
  run grep -c '<h2>Quality Profiles</h2>' "$filepath"
  [ "$output" = "0" ]
  run grep -c 'qg-name' "$filepath"
  [ "$output" = "0" ]
}

@test "generate_html_report: shows 'no profiles' note when profiles enabled but empty" {
  local f; f=$(mktemp)
  jq '.metadata.qualityProfiles = []' "$_REPORT_DATA_FILE" > "$f"
  run generate_html_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q '<h2>Quality Profiles</h2>' "$filepath"
  grep -q 'No quality profiles found' "$filepath"
}

@test "generate_html_report: shows N/A gate name when enabled but empty" {
  local f; f=$(mktemp)
  jq '.metadata.qualityGateName = ""' "$_REPORT_DATA_FILE" > "$f"
  run generate_html_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'qg-name.*N/A' "$filepath"
}

@test "generate_html_report: escapes HTML in profile names" {
  local f; f=$(mktemp)
  jq '.metadata.qualityProfiles = [
    {"key":"k1","name":"A<b>&C","language":"java","languageName":"Java"}
  ]' "$_REPORT_DATA_FILE" > "$f"
  run generate_html_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local filepath="${lines[-1]}"
  grep -q 'A&lt;b&gt;&amp;C' "$filepath"
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

@test "write_summary_csv: includes Quality Gate Name row when present" {
  local f summary_csv
  f=$(mktemp); summary_csv=$(mktemp)
  jq '.metadata.qualityGateName = "Sonar way"' "$_REPORT_DATA_FILE" > "$f"
  run write_summary_csv "$f" "$summary_csv"
  [ "$status" -eq 0 ]
  grep -qF '"Quality Gate Name","Sonar way"' "$summary_csv"
  rm -f "$f" "$summary_csv"
}

@test "write_summary_csv: includes per-language quality profile rows when present" {
  local f summary_csv
  f=$(mktemp); summary_csv=$(mktemp)
  jq '.metadata.qualityProfiles = [
    {"key":"k1","name":"Sonar way","language":"java","languageName":"Java"},
    {"key":"k2","name":"Custom Python","language":"py","languageName":"Python"}
  ]' "$_REPORT_DATA_FILE" > "$f"
  run write_summary_csv "$f" "$summary_csv"
  [ "$status" -eq 0 ]
  grep -qF '"Quality Profile (Java)","Sonar way"' "$summary_csv"
  grep -qF '"Quality Profile (Python)","Custom Python"' "$summary_csv"
  rm -f "$f" "$summary_csv"
}

@test "write_summary_csv: omits quality rows when absent" {
  local summary_csv
  summary_csv=$(mktemp)
  write_summary_csv "$_REPORT_DATA_FILE" "$summary_csv"
  run grep -c 'Quality Gate Name' "$summary_csv"
  [ "$output" = "0" ]
  run grep -c 'Quality Profile' "$summary_csv"
  [ "$output" = "0" ]
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

@test "write_issues_csv: appends End Line and Why columns at right edge" {
  local issues_csv
  issues_csv=$(mktemp)
  run write_issues_csv "$_REPORT_DATA_FILE" "$issues_csv"
  [ "$status" -eq 0 ]

  # The header line must end with the new columns
  head -1 "$issues_csv" | grep -q '"End Line","Why"$'

  rm -f "$issues_csv"
}

@test "write_issues_csv: emits End Line value from .endLine when present" {
  local enriched
  enriched=$(mktemp)
  jq '.issues[0] += {endLine: 45, startLine: 42}' "$_REPORT_DATA_FILE" > "$enriched"

  local issues_csv
  issues_csv=$(mktemp)
  run write_issues_csv "$enriched" "$issues_csv"
  [ "$status" -eq 0 ]

  grep -q '"42","Null pointer dereference","30min","2024-01-15T10:00:00+0000","45"' "$issues_csv"

  rm -f "$enriched" "$issues_csv"
}

@test "write_issues_csv: emits Why from ruleDescription.whyText when enriched" {
  local enriched
  enriched=$(mktemp)
  jq '.issues[0] += {ruleDescription: {whyText: "Null reference risks NPE", whyTextShort: "Null reference risks NPE"}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  local issues_csv
  issues_csv=$(mktemp)
  run write_issues_csv "$enriched" "$issues_csv"
  [ "$status" -eq 0 ]

  grep -q '"Null reference risks NPE"' "$issues_csv"

  rm -f "$enriched" "$issues_csv"
}

@test "write_hotspots_csv: includes hotspot detail columns and review status" {
  local hotspots_csv
  hotspots_csv=$(mktemp)
  run write_hotspots_csv "$_REPORT_DATA_FILE" "$hotspots_csv"
  [ "$status" -eq 0 ]

  grep -q '"Key","Status","Resolution","Risk","Rule","Component","Line","Message","Category","Author","Creation Date","Update Date"' "$hotspots_csv"
  grep -q '"HS1","TO_REVIEW","","HIGH","java:S3649","my-project:src/Db.java","21","Unsanitized SQL query","sql-injection","dev1","2024-01-15T09:00:00+0000","2024-01-15T09:00:00+0000"' "$hotspots_csv"

  rm -f "$hotspots_csv"
}

@test "write_hotspots_csv: appends End Line and Risk Why columns at right edge" {
  local hotspots_csv
  hotspots_csv=$(mktemp)
  run write_hotspots_csv "$_REPORT_DATA_FILE" "$hotspots_csv"
  [ "$status" -eq 0 ]

  head -1 "$hotspots_csv" | grep -q '"End Line","Risk Why"$'

  rm -f "$hotspots_csv"
}

@test "write_hotspots_csv: emits Risk Why from ruleDescription.riskText when enriched" {
  local enriched
  enriched=$(mktemp)
  jq '.hotspots[0] += {ruleDescription: {riskText: "SQL injection possible"}}' \
    "$_REPORT_DATA_FILE" > "$enriched"

  local hotspots_csv
  hotspots_csv=$(mktemp)
  run write_hotspots_csv "$enriched" "$hotspots_csv"
  [ "$status" -eq 0 ]

  grep -q '"SQL injection possible"' "$hotspots_csv"

  rm -f "$enriched" "$hotspots_csv"
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
  grep -q '"Key","Status","Resolution","Risk","Rule","Component","Line","Message","Category","Author","Creation Date","Update Date"' "$hotspots_file"
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

# ===========================================================================
# generate_csv_report — error branches
# ===========================================================================

@test "generate_csv_report: fails when summary CSV write fails" {
  write_summary_csv() { return 1; }
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to generate CSV summary"* ]]
}

@test "generate_csv_report: fails when issues CSV write fails" {
  write_issues_csv() { return 1; }
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to generate CSV issues"* ]]
}

@test "generate_csv_report: fails when hotspots CSV write fails" {
  write_hotspots_csv() { return 1; }
  run generate_csv_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to generate CSV hotspots"* ]]
}

# ===========================================================================
# generate_pdf_report
# ===========================================================================

@test "generate_pdf_report: errors when html file is missing" {
  PATH="$_FAKE_BIN:$PATH" run generate_pdf_report "/no/such/file.html" "$_OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"HTML file not found"* ]]
}

@test "generate_pdf_report: converts html to pdf when wkhtmltopdf present" {
  local html="$_OUTPUT_DIR/in.html"
  printf '<html><head></head><body>hi</body></html>' > "$html"
  PATH="$_FAKE_BIN:$PATH" run generate_pdf_report "$html" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.pdf ]]
  [ -f "${lines[-1]}" ]
}

@test "generate_pdf_report: source HTML carries quality profiles (PDF inherits)" {
  local f; f=$(mktemp)
  jq '.metadata.qualityGateName = "Sonar way"
      | .metadata.qualityProfiles = [{"key":"k","name":"Sonar way","language":"java","languageName":"Java"}]' \
    "$_REPORT_DATA_FILE" > "$f"
  # The PDF is rendered from the HTML report, so verify the HTML source carries
  # the data, then confirm PDF generation consumes that HTML without error.
  run generate_html_report "$f" "$_OUTPUT_DIR"
  rm -f "$f"
  [ "$status" -eq 0 ]
  local html="${lines[-1]}"
  grep -q 'Quality Profiles' "$html"
  grep -q 'qg-name' "$html"
  PATH="$_FAKE_BIN:$PATH" run generate_pdf_report "$html" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "${lines[-1]}" == *.pdf ]]
}

@test "generate_pdf_report: reports failure when wkhtmltopdf fails" {
  local faildir; faildir=$(mktemp -d)
  printf '#!/usr/bin/env bash\nexit 1\n' > "$faildir/wkhtmltopdf"
  chmod +x "$faildir/wkhtmltopdf"
  local html="$_OUTPUT_DIR/in.html"
  printf '<html><head></head><body>x</body></html>' > "$html"
  PATH="$faildir:$PATH" run generate_pdf_report "$html" "$_OUTPUT_DIR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"wkhtmltopdf failed"* ]]
  rm -rf "$faildir"
}

# ===========================================================================
# generate_spreadsheet_report — skip + error branches
# ===========================================================================

@test "generate_spreadsheet_report: skips when converter is absent" {
  SSCONVERT_BIN="/nonexistent/ssconvert" run generate_spreadsheet_report \
    "$_REPORT_DATA_FILE" "$_OUTPUT_DIR" "xlsx"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "generate_spreadsheet_report: fails when summary sheet prep fails" {
  write_summary_csv() { return 1; }
  SSCONVERT_BIN="$_FAKE_BIN/ssconvert" run generate_spreadsheet_report \
    "$_REPORT_DATA_FILE" "$_OUTPUT_DIR" "xlsx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to prepare summary sheet"* ]]
}

@test "generate_spreadsheet_report: fails when issues sheet prep fails" {
  write_issues_csv() { return 1; }
  SSCONVERT_BIN="$_FAKE_BIN/ssconvert" run generate_spreadsheet_report \
    "$_REPORT_DATA_FILE" "$_OUTPUT_DIR" "xlsx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to prepare issues sheet"* ]]
}

@test "generate_spreadsheet_report: fails when hotspots sheet prep fails" {
  write_hotspots_csv() { return 1; }
  SSCONVERT_BIN="$_FAKE_BIN/ssconvert" run generate_spreadsheet_report \
    "$_REPORT_DATA_FILE" "$_OUTPUT_DIR" "xlsx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to prepare hotspots sheet"* ]]
}

@test "generate_spreadsheet_report: reports converter failure" {
  local faildir; faildir=$(mktemp -d)
  printf '#!/usr/bin/env bash\nexit 1\n' > "$faildir/ssconvert"
  chmod +x "$faildir/ssconvert"
  SSCONVERT_BIN="$faildir/ssconvert" run generate_spreadsheet_report \
    "$_REPORT_DATA_FILE" "$_OUTPUT_DIR" "xlsx"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to generate"* ]]
  rm -rf "$faildir"
}

# ===========================================================================
# generate_sarif_report
# ===========================================================================

@test "generate_sarif_report: creates a .sarif file in output dir" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [ -f "${lines[-1]}" ]
  [[ "${lines[-1]}" == *.sarif ]]
}

@test "generate_sarif_report: output is valid JSON with SARIF 2.1.0 envelope" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  run jq -e '.' "$f"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.version' "$f")" = "2.1.0" ]
  [ "$(jq -r '."$schema"' "$f")" = "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json" ]
  [ "$(jq '.runs | length' "$f")" -eq 1 ]
  [ "$(jq -r '.runs[0].tool.driver.name' "$f")" = "SonarQube Community Reporter" ]
}

@test "generate_sarif_report: emits one result per issue and TO_REVIEW hotspot" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  # 1 issue + 1 TO_REVIEW hotspot (the REVIEWED hotspot is excluded)
  [ "$(jq '.runs[0].results | length' "$f")" -eq 2 ]
}

@test "generate_sarif_report: excludes REVIEWED hotspots and their rules" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  # java:S5131 belongs only to the REVIEWED hotspot HS2 — must not appear
  [ "$(jq '[.runs[0].results[].ruleId] | index("java:S5131")' "$f")" = "null" ]
  [ "$(jq '[.runs[0].tool.driver.rules[].id] | index("java:S5131")' "$f")" = "null" ]
}

@test "generate_sarif_report: de-duplicates rules and ruleIndex resolves" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  # rule ids are unique
  [ "$(jq '.runs[0].tool.driver.rules | length' "$f")" = "$(jq '[.runs[0].tool.driver.rules[].id] | unique | length' "$f")" ]
  # every result's ruleIndex points at a rule whose id matches its ruleId
  [ "$(jq '[.runs[0] as $r | $r.results[] | $r.tool.driver.rules[.ruleIndex].id == .ruleId] | all' "$f")" = "true" ]
}

@test "generate_sarif_report: maps severity to SARIF level" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  # CRITICAL issue -> error
  [ "$(jq -r '.runs[0].results[] | select(.ruleId=="java:S2259") | .level' "$f")" = "error" ]
  # HIGH hotspot -> error
  [ "$(jq -r '.runs[0].results[] | select(.ruleId=="java:S3649") | .level' "$f")" = "error" ]
}

@test "generate_sarif_report: builds repo-relative uri and a region" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  local loc='.runs[0].results[] | select(.ruleId=="java:S2259") | .locations[0].physicalLocation'
  [ "$(jq -r "$loc.artifactLocation.uri" "$f")" = "src/Main.java" ]
  [ "$(jq "$loc.region.startLine" "$f")" -eq 42 ]
}

@test "generate_sarif_report: sets stable partialFingerprints from issue key" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  [ "$(jq -r '.runs[0].results[] | select(.ruleId=="java:S2259") | .partialFingerprints."sonarIssueKey/v1"' "$f")" = "AXyz111" ]
}

@test "generate_sarif_report: hotspot rule carries security-severity" {
  run generate_sarif_report "$_REPORT_DATA_FILE" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  [ "$(jq -r '.runs[0].tool.driver.rules[] | select(.id=="java:S3649") | .properties["security-severity"]' "$f")" = "8.0" ]
}

@test "generate_sarif_report: null-line finding omits region but keeps location" {
  local data; data=$(mktemp)
  jq '.issues = [{
        "key": "NL1", "severity": "MINOR", "type": "CODE_SMELL",
        "message": "Add a newline at end of file",
        "component": "my-project:src/Eof.java",
        "line": null, "startLine": null, "endLine": null,
        "rule": "java:S113", "effort": "1min", "creationDate": "2024-01-15T10:00:00+0000"
      }] | .hotspots = []' "$_REPORT_DATA_FILE" > "$data"
  run generate_sarif_report "$data" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  local loc='.runs[0].results[0].locations[0].physicalLocation'
  [ "$(jq -r "$loc.artifactLocation.uri" "$f")" = "src/Eof.java" ]
  [ "$(jq "$loc | has(\"region\")" "$f")" = "false" ]
  rm -f "$data"
}

@test "generate_sarif_report: empty issues and hotspots yield empty results" {
  local data; data=$(mktemp)
  jq '.issues = [] | .hotspots = []' "$_REPORT_DATA_FILE" > "$data"
  run generate_sarif_report "$data" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  local f="${lines[-1]}"
  [ "$(jq '.runs[0].results | length' "$f")" -eq 0 ]
  [ "$(jq '.runs[0].tool.driver.rules | length' "$f")" -eq 0 ]
  rm -f "$data"
}

@test "generate_sarif_report: drops fileless findings and warns" {
  local data; data=$(mktemp)
  jq '.issues = [{
        "key": "NF1", "severity": "MAJOR", "type": "CODE_SMELL",
        "message": "Project-level issue", "component": "",
        "line": null, "rule": "java:S0000", "creationDate": "2024-01-15T10:00:00+0000"
      }] | .hotspots = []' "$_REPORT_DATA_FILE" > "$data"
  run generate_sarif_report "$data" "$_OUTPUT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped 1 finding"* ]]
  local f="${lines[-1]}"
  [ "$(jq '.runs[0].results | length' "$f")" -eq 0 ]
  rm -f "$data"
}
