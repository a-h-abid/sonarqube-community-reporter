#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_config.bats — Unit tests for scripts/lib/config.sh
#
# Covers:
#   is_allowed_key, sanitize_value, set_config_var,
#   parse_shell_config, parse_yaml_config, load_config_file
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

# shellcheck source=helpers.bash
load 'helpers'

setup() {
  # Source api.sh first (for logging functions)
  # shellcheck source=../scripts/lib/api.sh
  source "${REPO_ROOT}/scripts/lib/api.sh"

  # Source config.sh — provides all functions under test
  # shellcheck source=../scripts/lib/config.sh
  source "${REPO_ROOT}/scripts/lib/config.sh"

  # Unset all config vars to test clean loading
  unset SONAR_URL SONAR_TOKEN SONAR_PROJECT_KEY SONAR_BRANCH SONAR_ORGANIZATION
  unset SONAR_CLOUD SONAR_TASK_ID REPORT_FORMATS REPORT_OUTPUT_DIR HTML_TEMPLATE
  unset POLL_INTERVAL POLL_TIMEOUT ANALYSIS_ID DRY_RUN_FILE NOTIFY_WEBHOOK
  unset INCLUDE_RULE_DESCRIPTIONS INCLUDE_CODE_SNIPPETS SNIPPET_CONTEXT
  unset INCLUDE_QUALITY_PROFILES INCLUDE_QUALITY_GATE_NAME
}

# ==============================================================================
# is_allowed_key tests
# ==============================================================================
@test "is_allowed_key: accepts SONAR_URL" {
  run is_allowed_key "SONAR_URL"
  [ "$status" -eq 0 ]
}

@test "is_allowed_key: accepts REPORT_FORMATS" {
  run is_allowed_key "REPORT_FORMATS"
  [ "$status" -eq 0 ]
}

@test "is_allowed_key: accepts INCLUDE_QUALITY_PROFILES" {
  run is_allowed_key "INCLUDE_QUALITY_PROFILES"
  [ "$status" -eq 0 ]
}

@test "is_allowed_key: accepts INCLUDE_QUALITY_GATE_NAME" {
  run is_allowed_key "INCLUDE_QUALITY_GATE_NAME"
  [ "$status" -eq 0 ]
}

@test "is_allowed_key: rejects UNKNOWN_KEY" {
  run is_allowed_key "UNKNOWN_KEY"
  [ "$status" -ne 0 ]
}

@test "is_allowed_key: rejects empty key" {
  run is_allowed_key ""
  [ "$status" -ne 0 ]
}

# ==============================================================================
# sanitize_value tests
# ==============================================================================
@test "sanitize_value: returns clean value unchanged" {
  run sanitize_value "http://localhost:9000"
  [ "$status" -eq 0 ]
  [ "$output" = "http://localhost:9000" ]
}

# ==============================================================================
# set_config_var tests
# ==============================================================================
@test "set_config_var: sets allowed variable when not already set" {
  set_config_var "SONAR_URL" "http://test.example.com"
  [ "$SONAR_URL" = "http://test.example.com" ]
}

@test "set_config_var: does not override existing env var" {
  export SONAR_URL="http://existing.example.com"
  set_config_var "SONAR_URL" "http://new.example.com"
  [ "$SONAR_URL" = "http://existing.example.com" ]
}

# ==============================================================================
# parse_shell_config tests
# ==============================================================================
@test "parse_shell_config: loads shell config file" {
  parse_shell_config "${FIXTURES}/test_config.conf"
  [ "$SONAR_URL" = "http://test.example.com:9000" ]
  [ "$SONAR_TOKEN" = "test_token_12345" ]
  [ "$SONAR_PROJECT_KEY" = "test-project" ]
  [ "$SONAR_BRANCH" = "feature/test" ]
  [ "$REPORT_FORMATS" = "json,md" ]
  [ "$REPORT_OUTPUT_DIR" = "/tmp/test-reports" ]
  [ "$POLL_INTERVAL" = "10" ]
  [ "$POLL_TIMEOUT" = "600" ]
  [ "$INCLUDE_RULE_DESCRIPTIONS" = "short" ]
  [ "$INCLUDE_CODE_SNIPPETS" = "true" ]
  [ "$SNIPPET_CONTEXT" = "5" ]
}

@test "parse_shell_config: fails on nonexistent file" {
  run parse_shell_config "/tmp/nonexistent-config.conf"
  [ "$status" -ne 0 ]
}

@test "parse_shell_config: respects env vars (does not override)" {
  export SONAR_URL="http://env.example.com"
  parse_shell_config "${FIXTURES}/test_config.conf"
  [ "$SONAR_URL" = "http://env.example.com" ]
}

# ==============================================================================
# parse_yaml_config tests
# ==============================================================================
@test "parse_yaml_config: loads YAML config file" {
  parse_yaml_config "${FIXTURES}/test_config.yml"
  [ "$SONAR_URL" = "http://yaml-test.example.com:9000" ]
  [ "$SONAR_TOKEN" = "yaml_token_67890" ]
  [ "$SONAR_PROJECT_KEY" = "yaml-test-project" ]
  [ "$SONAR_BRANCH" = "main" ]
  [ "$SONAR_ORGANIZATION" = "test-org" ]
  [ "$SONAR_CLOUD" = "false" ]
  [ "$REPORT_FORMATS" = "html,pdf" ]
  [ "$REPORT_OUTPUT_DIR" = "/tmp/yaml-reports" ]
  [ "$POLL_INTERVAL" = "15" ]
  [ "$POLL_TIMEOUT" = "900" ]
  [ "$INCLUDE_RULE_DESCRIPTIONS" = "full" ]
  [ "$INCLUDE_CODE_SNIPPETS" = "true" ]
  [ "$SNIPPET_CONTEXT" = "7" ]
  [ "$DRY_RUN_FILE" = "/tmp/dry-run.json" ]
  [ "$NOTIFY_WEBHOOK" = "https://hooks.example.com/webhook" ]
}

@test "parse_yaml_config: fails on nonexistent file" {
  run parse_yaml_config "/tmp/nonexistent-config.yml"
  [ "$status" -ne 0 ]
}

@test "parse_yaml_config: respects env vars (does not override)" {
  export SONAR_URL="http://env.example.com"
  parse_yaml_config "${FIXTURES}/test_config.yml"
  [ "$SONAR_URL" = "http://env.example.com" ]
}

@test "parse_yaml_config: maps report.html_template into HTML_TEMPLATE" {
  local cfg
  cfg=$(mktemp)
  cat > "$cfg" <<'YML'
report:
  html_template: ./my-branding/report.html.tpl
YML
  parse_yaml_config "$cfg"
  rm -f "$cfg"
  [ "$HTML_TEMPLATE" = "./my-branding/report.html.tpl" ]
}

# ==============================================================================
# load_config_file tests
# ==============================================================================
@test "load_config_file: loads explicit shell config file" {
  load_config_file "" "${FIXTURES}/test_config.conf"
  [ "$SONAR_URL" = "http://test.example.com:9000" ]
}

@test "load_config_file: loads explicit YAML config file" {
  load_config_file "" "${FIXTURES}/test_config.yml"
  [ "$SONAR_URL" = "http://yaml-test.example.com:9000" ]
}

@test "load_config_file: fails when explicit file does not exist" {
  run load_config_file "" "/tmp/nonexistent.yml"
  [ "$status" -ne 0 ]
}

@test "load_config_file: succeeds when no config file found (auto-detect)" {
  # Create a temporary directory with no config files
  local tmpdir
  tmpdir=$(mktemp -d)
  load_config_file "$tmpdir"
  rm -rf "$tmpdir"
}

@test "load_config_file: prefers YAML over shell config" {
  # Create a temp directory with both config files
  local tmpdir
  tmpdir=$(mktemp -d)

  cat >"${tmpdir}/sonar-report.conf" <<EOF
SONAR_PROJECT_KEY=shell-config
EOF

  cat >"${tmpdir}/.sonar-report.yml" <<EOF
sonar:
  project_key: yaml-config
EOF

  load_config_file "$tmpdir"
  [ "$SONAR_PROJECT_KEY" = "yaml-config" ]
  rm -rf "$tmpdir"
}

# ==============================================================================
# yaml_key_to_env_var tests
# ==============================================================================
@test "yaml_key_to_env_var: maps sonar.url to SONAR_URL" {
  run yaml_key_to_env_var "sonar" "url"
  [ "$status" -eq 0 ]
  [ "$output" = "SONAR_URL" ]
}

@test "yaml_key_to_env_var: maps report.formats to REPORT_FORMATS" {
  run yaml_key_to_env_var "report" "formats"
  [ "$status" -eq 0 ]
  [ "$output" = "REPORT_FORMATS" ]
}

@test "yaml_key_to_env_var: returns empty for unknown mapping" {
  run yaml_key_to_env_var "unknown" "key"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ==============================================================================
# Additional branch coverage
# ==============================================================================

@test "is_allowed_key: accepts SONAR_URL (first allowlist entry)" {
  run is_allowed_key SONAR_URL
  [ "$status" -eq 0 ]
}

@test "sanitize_value: warns on shell metacharacters" {
  run sanitize_value 'value$(whoami)'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Suspicious pattern detected"* ]]
}

@test "set_config_var: ignores unknown key with warning" {
  run set_config_var "TOTALLY_UNKNOWN_KEY" "x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ignoring unknown config key"* ]]
}

@test "set_config_var: respects env snapshot (does not override)" {
  _ENV_SNAPSHOT_VARS=" SONAR_URL "
  export SONAR_URL="from-env"
  set_config_var SONAR_URL "from-config"
  [ "$SONAR_URL" = "from-env" ]
}

@test "parse_shell_config: strips quotes from values" {
  local f; f=$(mktemp)
  printf 'SONAR_TOKEN="quoted-token"\n' > "$f"
  parse_shell_config "$f"
  [ "$SONAR_TOKEN" = "quoted-token" ]
  rm -f "$f"
}

@test "parse_yaml_config: strips quotes from values" {
  local f; f=$(mktemp)
  printf 'sonar:\n  token: "quoted-tok"\n' > "$f"
  parse_yaml_config "$f"
  [ "$SONAR_TOKEN" = "quoted-tok" ]
  rm -f "$f"
}

@test "parse_yaml_config: warns on unknown YAML key" {
  local f; f=$(mktemp)
  printf 'sonar:\n  bogus_key: val\n' > "$f"
  run parse_yaml_config "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ignoring unknown YAML key: sonar.bogus_key"* ]]
  rm -f "$f"
}

@test "yaml_key_to_env_var: maps task_id, analysis_id, polling.wait, fail_on_gate" {
  [ "$(yaml_key_to_env_var sonar task_id)" = "SONAR_TASK_ID" ]
  [ "$(yaml_key_to_env_var sonar analysis_id)" = "ANALYSIS_ID" ]
  [ "$(yaml_key_to_env_var polling wait)" = "WAIT_FOR_ANALYSIS" ]
  [ "$(yaml_key_to_env_var options fail_on_gate)" = "FAIL_ON_GATE" ]
}

@test "yaml_key_to_env_var: maps enrichment quality-metadata keys" {
  [ "$(yaml_key_to_env_var enrichment include_quality_profiles)" = "INCLUDE_QUALITY_PROFILES" ]
  [ "$(yaml_key_to_env_var enrichment include_quality_gate_name)" = "INCLUDE_QUALITY_GATE_NAME" ]
}

@test "load_config_file: errors when config_dir not specified" {
  run load_config_file "" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"config_dir not specified"* ]]
}

@test "load_config_file: auto-loads sonar-report.conf when no YAML present" {
  local d; d=$(mktemp -d)
  printf 'SONAR_BRANCH=confbranch\n' > "$d/sonar-report.conf"
  run load_config_file "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Loading config from"* ]]
  [[ "$output" == *"sonar-report.conf"* ]]
  rm -rf "$d"
}

@test "is_allowed_key: accepts HTML_TEMPLATE" {
  run is_allowed_key "HTML_TEMPLATE"
  [ "$status" -eq 0 ]
}

@test "yaml_key_to_env_var: maps report.html_template to HTML_TEMPLATE" {
  run yaml_key_to_env_var "report" "html_template"
  [ "$status" -eq 0 ]
  [ "$output" = "HTML_TEMPLATE" ]
}

# ==============================================================================
# Config file vs. built-in defaults
#   The main script assigns defaults such as FAIL_ON_GATE=false before the
#   config file is read. A config value must replace such a default; only a
#   value that came from the environment (recorded in _ENV_SNAPSHOT_VARS) wins.
# ==============================================================================
@test "set_config_var: with an env snapshot, config replaces a pre-assigned default" {
  _ENV_SNAPSHOT_VARS=""
  FAIL_ON_GATE="false"
  set_config_var FAIL_ON_GATE "true"
  [ "$FAIL_ON_GATE" = "true" ]
}

@test "set_config_var: with an env snapshot, the environment still wins" {
  _ENV_SNAPSHOT_VARS=" FAIL_ON_GATE "
  FAIL_ON_GATE="false"
  set_config_var FAIL_ON_GATE "true"
  [ "$FAIL_ON_GATE" = "false" ]
}

@test "set_config_var: the first non-empty config entry for a key wins" {
  _ENV_SNAPSHOT_VARS=""
  SONAR_BRANCH=""
  set_config_var SONAR_BRANCH ""
  set_config_var SONAR_BRANCH "first"
  set_config_var SONAR_BRANCH "second"
  [ "$SONAR_BRANCH" = "first" ]
}

@test "set_config_var: an empty config value does not clear a default" {
  _ENV_SNAPSHOT_VARS=""
  POLL_INTERVAL="5"
  set_config_var POLL_INTERVAL ""
  [ "$POLL_INTERVAL" = "5" ]
}

@test "set_config_var: an empty config value still defines an unset variable" {
  _ENV_SNAPSHOT_VARS=""
  unset SONAR_TASK_ID
  set_config_var SONAR_TASK_ID ""
  [ "${SONAR_TASK_ID-unset}" = "" ]
}

@test "parse_yaml_config: on/off switches override defaults assigned earlier" {
  _ENV_SNAPSHOT_VARS=""
  WAIT_FOR_ANALYSIS="false"; FAIL_ON_GATE="false"; FAIL_ON_REGRESSION="false"; SONAR_CLOUD="false"
  local f; f=$(mktemp)
  printf 'sonar:\n  cloud: true\npolling:\n  wait: true\noptions:\n  fail_on_gate: true\n  fail_on_regression: true\n' > "$f"
  parse_yaml_config "$f"
  rm -f "$f"
  [ "$SONAR_CLOUD" = "true" ]
  [ "$WAIT_FOR_ANALYSIS" = "true" ]
  [ "$FAIL_ON_GATE" = "true" ]
  [ "$FAIL_ON_REGRESSION" = "true" ]
}

@test "parse_shell_config: FAIL_ON_GATE overrides a default assigned earlier" {
  _ENV_SNAPSHOT_VARS=""
  FAIL_ON_GATE="false"
  local f; f=$(mktemp)
  printf 'FAIL_ON_GATE=true\n' > "$f"
  parse_shell_config "$f"
  rm -f "$f"
  [ "$FAIL_ON_GATE" = "true" ]
}
