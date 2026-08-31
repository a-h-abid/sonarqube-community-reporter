#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_trend.bats — Unit tests for scripts/lib/trend.sh
#
# Covers:
#   validate_baseline_file, compute_trend, apply_trend, trend_has_regression,
#   log_trend_summary, plus trend rendering in the Markdown / HTML / CSV
#   generators and the --compare-with / --fail-on-regression CLI wiring.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

# shellcheck source=helpers.bash
load 'helpers'

setup() {
  # shellcheck source=../scripts/lib/trend.sh
  source "${REPO_ROOT}/scripts/lib/trend.sh"

  TEST_TMP=$(mktemp -d)
  BASELINE="${TEST_TMP}/baseline.json"
  CURRENT="${TEST_TMP}/current.json"
  cp "${FIXTURES}/report_data.json" "$BASELINE"
  cp "${FIXTURES}/report_data.json" "$CURRENT"
}

teardown() {
  [[ -n "${TEST_TMP:-}" ]] && rm -rf "$TEST_TMP"
}

# Rewrites $CURRENT through the given jq filter.
mutate_current() {
  jq "$1" "$CURRENT" > "${CURRENT}.new" && mv "${CURRENT}.new" "$CURRENT"
}

# Prints the .trend object computed for $CURRENT against $BASELINE.
trend_of() {
  compute_trend "$CURRENT" "$BASELINE" | jq '.trend'
}

# ===========================================================================
# validate_baseline_file
# ===========================================================================

@test "validate_baseline_file: accepts a saved report data file" {
  run validate_baseline_file "$BASELINE"
  [ "$status" -eq 0 ]
}

@test "validate_baseline_file: fails when the file does not exist" {
  run validate_baseline_file "${TEST_TMP}/missing.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "validate_baseline_file: fails on invalid JSON" {
  echo "not json {" > "${TEST_TMP}/bad.json"
  run validate_baseline_file "${TEST_TMP}/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid report data JSON"* ]]
}

@test "validate_baseline_file: fails when JSON is not an object" {
  echo '[1,2,3]' > "${TEST_TMP}/arr.json"
  run validate_baseline_file "${TEST_TMP}/arr.json"
  [ "$status" -eq 1 ]
}

# ===========================================================================
# compute_trend — metric deltas
# ===========================================================================

@test "compute_trend: identical reports produce zero deltas" {
  local deltas
  deltas=$(trend_of | jq -r '[.metrics[].delta] | unique | @csv')
  [ "$deltas" = "0" ]
}

@test "compute_trend: higher bug count is an upward regression" {
  mutate_current '.measures.bugs = "7"'
  local entry
  entry=$(trend_of | jq -c '.metrics.bugs')
  [ "$(jq -r '.previous' <<<"$entry")" = "2" ]
  [ "$(jq -r '.current' <<<"$entry")" = "7" ]
  [ "$(jq -r '.delta' <<<"$entry")" = "5" ]
  [ "$(jq -r '.indicator' <<<"$entry")" = "↑" ]
  [ "$(jq -r '.regressed' <<<"$entry")" = "true" ]
  [ "$(jq -r '.improved' <<<"$entry")" = "false" ]
}

@test "compute_trend: fewer vulnerabilities is an improvement" {
  mutate_current '.measures.vulnerabilities = "0"'
  local entry
  entry=$(trend_of | jq -c '.metrics.vulnerabilities')
  [ "$(jq -r '.delta' <<<"$entry")" = "-1" ]
  [ "$(jq -r '.indicator' <<<"$entry")" = "↓" ]
  [ "$(jq -r '.improved' <<<"$entry")" = "true" ]
  [ "$(jq -r '.regressed' <<<"$entry")" = "false" ]
}

@test "compute_trend: dropping coverage is a regression (lower is worse)" {
  mutate_current '.measures.coverage = "70.5"'
  local entry
  entry=$(trend_of | jq -c '.metrics.coverage')
  [ "$(jq -r '.delta' <<<"$entry")" = "-8" ]
  [ "$(jq -r '.regressed' <<<"$entry")" = "true" ]
}

@test "compute_trend: rising coverage is an improvement" {
  mutate_current '.measures.coverage = "90"'
  local entry
  entry=$(trend_of | jq -c '.metrics.coverage')
  [ "$(jq -r '.improved' <<<"$entry")" = "true" ]
  [ "$(jq -r '.indicator' <<<"$entry")" = "↑" ]
}

@test "compute_trend: growing technical debt is a regression" {
  mutate_current '.measures.sqale_index = "300"'
  local entry
  entry=$(trend_of | jq -c '.metrics.sqale_index')
  [ "$(jq -r '.delta' <<<"$entry")" = "180" ]
  [ "$(jq -r '.regressed' <<<"$entry")" = "true" ]
}

@test "compute_trend: growing duplication is a regression" {
  mutate_current '.measures.duplicated_lines_density = "9.4"'
  local entry
  entry=$(trend_of | jq -c '.metrics.duplicated_lines_density')
  [ "$(jq -r '.delta' <<<"$entry")" = "6.2" ]
  [ "$(jq -r '.regressed' <<<"$entry")" = "true" ]
}

@test "compute_trend: unchanged metric renders the neutral indicator" {
  local entry
  entry=$(trend_of | jq -c '.metrics.code_smells')
  [ "$(jq -r '.direction' <<<"$entry")" = "same" ]
  [ "$(jq -r '.indicator' <<<"$entry")" = "→" ]
}

@test "compute_trend: non-numeric measure yields an unknown delta" {
  mutate_current '.measures.coverage = "N/A"'
  local entry
  entry=$(trend_of | jq -c '.metrics.coverage')
  [ "$(jq -r '.delta' <<<"$entry")" = "null" ]
  [ "$(jq -r '.direction' <<<"$entry")" = "unknown" ]
  [ "$(jq -r '.indicator' <<<"$entry")" = "—" ]
  [ "$(jq -r '.regressed' <<<"$entry")" = "false" ]
}

@test "compute_trend: missing measure in the baseline yields an unknown delta" {
  jq 'del(.measures.bugs)' "$BASELINE" > "${BASELINE}.new" && mv "${BASELINE}.new" "$BASELINE"
  local entry
  entry=$(trend_of | jq -c '.metrics.bugs')
  [ "$(jq -r '.previous' <<<"$entry")" = "null" ]
  [ "$(jq -r '.direction' <<<"$entry")" = "unknown" ]
}

@test "compute_trend: reports all six tracked metrics" {
  local keys
  keys=$(trend_of | jq -r '.metrics | keys_unsorted | join(",")')
  [ "$keys" = "bugs,vulnerabilities,code_smells,coverage,duplicated_lines_density,sqale_index" ]
}

@test "compute_trend: records baseline provenance" {
  local baseline_node
  baseline_node=$(trend_of | jq -c '.baseline')
  [ "$(jq -r '.file' <<<"$baseline_node")" = "$BASELINE" ]
  [ "$(jq -r '.projectKey' <<<"$baseline_node")" = "my-project" ]
}

# ===========================================================================
# compute_trend — quality gate
# ===========================================================================

@test "compute_trend: gate OK → ERROR is a regression" {
  mutate_current '.qualityGate.status = "ERROR"'
  local gate
  gate=$(trend_of | jq -c '.qualityGate')
  [ "$(jq -r '.previous' <<<"$gate")" = "OK" ]
  [ "$(jq -r '.current' <<<"$gate")" = "ERROR" ]
  [ "$(jq -r '.changed' <<<"$gate")" = "true" ]
  [ "$(jq -r '.regressed' <<<"$gate")" = "true" ]
}

@test "compute_trend: gate ERROR → OK is an improvement" {
  jq '.qualityGate.status = "ERROR"' "$BASELINE" > "${BASELINE}.new" && mv "${BASELINE}.new" "$BASELINE"
  local gate
  gate=$(trend_of | jq -c '.qualityGate')
  [ "$(jq -r '.improved' <<<"$gate")" = "true" ]
  [ "$(jq -r '.regressed' <<<"$gate")" = "false" ]
}

@test "compute_trend: unchanged gate is neither improved nor regressed" {
  local gate
  gate=$(trend_of | jq -c '.qualityGate')
  [ "$(jq -r '.changed' <<<"$gate")" = "false" ]
  [ "$(jq -r '.improved' <<<"$gate")" = "false" ]
  [ "$(jq -r '.regressed' <<<"$gate")" = "false" ]
}

@test "compute_trend: absent gate status falls back to UNKNOWN" {
  jq 'del(.qualityGate)' "$BASELINE" > "${BASELINE}.new" && mv "${BASELINE}.new" "$BASELINE"
  local gate
  gate=$(trend_of | jq -c '.qualityGate')
  [ "$(jq -r '.previous' <<<"$gate")" = "UNKNOWN" ]
}

# ===========================================================================
# compute_trend — issues
# ===========================================================================

@test "compute_trend: counts new issue keys" {
  mutate_current '.issues += [{"key": "NEW1"}, {"key": "NEW2"}]'
  local issues
  issues=$(trend_of | jq -c '.issues')
  [ "$(jq -r '.new' <<<"$issues")" = "2" ]
  [ "$(jq -r '.fixed' <<<"$issues")" = "0" ]
  [ "$(jq -r '.newKeys | join(",")' <<<"$issues")" = "NEW1,NEW2" ]
}

@test "compute_trend: counts fixed issue keys" {
  mutate_current '.issues = []'
  local issues
  issues=$(trend_of | jq -c '.issues')
  [ "$(jq -r '.new' <<<"$issues")" = "0" ]
  [ "$(jq -r '.fixed' <<<"$issues")" = "1" ]
  [ "$(jq -r '.fixedKeys | join(",")' <<<"$issues")" = "AXyz111" ]
}

@test "compute_trend: counts issues present in both datasets as unchanged" {
  local issues
  issues=$(trend_of | jq -c '.issues')
  [ "$(jq -r '.unchanged' <<<"$issues")" = "1" ]
  [ "$(jq -r '.new' <<<"$issues")" = "0" ]
}

@test "compute_trend: new issues alone do not flag a regression" {
  mutate_current '.issues += [{"key": "NEW1"}]'
  [ "$(trend_of | jq -r '.regression')" = "false" ]
}

# ===========================================================================
# compute_trend — regression rollup
# ===========================================================================

@test "compute_trend: no regression when nothing worsened" {
  [ "$(trend_of | jq -r '.regression')" = "false" ]
}

@test "compute_trend: regression when a metric worsened" {
  mutate_current '.measures.code_smells = "40"'
  [ "$(trend_of | jq -r '.regression')" = "true" ]
}

@test "compute_trend: regression when the gate turned to ERROR" {
  mutate_current '.qualityGate.status = "ERROR"'
  [ "$(trend_of | jq -r '.regression')" = "true" ]
}

@test "compute_trend: improvements alone do not flag a regression" {
  mutate_current '.measures.bugs = "0" | .measures.coverage = "99"'
  [ "$(trend_of | jq -r '.regression')" = "false" ]
}

@test "compute_trend: fails when the baseline is unreadable" {
  run compute_trend "$CURRENT" "${TEST_TMP}/missing.json"
  [ "$status" -eq 1 ]
}

# ===========================================================================
# apply_trend / trend_has_regression / log_trend_summary
# ===========================================================================

@test "apply_trend: writes an enriched copy and leaves the input untouched" {
  local before
  before=$(md5sum < "$CURRENT")

  local out
  out=$(apply_trend "$CURRENT" "$BASELINE")
  [ -f "$out" ]
  [ "$out" != "$CURRENT" ]
  [ "$(jq -r '.trend | type' "$out")" = "object" ]
  [ "$(jq -r '.metadata.projectKey' "$out")" = "my-project" ]
  [ "$(jq -r 'has("trend")' "$CURRENT")" = "false" ]
  [ "$(md5sum < "$CURRENT")" = "$before" ]
  rm -f "$out"
}

@test "apply_trend: leaves the baseline file unmodified" {
  local before
  before=$(md5sum < "$BASELINE")
  local out
  out=$(apply_trend "$CURRENT" "$BASELINE")
  [ "$(md5sum < "$BASELINE")" = "$before" ]
  rm -f "$out"
}

@test "apply_trend: fails when the baseline is missing" {
  run apply_trend "$CURRENT" "${TEST_TMP}/missing.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "trend_has_regression: true when the trend reports a regression" {
  mutate_current '.qualityGate.status = "ERROR"'
  local out
  out=$(apply_trend "$CURRENT" "$BASELINE")
  run trend_has_regression "$out"
  [ "$status" -eq 0 ]
  rm -f "$out"
}

@test "trend_has_regression: false when there is no regression" {
  local out
  out=$(apply_trend "$CURRENT" "$BASELINE")
  run trend_has_regression "$out"
  [ "$status" -ne 0 ]
  rm -f "$out"
}

@test "trend_has_regression: false when no trend was computed" {
  run trend_has_regression "$CURRENT"
  [ "$status" -ne 0 ]
}

@test "log_trend_summary: logs baseline, gate, metrics and issue counts" {
  mutate_current '.measures.bugs = "9"'
  local out
  out=$(apply_trend "$CURRENT" "$BASELINE")
  run log_trend_summary "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Trend baseline:"* ]]
  [[ "$output" == *"Quality gate: OK"* ]]
  [[ "$output" == *"Bugs ↑ 7"* ]]
  [[ "$output" == *"Issues: 0 new, 0 fixed"* ]]
  rm -f "$out"
}

@test "log_trend_summary: prints nothing without a trend object" {
  run log_trend_summary "$CURRENT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ===========================================================================
# Report rendering
# ===========================================================================

@test "markdown report: renders the trend section when trend data is present" {
  # shellcheck source=../scripts/lib/report-md.sh
  source "${REPO_ROOT}/scripts/lib/report-md.sh"
  mutate_current '.measures.bugs = "9" | .qualityGate.status = "ERROR"'
  local enriched
  enriched=$(apply_trend "$CURRENT" "$BASELINE")

  run generate_md_report "$enriched" "${TEST_TMP}/out"
  [ "$status" -eq 0 ]

  local md="${output##*$'\n'}"
  grep -q "## Trend / Changes since last report" "$md"
  grep -q "| \*\*Bugs\*\* | 2 | 9 | ↑ +7 |" "$md"
  grep -q "❌ regressed" "$md"
  grep -q "Regression detected" "$md"
  rm -f "$enriched"
}

@test "markdown report: omits the trend section without a baseline" {
  # shellcheck source=../scripts/lib/report-md.sh
  source "${REPO_ROOT}/scripts/lib/report-md.sh"
  run generate_md_report "$CURRENT" "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local md="${output##*$'\n'}"
  ! grep -q "Trend / Changes since last report" "$md"
}

@test "html report: renders the trend table and no leftover placeholder" {
  # shellcheck source=../scripts/lib/report-html.sh
  source "${REPO_ROOT}/scripts/lib/report-html.sh"
  mutate_current '.measures.coverage = "60"'
  local enriched
  enriched=$(apply_trend "$CURRENT" "$BASELINE")

  run generate_html_report "$enriched" "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local html="${output##*$'\n'}"
  grep -q "<h2>Trend / Changes since last report</h2>" "$html"
  grep -q "trend-worse" "$html"
  ! grep -q "{{TREND_SECTION}}" "$html"
  rm -f "$enriched"
}

@test "html report: drops the trend placeholder when no baseline is given" {
  # shellcheck source=../scripts/lib/report-html.sh
  source "${REPO_ROOT}/scripts/lib/report-html.sh"
  run generate_html_report "$CURRENT" "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local html="${output##*$'\n'}"
  ! grep -q "{{TREND_SECTION}}" "$html"
  ! grep -q "<h2>Trend / Changes since last report</h2>" "$html"
}

@test "csv summary: adds trend rows only when trend data is present" {
  # shellcheck source=../scripts/lib/report-spreadsheet.sh
  source "${REPO_ROOT}/scripts/lib/report-spreadsheet.sh"
  mutate_current '.measures.bugs = "9"'
  local enriched
  enriched=$(apply_trend "$CURRENT" "$BASELINE")

  write_summary_csv "$enriched" "${TEST_TMP}/with.csv"
  grep -q "Trend / Changes since last report" "${TEST_TMP}/with.csv"
  grep -q '"Trend Bugs","↑ +7"' "${TEST_TMP}/with.csv"
  grep -q '"Trend Regression","yes"' "${TEST_TMP}/with.csv"

  write_summary_csv "$CURRENT" "${TEST_TMP}/without.csv"
  ! grep -q "Trend" "${TEST_TMP}/without.csv"
  rm -f "$enriched"
}

@test "json report: carries the trend object through untouched" {
  # shellcheck source=../scripts/lib/report-json.sh
  source "${REPO_ROOT}/scripts/lib/report-json.sh"
  local enriched
  enriched=$(apply_trend "$CURRENT" "$BASELINE")

  run generate_json_report "$enriched" "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local json="${output##*$'\n'}"
  [ "$(jq -r '.trend.baseline.projectKey' "$json")" = "my-project" ]
  rm -f "$enriched"
}

# ===========================================================================
# Configuration wiring
# ===========================================================================

@test "config: COMPARE_WITH and FAIL_ON_REGRESSION are allowed keys" {
  # shellcheck source=../scripts/lib/config.sh
  source "${REPO_ROOT}/scripts/lib/config.sh"
  run is_allowed_key "COMPARE_WITH"
  [ "$status" -eq 0 ]
  run is_allowed_key "FAIL_ON_REGRESSION"
  [ "$status" -eq 0 ]
}

@test "config: YAML options map to the trend variables" {
  # shellcheck source=../scripts/lib/config.sh
  source "${REPO_ROOT}/scripts/lib/config.sh"
  run yaml_key_to_env_var "options" "compare_with"
  [ "$output" = "COMPARE_WITH" ]
  run yaml_key_to_env_var "options" "fail_on_regression"
  [ "$output" = "FAIL_ON_REGRESSION" ]
}

# ===========================================================================
# CLI end-to-end (dry-run)
# ===========================================================================

run_cli() {
  run env -u COMPARE_WITH -u FAIL_ON_REGRESSION \
    bash "${REPO_ROOT}/scripts/sonar-report.sh" "$@"
}

@test "cli: --compare-with injects the trend into the JSON report" {
  mutate_current '.measures.bugs = "9"'
  run_cli --dry-run "$CURRENT" --compare-with "$BASELINE" \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local json
  json=$(find "${TEST_TMP}/out" -name '*.json' | head -1)
  [ "$(jq -r '.trend.metrics.bugs.delta' "$json")" = "7" ]
}

@test "cli: no trend is added without --compare-with" {
  run_cli --dry-run "$CURRENT" --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local json
  json=$(find "${TEST_TMP}/out" -name '*.json' | head -1)
  [ "$(jq -r 'has("trend")' "$json")" = "false" ]
}

@test "cli: --fail-on-regression exits 1 on a regression" {
  mutate_current '.measures.bugs = "9"'
  run_cli --dry-run "$CURRENT" --compare-with "$BASELINE" --fail-on-regression \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"regressed against the baseline"* ]]
}

@test "cli: --fail-on-regression exits 0 when nothing worsened" {
  mutate_current '.measures.bugs = "0"'
  run_cli --dry-run "$CURRENT" --compare-with "$BASELINE" --fail-on-regression \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
}

@test "cli: a regression without --fail-on-regression still exits 0" {
  mutate_current '.measures.bugs = "9"'
  run_cli --dry-run "$CURRENT" --compare-with "$BASELINE" \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
}

@test "cli: errors when the baseline file does not exist" {
  run_cli --dry-run "$CURRENT" --compare-with "${TEST_TMP}/missing.json" \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Baseline report file not found"* ]]
}

@test "cli: errors when the baseline is not valid JSON" {
  echo "nope {" > "${TEST_TMP}/bad.json"
  run_cli --dry-run "$CURRENT" --compare-with "${TEST_TMP}/bad.json" \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid report data JSON"* ]]
}

@test "cli: --compare-with=PATH form is accepted" {
  run_cli --dry-run "$CURRENT" "--compare-with=${BASELINE}" \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local json
  json=$(find "${TEST_TMP}/out" -name '*.json' | head -1)
  [ "$(jq -r '.trend | type' "$json")" = "object" ]
}

@test "cli: COMPARE_WITH environment variable is honored" {
  run env -u FAIL_ON_REGRESSION COMPARE_WITH="$BASELINE" \
    bash "${REPO_ROOT}/scripts/sonar-report.sh" \
    --dry-run "$CURRENT" --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  local json
  json=$(find "${TEST_TMP}/out" -name '*.json' | head -1)
  [ "$(jq -r '.trend | type' "$json")" = "object" ]
}

@test "cli: --fail-on-regression without a baseline warns and is ignored" {
  run_cli --dry-run "$CURRENT" --fail-on-regression \
    --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no effect without --compare-with"* ]]
}

@test "cli: invalid FAIL_ON_REGRESSION value is rejected" {
  run env -u COMPARE_WITH FAIL_ON_REGRESSION="maybe" \
    bash "${REPO_ROOT}/scripts/sonar-report.sh" \
    --dry-run "$CURRENT" --formats json --output-dir "${TEST_TMP}/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid FAIL_ON_REGRESSION"* ]]
}

@test "cli: --help documents the trend flags" {
  run_cli --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--compare-with"* ]]
  [[ "$output" == *"--fail-on-regression"* ]]
}
