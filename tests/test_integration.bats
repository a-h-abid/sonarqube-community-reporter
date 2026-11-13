#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# ==============================================================================
# test_integration.bats — End-to-end tests for sonar-report.sh main() + entry
#
# Exercises the main() orchestration via the offline --dry-run path (no network)
# and via mocked collaborators (check_connectivity / wait_for_analysis /
# fetch_all_metrics) for the live path.
#
# External tools (wkhtmltopdf, ssconvert) are made deterministic with a PATH
# sandbox: a symlink farm of the real toolchain MINUS those tools (the "absent"
# base), plus a fake-bin dir holding fast stand-ins (the "present" overlay).
# ==============================================================================

setup_file() {
  export _IT_SANDBOX="${BATS_FILE_TMPDIR}/sandbox"
  export _IT_FAKEBIN="${BATS_FILE_TMPDIR}/fakebin"
  mkdir -p "$_IT_SANDBOX" "$_IT_FAKEBIN"

  # Symlink-farm every dir on PATH (first match wins, like PATH search), then
  # drop the heavy report tools so the base sandbox simulates them being absent.
  local d
  local -a _dirs
  IFS=':' read -ra _dirs <<< "$PATH"
  for d in "${_dirs[@]}"; do
    [[ -d "$d" ]] && cp -as "${d}/." "$_IT_SANDBOX/" 2>/dev/null || true
  done
  rm -f "$_IT_SANDBOX/wkhtmltopdf" "$_IT_SANDBOX/ssconvert" \
        "$_IT_SANDBOX/soffice" "$_IT_SANDBOX/libreoffice"

  # Fast fakes: wkhtmltopdf writes its output (last arg); ssconvert writes the
  # --merge-to target. Both succeed instantly so the success paths are covered
  # without invoking the real (slow, xvfb-dependent) renderers.
  cat > "$_IT_FAKEBIN/wkhtmltopdf" <<'SH'
#!/usr/bin/env bash
out="${@: -1}"
printf '%%PDF-1.4 fake' > "$out"
SH
  cat > "$_IT_FAKEBIN/ssconvert" <<'SH'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in --merge-to=*) printf 'fake-spreadsheet' > "${a#--merge-to=}" ;; esac
done
SH
  chmod +x "$_IT_FAKEBIN/wkhtmltopdf" "$_IT_FAKEBIN/ssconvert"
}

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  # shellcheck source=../scripts/sonar-report.sh
  source "${REPO_ROOT}/scripts/sonar-report.sh"

  # Reset all config/env vars to a known clean state so neither a developer's
  # local .env nor inherited environment leaks into the assertions.
  SONAR_URL="http://sonar.example.com"; SONAR_TOKEN=""; SONAR_PROJECT_KEY=""
  SONAR_BRANCH=""; SONAR_TASK_ID=""; SONAR_ORGANIZATION=""; SONAR_CLOUD="false"
  REPORT_FORMATS="json"; REPORT_OUTPUT_DIR="./reports"
  POLL_INTERVAL="1"; POLL_TIMEOUT="2"; ANALYSIS_ID=""; DRY_RUN_FILE=""
  NOTIFY_WEBHOOK=""; INCLUDE_RULE_DESCRIPTIONS=""; INCLUDE_CODE_SNIPPETS="false"
  SNIPPET_CONTEXT="3"; WAIT_FOR_ANALYSIS="false"; FAIL_ON_GATE="false"
  REQUESTED_FORMATS=(); SONAR_PROJECT_KEYS=()
  SEVERITY_THRESHOLD=""; ISSUE_TYPES=""; MAX_ISSUES=""

  FIXTURE="${REPO_ROOT}/tests/fixtures/report_data.json"
  FIXTURE_ERR="${REPO_ROOT}/tests/fixtures/report_data_gate_error.json"
  FIXTURE_PORTFOLIO="${REPO_ROOT}/tests/fixtures/portfolio_data.json"
  OUT="$(mktemp -d)"

  PRESENT="${_IT_FAKEBIN}:${_IT_SANDBOX}"   # report tools available (fakes)
  ABSENT="${_IT_SANDBOX}"                    # report tools missing
}

teardown() {
  rm -rf "$OUT"
}

# ===========================================================================
# Dry-run mode — pure-bash formats (no external tools)
# ===========================================================================

@test "main: dry-run generates json, md, html, csv" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats json,md,html,csv --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Quality Gate: PASSED"* ]]
  [[ "$output" == *"Generated"* ]]
  [ -n "$(find "$OUT" -name '*.json')" ]
  [ -n "$(find "$OUT" -name '*.md')" ]
  [ -n "$(find "$OUT" -name '*.html')" ]
  [ -n "$(find "$OUT" -name '*.csv')" ]
}

@test "main: dry-run auto-populates project key from file" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Project key from dry-run file: my-project"* ]]
}

# ===========================================================================
# Dry-run mode — all formats with report tools present (fakes)
# ===========================================================================

@test "main: dry-run generates all formats when tools present" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" \
    --formats json,md,html,pdf,xlsx,ods,csv,sarif --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [ -n "$(find "$OUT" -name '*.pdf')" ]
  [ -n "$(find "$OUT" -name '*.xlsx')" ]
  [ -n "$(find "$OUT" -name '*.ods')" ]
  [ -n "$(find "$OUT" -name '*.sarif')" ]
}

@test "main: pdf reuses already-generated html (html+pdf requested)" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats html,pdf --output-dir "$OUT"
  [ "$status" -eq 0 ]
  # exactly one HTML file even though both html and pdf were requested
  [ "$(find "$OUT" -name '*.html' | wc -l)" -eq 1 ]
  [ -n "$(find "$OUT" -name '*.pdf')" ]
}

# ===========================================================================
# Dry-run mode — report tools absent → formats skipped gracefully
# ===========================================================================

@test "main: skips pdf/xlsx/ods when tools are absent" {
  PATH="$ABSENT" SSCONVERT_BIN="ssconvert" run main --dry-run "$FIXTURE" \
    --formats pdf,xlsx,ods --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped format(s)"* ]]
  [[ "$output" == *"pdf"* ]]
}

# ===========================================================================
# Quality gate handling / exit codes
# ===========================================================================

@test "main: --fail-on-gate exits 1 on failing gate" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE_ERR" --fail-on-gate \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Quality Gate: FAILED"* ]]
  [[ "$output" == *"quality gate failed"* ]]
}

@test "main: failing gate without --fail-on-gate still exits 0" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE_ERR" --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Quality Gate: FAILED"* ]]
}

@test "main: warns on unknown (WARN) gate status" {
  local warn_fix="$OUT/warn.json"
  jq '.qualityGate.status = "WARN"' "$FIXTURE" > "$warn_fix"
  PATH="$PRESENT" run main --dry-run "$warn_fix" --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Quality Gate: WARN"* ]]
}

# ===========================================================================
# Webhook notification branch
# ===========================================================================

@test "main: invokes webhook notification when --notify-webhook set" {
  send_webhook_notification() { echo "WEBHOOK_CALLED $1"; return 0; }
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats json \
    --notify-webhook "https://hooks.example.com/x" --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WEBHOOK_CALLED https://hooks.example.com/x"* ]]
}

@test "main: continues when webhook notification fails" {
  send_webhook_notification() { return 1; }
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats json \
    --notify-webhook "https://hooks.example.com/x" --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Webhook notification failed"* ]]
}

# ===========================================================================
# Enrichment flag logging (dry-run)
# ===========================================================================

@test "main: reports enrichment flags in banner" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats json \
    --include-rule-descriptions=full --include-code-snippets --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rule descriptions: full"* ]]
  [[ "$output" == *"Code snippets:"* ]]
}

# ===========================================================================
# Argument / validation error paths
# ===========================================================================

@test "main: errors when SONAR_TOKEN missing (live mode)" {
  PATH="$PRESENT" run main --project-key p --formats json --output-dir "$OUT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SONAR_TOKEN is required"* ]]
}

@test "main: errors when SONAR_PROJECT_KEY missing (live mode)" {
  PATH="$PRESENT" run main --token t --formats json --output-dir "$OUT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SONAR_PROJECT_KEY is required"* ]]
}

@test "main: errors when SonarCloud org missing" {
  PATH="$PRESENT" run main --token t --project-key p --sonarcloud \
    --formats json --output-dir "$OUT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SONAR_ORGANIZATION is required"* ]]
}

@test "main: rejects unknown option with a non-zero exit" {
  PATH="$PRESENT" run main --bogus-flag
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --bogus-flag"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "main: rejects the unsupported --flag=value spelling instead of exiting 0" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats=json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --formats=json"* ]]
  [ -z "$(find "$OUT" -type f)" ]
}

@test "main: an option missing its value exits 1 with a clear error" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats
  [ "$status" -eq 1 ]
  [[ "$output" == *"Option --formats requires a value"* ]]
}

@test "main: an option given where a value belongs is an error, not the value" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE_ERR" --formats json --output-dir "$OUT" \
    --branch --fail-on-gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Option --branch requires a value (found option '--fail-on-gate' instead)"* ]]
  [ -z "$(find "$OUT" -type f)" ]
}

@test "main: -h given where a value belongs is an error" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats -h
  [ "$status" -eq 1 ]
  [[ "$output" == *"Option --formats requires a value"* ]]
}

@test "main: an empty value and a value starting with a single dash are accepted" {
  mkdir -p "$OUT/-reports"
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --branch "" --formats json \
    --output-dir "$OUT/-reports"
  [ "$status" -eq 0 ]
  [ -n "$(find "$OUT/-reports" -name '*.json')" ]
}

@test "main: --config without a path exits 1 with a clear error" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --config
  [ "$status" -eq 1 ]
  [[ "$output" == *"Option --config requires a value"* ]]
}

# ===========================================================================
# Fail-closed switches (FAIL_ON_GATE & friends)
# ===========================================================================

@test "main: FAIL_ON_GATE accepts the usual true spellings" {
  local v
  for v in true TRUE True yes 1 on; do
    FAIL_ON_GATE="$v"
    PATH="$PRESENT" run main --dry-run "$FIXTURE_ERR" --formats json --output-dir "$OUT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"quality gate failed"* ]]
  done
}

@test "main: FAIL_ON_GATE false spellings do not fail the run" {
  local v
  for v in false FALSE no 0 off ""; do
    FAIL_ON_GATE="$v"
    PATH="$PRESENT" run main --dry-run "$FIXTURE_ERR" --formats json --output-dir "$OUT"
    [ "$status" -eq 0 ]
  done
}

@test "main: an unrecognized FAIL_ON_GATE value is an error, not a silent false" {
  FAIL_ON_GATE="maybe"
  PATH="$PRESENT" run main --dry-run "$FIXTURE_ERR" --formats json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid FAIL_ON_GATE value: 'maybe'"* ]]
  [ -z "$(find "$OUT" -type f)" ]
}

@test "main: unrecognized WAIT_FOR_ANALYSIS / SONAR_CLOUD values are errors" {
  WAIT_FOR_ANALYSIS="sometimes"; SONAR_CLOUD="perhaps"
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid WAIT_FOR_ANALYSIS value"* ]]
  [[ "$output" == *"Invalid SONAR_CLOUD value"* ]]
}

@test "main: fail_on_gate from a config file fails the run on a failing gate" {
  _ENV_SNAPSHOT_VARS=""
  printf 'options:\n  fail_on_gate: true\n' > "$OUT/c.yml"
  PATH="$PRESENT" run main --config "$OUT/c.yml" --dry-run "$FIXTURE_ERR" \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"quality gate failed"* ]]
}

@test "main: FAIL_ON_GATE from the environment beats the config file" {
  _ENV_SNAPSHOT_VARS=" FAIL_ON_GATE "
  FAIL_ON_GATE="false"
  printf 'options:\n  fail_on_gate: true\n' > "$OUT/c.yml"
  PATH="$PRESENT" run main --config "$OUT/c.yml" --dry-run "$FIXTURE_ERR" \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
}

@test "normalize_bool_var: rewrites the variable to true/false" {
  local MY_SWITCH="YES"
  normalize_bool_var MY_SWITCH
  [ "$MY_SWITCH" = "true" ]
  MY_SWITCH="Off"
  normalize_bool_var MY_SWITCH
  [ "$MY_SWITCH" = "false" ]
  MY_SWITCH=""
  normalize_bool_var MY_SWITCH
  [ "$MY_SWITCH" = "false" ]
}

# ===========================================================================
# Generator failures are fatal
# ===========================================================================

@test "main: untrusted report values cannot run commands during HTML generation" {
  local marker="$OUT/PWNED"
  jq --arg name "Acme|;1e touch ${marker} #" '.metadata.projectName = $name' "$FIXTURE" > "$OUT/evil.json"
  PATH="$PRESENT" run main --dry-run "$OUT/evil.json" --formats html --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  [ -s "$(find "$OUT" -name '*.html')" ]
}

@test "main: exits 1 and names the format when a generator fails" {
  jq '.issues = 5' "$FIXTURE" > "$OUT/bad.json"
  PATH="$PRESENT" run main --dry-run "$OUT/bad.json" --formats json,html --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to generate HTML report"* ]]
  [[ "$output" != *"Generated"* ]]
  [ -z "$(find "$OUT" -name '*.html')" ]
}

@test "main: exits 1 when a generator reports success but leaves an empty file" {
  generate_md_report() { : > "$2/empty.md"; echo "$2/empty.md"; }
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats md --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Report file is missing or empty"* ]]
  [[ "$output" == *"Failed to generate MD report"* ]]
}

@test "main: exits 1 when the csv generator produces nothing" {
  generate_csv_report() { :; }
  PATH="$PRESENT" run main --dry-run "$FIXTURE" --formats csv --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to generate CSV report"* ]]
}

# ===========================================================================
# Live mode (mocked collaborators — no real network)
# ===========================================================================

@test "main: live SonarQube run with mocked collaborators" {
  check_connectivity() { return 0; }
  fetch_all_metrics() { cat "$FIXTURE"; }
  PATH="$PRESENT" run main --token t --project-key p --formats json,md --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode:       SonarQube"* ]]
  [ -n "$(find "$OUT" -name '*.json')" ]
}

@test "main: live run honors --wait" {
  check_connectivity() { return 0; }
  wait_for_analysis() { echo "WAITED"; return 0; }
  fetch_all_metrics() { cat "$FIXTURE"; }
  PATH="$PRESENT" run main --wait --token t --project-key p --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WAITED"* ]]
}

@test "main: live SonarCloud run logs cloud mode" {
  check_connectivity() { return 0; }
  fetch_all_metrics() { cat "$FIXTURE"; }
  PATH="$PRESENT" run main --token t --project-key p --sonarcloud \
    --organization my-org --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode:       SonarCloud"* ]]
  [[ "$output" == *"Org:"* ]]
}

@test "main: exits 1 when metrics collection fails" {
  check_connectivity() { return 0; }
  fetch_all_metrics() { return 1; }
  PATH="$PRESENT" run main --token t --project-key p --formats json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to collect analysis data"* ]]
}

# ===========================================================================
# Explicit config file (covers main's --config first pass)
# ===========================================================================

@test "main: loads explicit --config file" {
  local cfg="$OUT/custom.conf"
  printf 'SONAR_BRANCH=from-config\n' > "$cfg"
  check_connectivity() { return 0; }
  fetch_all_metrics() { cat "$FIXTURE"; }
  PATH="$PRESENT" run main --config "$cfg" --token t --project-key p \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# Portfolio (multi-project) mode
# ===========================================================================

@test "main: portfolio dry-run generates rolled-up reports across formats" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE_PORTFOLIO" \
    --formats json,md,html,csv --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"passed across 2 projects"* ]]
  [ -n "$(find "$OUT" -name 'portfolio_*.md')" ]
  [ -n "$(find "$OUT" -name 'portfolio_*.html')" ]
  [ -n "$(find "$OUT" -name 'portfolio_*_comparison.csv')" ]
}

@test "main: portfolio --fail-on-gate exits 1 when any project's gate failed" {
  PATH="$PRESENT" run main --dry-run "$FIXTURE_PORTFOLIO" --fail-on-gate \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAILED"* ]]
  [[ "$output" == *"quality gate failed"* ]]
}

@test "main: live portfolio run with repeated --project-key flags" {
  check_connectivity() { return 0; }
  fetch_all_metrics() {
    case "$SONAR_PROJECT_KEY" in
      proj-a) cat "${REPO_ROOT}/tests/fixtures/portfolio_project_a.json" ;;
      proj-b) cat "${REPO_ROOT}/tests/fixtures/portfolio_project_b.json" ;;
      *) return 1 ;;
    esac
  }
  PATH="$PRESENT" run main --token t \
    --project-key proj-a --project-key proj-b \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Mode:       portfolio (2 projects)"* ]]
  local f
  f=$(find "$OUT" -name 'portfolio_*.json')
  [ -n "$f" ]
  [ "$(jq -r '.metadata.reportType' "$f")" = "portfolio" ]
  [ "$(jq -r '.metadata.projectCount' "$f")" = "2" ]
}

@test "main: portfolio summary reports all gates passing" {
  local allpass="$OUT/allpass.json"
  jq '.portfolio.totals.gatesFailed = 0
      | .portfolio.totals.gatesPassed = 2
      | (.portfolio.projects[].qualityGate.status) = "OK"' \
     "$FIXTURE_PORTFOLIO" > "$allpass"
  PATH="$PRESENT" run main --dry-run "$allpass" --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all 2 PASSED across 2 projects"* ]]
}

@test "main: exits 1 when portfolio collection fails" {
  check_connectivity() { return 0; }
  fetch_all_metrics() {
    [ "$SONAR_PROJECT_KEY" = "proj-a" ] && cat "${REPO_ROOT}/tests/fixtures/portfolio_project_a.json" || return 1
  }
  PATH="$PRESENT" run main --token t \
    --project-key proj-a --project-key proj-b \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to collect portfolio data"* ]]
}

@test "main: live portfolio accepts a comma-separated --project-key list" {
  check_connectivity() { return 0; }
  fetch_all_metrics() {
    case "$SONAR_PROJECT_KEY" in
      proj-a) cat "${REPO_ROOT}/tests/fixtures/portfolio_project_a.json" ;;
      proj-b) cat "${REPO_ROOT}/tests/fixtures/portfolio_project_b.json" ;;
      *) return 1 ;;
    esac
  }
  PATH="$PRESENT" run main --token t --project-key "proj-a,proj-b" \
    --formats json --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"portfolio (2 projects)"* ]]
}

# ===========================================================================
# Entry-point guard (real subprocess so BASH_SOURCE == $0 fires)
# ===========================================================================

@test "entrypoint: script runs end-to-end as a subprocess" {
  PATH="$PRESENT" run bash "${REPO_ROOT}/scripts/sonar-report.sh" \
    --dry-run "$FIXTURE" --formats json,md --output-dir "$OUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Generated"* ]]
  [ -n "$(find "$OUT" -name '*.json')" ]
}

@test "entrypoint: --help prints usage as a subprocess" {
  PATH="$PRESENT" run bash "${REPO_ROOT}/scripts/sonar-report.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

@test "entrypoint: an unknown option exits 1 as a subprocess" {
  PATH="$PRESENT" run bash "${REPO_ROOT}/scripts/sonar-report.sh" --no-such-option
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option: --no-such-option"* ]]
}

@test "entrypoint: a failing generator ends the run with exit 1 (errexit inside \$())" {
  jq '.issues = 5' "$FIXTURE" > "$OUT/bad.json"
  PATH="$PRESENT" run bash "${REPO_ROOT}/scripts/sonar-report.sh" \
    --dry-run "$OUT/bad.json" --formats html,json --output-dir "$OUT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to generate HTML report"* ]]
  [ -z "$(find "$OUT" -name '*.html')" ]
  [ -z "$(find "$OUT" -name '*.json' ! -name 'bad.json')" ]
}
