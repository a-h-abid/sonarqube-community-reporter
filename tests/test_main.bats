#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_main.bats — Unit tests for scripts/sonar-report.sh orchestration helpers
#
# Covers:
#   normalize_format, validate_report_formats, validate_params (dry-run mode)
#
# The main script is sourced under test; its main() entrypoint is guarded so it
# does not execute during these tests.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  # shellcheck source=../scripts/sonar-report.sh
  source "${REPO_ROOT}/scripts/sonar-report.sh"

  REQUESTED_FORMATS=()
  SONAR_PROJECT_KEYS=()
  REPORT_FORMATS="json"
  HTML_TEMPLATE=""
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY=""
  SONAR_URL="http://localhost:9000"
  SONAR_ORGANIZATION=""
  SONAR_CLOUD=false
  DRY_RUN_FILE=""
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  INCLUDE_QUALITY_PROFILES="false"
  INCLUDE_QUALITY_GATE_NAME="false"
}

@test "normalize_format: maps markdown alias to md" {
  run normalize_format " markdown "
  [ "$status" -eq 0 ]
  [ "$output" = "md" ]
}

@test "apply_defaults: returns success when values are already set" {
  SONAR_URL="http://example.com"
  SONAR_TOKEN="mytoken"
  SONAR_PROJECT_KEY="myproject"
  SONAR_CLOUD="false"
  REPORT_FORMATS="json,md"
  REPORT_OUTPUT_DIR="./reports"
  POLL_INTERVAL="5"
  POLL_TIMEOUT="300"
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  WAIT_FOR_ANALYSIS="false"
  FAIL_ON_GATE="false"

  run apply_defaults

  [ "$status" -eq 0 ]
}

@test "validate_report_formats: rejects unsupported formats" {
  REPORT_FORMATS="json,invalid"

  run validate_report_formats
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported report format: invalid"* ]]
}

@test "validate_report_formats: rejects empty formats" {
  REPORT_FORMATS="json,,html"

  run validate_report_formats
  [ "$status" -ne 0 ]
  [[ "$output" == *"Empty report format"* ]]
}

@test "validate_report_formats: normalizes aliases and removes duplicates" {
  REPORT_FORMATS="json, markdown, html, json"

  validate_report_formats

  [ "${#REQUESTED_FORMATS[@]}" -eq 3 ]
  [ "${REQUESTED_FORMATS[0]}" = "json" ]
  [ "${REQUESTED_FORMATS[1]}" = "md" ]
  [ "${REQUESTED_FORMATS[2]}" = "html" ]
}

@test "validate_report_formats: accepts csv format" {
  REPORT_FORMATS="csv"

  validate_report_formats

  [ "${#REQUESTED_FORMATS[@]}" -eq 1 ]
  [ "${REQUESTED_FORMATS[0]}" = "csv" ]
}

# ===========================================================================
# validate_params — dry-run mode
# ===========================================================================

@test "validate_params: dry-run mode accepts missing SONAR_TOKEN" {
  local tmp_file
  tmp_file=$(mktemp)
  echo '{"metadata":{"projectKey":"my-project"}}' > "$tmp_file"

  DRY_RUN_FILE="$tmp_file"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY="my-project"
  REPORT_FORMATS="json"

  # validate_params calls exit on failure; must not fail here
  validate_params
  [ "$?" -eq 0 ]

  rm -f "$tmp_file"
}

@test "validate_params: dry-run mode auto-populates project key from file" {
  local tmp_file
  tmp_file=$(mktemp)
  echo '{"metadata":{"projectKey":"auto-project"}}' > "$tmp_file"

  DRY_RUN_FILE="$tmp_file"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY=""
  REPORT_FORMATS="json"

  validate_params

  [ "$SONAR_PROJECT_KEY" = "auto-project" ]

  rm -f "$tmp_file"
}

@test "validate_params: dry-run mode fails when file does not exist" {
  DRY_RUN_FILE="/nonexistent/file.json"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY="my-project"
  REPORT_FORMATS="json"

  run validate_params
  [ "$status" -ne 0 ]
  [[ "$output" == *"Dry-run file not found"* ]]
}

@test "validate_params: dry-run mode fails when file is not valid JSON" {
  local tmp_file
  tmp_file=$(mktemp)
  echo "not json at all" > "$tmp_file"

  DRY_RUN_FILE="$tmp_file"
  SONAR_TOKEN=""
  SONAR_PROJECT_KEY="my-project"
  REPORT_FORMATS="json"

  run validate_params
  [ "$status" -ne 0 ]

  rm -f "$tmp_file"
}

# ===========================================================================
# parse_args / normalize_project_keys — multi-project (portfolio) keys
# ===========================================================================

@test "parse_args: single --project-key populates the keys array" {
  parse_args --project-key alpha
  [ "${#SONAR_PROJECT_KEYS[@]}" -eq 1 ]
  [ "${SONAR_PROJECT_KEYS[0]}" = "alpha" ]
}

@test "parse_args: repeated --project-key flags accumulate" {
  parse_args --project-key alpha --project-key beta --project-key gamma
  [ "${#SONAR_PROJECT_KEYS[@]}" -eq 3 ]
  [ "${SONAR_PROJECT_KEYS[0]}" = "alpha" ]
  [ "${SONAR_PROJECT_KEYS[2]}" = "gamma" ]
}

@test "parse_args: comma-separated --project-key splits into the array" {
  parse_args --project-key "alpha, beta ,gamma"
  [ "${#SONAR_PROJECT_KEYS[@]}" -eq 3 ]
  [ "${SONAR_PROJECT_KEYS[1]}" = "beta" ]
}

@test "parse_args: --project-keys alias and --project-key=VALUE form both work" {
  parse_args --project-keys "alpha,beta" --project-key=gamma
  [ "${#SONAR_PROJECT_KEYS[@]}" -eq 3 ]
  [ "${SONAR_PROJECT_KEYS[0]}" = "alpha" ]
  [ "${SONAR_PROJECT_KEYS[2]}" = "gamma" ]
}

@test "normalize_project_keys: seeds the array from a comma-separated scalar" {
  SONAR_PROJECT_KEY="alpha,beta"
  normalize_project_keys
  [ "${#SONAR_PROJECT_KEYS[@]}" -eq 2 ]
  [ "${SONAR_PROJECT_KEYS[0]}" = "alpha" ]
  # Scalar collapses to the first key for single-project code paths.
  [ "$SONAR_PROJECT_KEY" = "alpha" ]
}

@test "normalize_project_keys: CLI keys take precedence and set scalar to first" {
  SONAR_PROJECT_KEY="from-env"
  parse_args --project-key cli-a --project-key cli-b
  normalize_project_keys
  [ "${#SONAR_PROJECT_KEYS[@]}" -eq 2 ]
  [ "${SONAR_PROJECT_KEYS[0]}" = "cli-a" ]
  [ "$SONAR_PROJECT_KEY" = "cli-a" ]
}

# ===========================================================================
# parse_args — new flags
# ===========================================================================

@test "parse_args: --dry-run sets DRY_RUN_FILE" {
  local dry_run_file="${BATS_TEST_TMPDIR}/report.json"

  parse_args --dry-run "$dry_run_file" --project-key "p"
  [ "$DRY_RUN_FILE" = "$dry_run_file" ]
}

@test "parse_args: parses url, branch, task-id, and polling flags" {
  parse_args --url http://x:9000 --branch feat --task-id TASK123 \
    --no-wait --poll-interval 9 --poll-timeout 99 --project-key p
  [ "$SONAR_URL" = "http://x:9000" ]
  [ "$SONAR_BRANCH" = "feat" ]
  [ "$SONAR_TASK_ID" = "TASK123" ]
  [ "$WAIT_FOR_ANALYSIS" = "false" ]
  [ "$POLL_INTERVAL" = "9" ]
  [ "$POLL_TIMEOUT" = "99" ]
}

@test "parse_args: --notify-webhook sets NOTIFY_WEBHOOK" {
  parse_args --notify-webhook "https://hooks.example.com/abc" --project-key "p"
  [ "$NOTIFY_WEBHOOK" = "https://hooks.example.com/abc" ]
}

@test "parse_args: --sonarcloud sets SONAR_CLOUD to true" {
  parse_args --sonarcloud --project-key "p"
  [ "$SONAR_CLOUD" = "true" ]
}

@test "parse_args: --organization sets SONAR_ORGANIZATION" {
  parse_args --organization "my-org" --project-key "p"
  [ "$SONAR_ORGANIZATION" = "my-org" ]
}

@test "parse_args: --sonarcloud and --organization together" {
  parse_args --sonarcloud --organization "my-org" --project-key "p"
  [ "$SONAR_CLOUD" = "true" ]
  [ "$SONAR_ORGANIZATION" = "my-org" ]
}

# ===========================================================================
# validate_params — SonarCloud mode
# ===========================================================================

@test "validate_params: SonarCloud mode fails when SONAR_ORGANIZATION is empty" {
  SONAR_CLOUD=true
  SONAR_TOKEN="mytoken"
  SONAR_PROJECT_KEY="myproject"
  SONAR_ORGANIZATION=""
  REPORT_FORMATS="json"

  run validate_params
  [ "$status" -ne 0 ]
  [[ "$output" == *"SONAR_ORGANIZATION"* ]]
}

@test "validate_params: SonarCloud mode passes when SONAR_ORGANIZATION is set" {
  SONAR_CLOUD=true
  SONAR_TOKEN="mytoken"
  SONAR_PROJECT_KEY="myproject"
  SONAR_ORGANIZATION="my-org"
  REPORT_FORMATS="json"

  validate_params
  [ "$?" -eq 0 ]
}

@test "validate_params: auto-detects SonarCloud when URL contains sonarcloud.io" {
  SONAR_CLOUD=false
  SONAR_URL="https://sonarcloud.io"
  SONAR_TOKEN="mytoken"
  SONAR_PROJECT_KEY="myproject"
  SONAR_ORGANIZATION="my-org"
  REPORT_FORMATS="json"

  validate_params

  [ "$SONAR_CLOUD" = "true" ]
}

@test "validate_params: SONAR_CLOUD remains false for non-SonarCloud URL" {
  SONAR_CLOUD=false
  SONAR_URL="http://sonar.example.com"
  SONAR_TOKEN="mytoken"
  SONAR_PROJECT_KEY="myproject"
  SONAR_ORGANIZATION=""
  REPORT_FORMATS="json"

  validate_params

  [ "$SONAR_CLOUD" = "false" ]
}

# ===========================================================================
# parse_args — enrichment flags
# ===========================================================================

@test "parse_args: --include-rule-descriptions (bare) sets mode to short" {
  parse_args --include-rule-descriptions --project-key "p"
  [ "$INCLUDE_RULE_DESCRIPTIONS" = "short" ]
}

@test "parse_args: --include-rule-descriptions=full sets mode to full" {
  parse_args --include-rule-descriptions=full --project-key "p"
  [ "$INCLUDE_RULE_DESCRIPTIONS" = "full" ]
}

@test "parse_args: --include-rule-descriptions=short sets mode to short" {
  parse_args --include-rule-descriptions=short --project-key "p"
  [ "$INCLUDE_RULE_DESCRIPTIONS" = "short" ]
}

@test "parse_args: --include-code-snippets sets INCLUDE_CODE_SNIPPETS to true" {
  parse_args --include-code-snippets --project-key "p"
  [ "$INCLUDE_CODE_SNIPPETS" = "true" ]
}

@test "parse_args: --snippet-context sets SNIPPET_CONTEXT" {
  parse_args --snippet-context 5 --project-key "p"
  [ "$SNIPPET_CONTEXT" = "5" ]
}

@test "parse_args: --include-quality-profiles sets INCLUDE_QUALITY_PROFILES to true" {
  parse_args --include-quality-profiles --project-key "p"
  [ "$INCLUDE_QUALITY_PROFILES" = "true" ]
}

@test "parse_args: --include-quality-gate-name sets INCLUDE_QUALITY_GATE_NAME to true" {
  parse_args --include-quality-gate-name --project-key "p"
  [ "$INCLUDE_QUALITY_GATE_NAME" = "true" ]
}

@test "parse_args: --html-template sets HTML_TEMPLATE" {
  parse_args --html-template "/tmp/my.html.tpl" --project-key "p"
  [ "$HTML_TEMPLATE" = "/tmp/my.html.tpl" ]
}

@test "parse_args: --html-template=PATH form sets HTML_TEMPLATE" {
  parse_args --html-template=/tmp/eq.html.tpl --project-key "p"
  [ "$HTML_TEMPLATE" = "/tmp/eq.html.tpl" ]
}

@test "apply_defaults: defaults HTML_TEMPLATE to empty" {
  unset HTML_TEMPLATE
  apply_defaults
  [ "$HTML_TEMPLATE" = "" ]
}

# ===========================================================================
# apply_defaults — quality metadata flags
# ===========================================================================

@test "apply_defaults: defaults quality metadata flags to false" {
  unset INCLUDE_QUALITY_PROFILES INCLUDE_QUALITY_GATE_NAME
  apply_defaults
  [ "$INCLUDE_QUALITY_PROFILES" = "false" ]
  [ "$INCLUDE_QUALITY_GATE_NAME" = "false" ]
}

# ===========================================================================
# validate_enrichment_flags
# ===========================================================================

@test "validate_enrichment_flags: accepts empty mode (feature off)" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  run validate_enrichment_flags
  [ "$status" -eq 0 ]
}

@test "validate_enrichment_flags: accepts short and full modes" {
  INCLUDE_RULE_DESCRIPTIONS="short"
  validate_enrichment_flags
  [ "$?" -eq 0 ]

  INCLUDE_RULE_DESCRIPTIONS="full"
  validate_enrichment_flags
  [ "$?" -eq 0 ]
}

@test "validate_enrichment_flags: rejects invalid mode" {
  INCLUDE_RULE_DESCRIPTIONS="medium"
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  run validate_enrichment_flags
  [ "$status" -ne 0 ]
}

@test "validate_enrichment_flags: normalizes INCLUDE_CODE_SNIPPETS to true/false" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="yes"
  SNIPPET_CONTEXT="3"
  validate_enrichment_flags
  [ "$INCLUDE_CODE_SNIPPETS" = "true" ]

  INCLUDE_CODE_SNIPPETS="0"
  validate_enrichment_flags
  [ "$INCLUDE_CODE_SNIPPETS" = "false" ]
}

@test "validate_enrichment_flags: rejects invalid INCLUDE_CODE_SNIPPETS" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="banana"
  SNIPPET_CONTEXT="3"
  run validate_enrichment_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"INCLUDE_CODE_SNIPPETS"* ]]
}

@test "validate_enrichment_flags: rejects invalid INCLUDE_QUALITY_GATE_NAME" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  INCLUDE_QUALITY_GATE_NAME="perhaps"
  run validate_enrichment_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"INCLUDE_QUALITY_GATE_NAME"* ]]
}

@test "validate_enrichment_flags: rejects an unreadable HTML_TEMPLATE file" {
  if [ "$(id -u)" -eq 0 ]; then skip "root bypasses file permission checks"; fi
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  local tpl
  tpl=$(mktemp)
  echo "<html></html>" > "$tpl"
  chmod 000 "$tpl"
  HTML_TEMPLATE="$tpl"
  run validate_enrichment_flags
  chmod 644 "$tpl"; rm -f "$tpl"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not readable"* ]]
}

@test "validate_report_formats: rejects empty REPORT_FORMATS" {
  REPORT_FORMATS=""
  run validate_report_formats
  [ "$status" -ne 0 ]
  [[ "$output" == *"At least one"* ]]
}

@test "validate_enrichment_flags: rejects non-numeric SNIPPET_CONTEXT" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="abc"
  run validate_enrichment_flags
  [ "$status" -ne 0 ]
}

@test "validate_enrichment_flags: clamps very large SNIPPET_CONTEXT to 50" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="9999"
  validate_enrichment_flags
  [ "$SNIPPET_CONTEXT" = "50" ]
}

@test "validate_enrichment_flags: normalizes INCLUDE_QUALITY_PROFILES to true/false" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  INCLUDE_QUALITY_PROFILES="yes"
  validate_enrichment_flags
  [ "$INCLUDE_QUALITY_PROFILES" = "true" ]

  INCLUDE_QUALITY_PROFILES="off"
  validate_enrichment_flags
  [ "$INCLUDE_QUALITY_PROFILES" = "false" ]
}

@test "validate_enrichment_flags: normalizes INCLUDE_QUALITY_GATE_NAME to true/false" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  INCLUDE_QUALITY_GATE_NAME="1"
  validate_enrichment_flags
  [ "$INCLUDE_QUALITY_GATE_NAME" = "true" ]
}

@test "validate_enrichment_flags: rejects invalid INCLUDE_QUALITY_PROFILES" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  INCLUDE_QUALITY_PROFILES="maybe"
  run validate_enrichment_flags
  [ "$status" -ne 0 ]
}

@test "validate_enrichment_flags: accepts empty HTML_TEMPLATE" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  HTML_TEMPLATE=""
  run validate_enrichment_flags
  [ "$status" -eq 0 ]
}

@test "validate_enrichment_flags: accepts a readable HTML_TEMPLATE file" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  local tpl
  tpl=$(mktemp)
  echo "<html></html>" > "$tpl"
  HTML_TEMPLATE="$tpl"
  run validate_enrichment_flags
  rm -f "$tpl"
  [ "$status" -eq 0 ]
}

@test "validate_enrichment_flags: rejects a missing HTML_TEMPLATE file" {
  INCLUDE_RULE_DESCRIPTIONS=""
  INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"
  HTML_TEMPLATE="/no/such/template-xyz.tpl"
  run validate_enrichment_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"HTML template"* ]]
}
