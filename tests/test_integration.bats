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
  REQUESTED_FORMATS=()

  FIXTURE="${REPO_ROOT}/tests/fixtures/report_data.json"
  FIXTURE_ERR="${REPO_ROOT}/tests/fixtures/report_data_gate_error.json"
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

@test "main: rejects unknown option" {
  PATH="$PRESENT" run main --bogus-flag
  [[ "$output" == *"Unknown option: --bogus-flag"* ]]
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
