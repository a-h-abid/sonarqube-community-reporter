#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# shellcheck disable=SC2030,SC2031  # per-test variable changes are intentional
# ==============================================================================
# test_resilience.bats — HTTP retry/backoff/timeouts and bounded concurrency
#
# Covers:
#   api.sh          — sonar_api_get retries, http_retry_wait, http_setting,
#                     concurrency_level, run_parallel
#   portfolio.sh    — parallel per-project fetch
#   rule-details.sh — parallel enrichment prefetch
#   sonar-report.sh — parse_args wiring and validate_http_flags
#   config.sh       — http.* YAML keys
#
# curl is mocked with a per-test script of outcomes; every call is recorded as
# one file in a private directory, which stays correct under parallel workers.
# ==============================================================================

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

setup() {
  # shellcheck source=../scripts/sonar-report.sh
  source "${REPO_ROOT}/scripts/sonar-report.sh"

  export SONAR_REPORT_TMP_DIR CALLS OUT
  SONAR_REPORT_TMP_DIR=$(mktemp -d)
  CALLS=$(mktemp -d)
  OUT=$(mktemp -d)

  export SONAR_URL="http://sonar.example.com"
  export SONAR_TOKEN="test-token"
  export SONAR_ORGANIZATION="" SONAR_CLOUD="false" SONAR_BRANCH=""
  export HTTP_RETRIES=3 HTTP_RETRY_DELAY=0 HTTP_CONNECT_TIMEOUT=10 HTTP_TIMEOUT=120
  export CONCURRENCY=1
  SEVERITY_THRESHOLD=""; ISSUE_TYPES=""; MAX_ISSUES=""

  # MOCK_CURL_PLAN is a space-separated list consumed one entry per call; the
  # last entry repeats. An entry is an HTTP status, or "rcN" for curl exit N.
  # MOCK_CURL_RETRY_AFTER adds a Retry-After header to every response.
  curl() {
    local outfile="" hdrfile="" i=0 args=("$@")
    while [[ $i -lt ${#args[@]} ]]; do
      case "${args[$i]}" in
        -o) outfile="${args[$((i + 1))]}"; i=$((i + 2)) ;;
        -D) hdrfile="${args[$((i + 1))]}"; i=$((i + 2)) ;;
        *)  i=$((i + 1)) ;;
      esac
    done
    printf '%s\n' "$*" > "$(mktemp "${CALLS}/call.XXXXXX")"
    local n plan=() step
    n=$(find "$CALLS" -name 'call.*' | wc -l)
    read -ra plan <<< "${MOCK_CURL_PLAN:-200}"
    [[ "$n" -gt "${#plan[@]}" ]] && n="${#plan[@]}"
    step="${plan[$((n - 1))]}"
    if [[ -n "$hdrfile" && -n "${MOCK_CURL_RETRY_AFTER:-}" ]]; then
      printf 'HTTP/1.1 %s\r\nRetry-After: %s\r\n\r\n' "$step" "$MOCK_CURL_RETRY_AFTER" > "$hdrfile"
    fi
    if [[ "$step" == rc* ]]; then
      printf '000'
      return "${step#rc}"
    fi
    [[ -n "$outfile" ]] && printf '%s' "${MOCK_CURL_BODY:-{\}}" > "$outfile"
    printf '%s' "$step"
  }
  export -f curl

  sleep() { echo "$1" >> "${CALLS}/sleeps"; }
  export -f sleep
}

teardown() {
  rm -rf "$SONAR_REPORT_TMP_DIR" "$CALLS" "$OUT"
}

call_count() {
  find "$CALLS" -name 'call.*' | wc -l
}

# ===========================================================================
# sonar_api_get — retries
# ===========================================================================

@test "sonar_api_get: retries a 503 and succeeds on the next attempt" {
  export MOCK_CURL_PLAN="503 200" MOCK_CURL_BODY='{"ok":true}'
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  [ "$output" = '{"ok":true}' ]
  [ "$(call_count)" -eq 2 ]
  [[ "$stderr" == *"failed (HTTP 503) — retry 1/3"* ]]
}

@test "sonar_api_get: retries each transient status (408, 429, 502, 504)" {
  export MOCK_CURL_PLAN="408 429 502 504 200" HTTP_RETRIES=4
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  [ "$(call_count)" -eq 5 ]
}

@test "sonar_api_get: retries a transport failure and succeeds" {
  export MOCK_CURL_PLAN="rc7 rc28 200" MOCK_CURL_BODY='{"ok":true}'
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  [ "$output" = '{"ok":true}' ]
  [ "$(call_count)" -eq 3 ]
  [[ "$stderr" == *"curl exit 7"* ]]
  [[ "$stderr" == *"curl exit 28"* ]]
}

@test "sonar_api_get: gives up after HTTP_RETRIES and reports the status" {
  export MOCK_CURL_PLAN="503" HTTP_RETRIES=2
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 3 ]
  [[ "$stderr" == *"API 503"* ]]
}

@test "sonar_api_get: fails (not an empty success) when the server stays unreachable" {
  export MOCK_CURL_PLAN="rc7" HTTP_RETRIES=1
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [ "$(call_count)" -eq 2 ]
  [[ "$stderr" == *"Request failed (curl exit 7)"* ]]
}

@test "sonar_api_get: does not retry deterministic errors (401, 404, 500)" {
  local code
  for code in 401 404 500; do
    rm -f "${CALLS}"/call.*
    export MOCK_CURL_PLAN="$code"
    run --separate-stderr sonar_api_get "system/status"
    [ "$status" -ne 0 ]
    [ "$(call_count)" -eq 1 ]
  done
}

@test "sonar_api_get: HTTP_RETRIES=0 disables retries" {
  export MOCK_CURL_PLAN="503 200" HTTP_RETRIES=0
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 1 ]
}

@test "sonar_api_get: backs off exponentially between retries" {
  export MOCK_CURL_PLAN="503 503 503 200" HTTP_RETRY_DELAY=2
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  [ "$(tr '\n' ' ' < "${CALLS}/sleeps")" = "2 4 8 " ]
}

@test "sonar_api_get: honours a longer Retry-After header" {
  export MOCK_CURL_PLAN="429 200" HTTP_RETRY_DELAY=1 MOCK_CURL_RETRY_AFTER=7
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  [ "$(cat "${CALLS}/sleeps")" = "7" ]
}

@test "sonar_api_get: passes connect and total timeouts to curl" {
  export HTTP_CONNECT_TIMEOUT=4 HTTP_TIMEOUT=33
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  grep -q -- '--connect-timeout 4 --max-time 33' "${CALLS}"/call.*
}

@test "sonar_api_get: falls back to defaults when settings are not numeric" {
  export HTTP_CONNECT_TIMEOUT="abc" HTTP_TIMEOUT="" HTTP_RETRIES="x" MOCK_CURL_PLAN="503"
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 4 ]
  grep -q -- '--connect-timeout 10 --max-time 120' "${CALLS}"/call.*
}

@test "sonar_api_get: leaves no temp files behind" {
  export MOCK_CURL_PLAN="503 200" MOCK_CURL_RETRY_AFTER=0
  run --separate-stderr sonar_api_get "system/status"
  [ "$status" -eq 0 ]
  [ -z "$(ls -A "$SONAR_REPORT_TMP_DIR")" ]
}

# ===========================================================================
# http_retry_wait / http_setting / concurrency_level
# ===========================================================================

@test "http_retry_wait: doubles per attempt and is capped" {
  export HTTP_RETRY_DELAY=3
  [ "$(http_retry_wait 1)" = "3" ]
  [ "$(http_retry_wait 2)" = "6" ]
  [ "$(http_retry_wait 3)" = "12" ]
  [ "$(http_retry_wait 9)" = "60" ]
  [ "$(http_retry_wait 500)" = "60" ]
}

@test "http_retry_wait: Retry-After is capped and ignored when shorter or non-numeric" {
  export HTTP_RETRY_DELAY=5
  printf 'HTTP/1.1 429\r\nretry-after: 900\r\n\r\n' > "${OUT}/h"
  [ "$(http_retry_wait 1 "${OUT}/h")" = "60" ]
  printf 'HTTP/1.1 429\r\nRetry-After: 2\r\n\r\n' > "${OUT}/h"
  [ "$(http_retry_wait 1 "${OUT}/h")" = "5" ]
  printf 'HTTP/1.1 503\r\nRetry-After: Wed, 21 Oct 2026 07:28:00 GMT\r\n\r\n' > "${OUT}/h"
  [ "$(http_retry_wait 1 "${OUT}/h")" -le 60 ]
  printf 'HTTP/1.1 503\r\nContent-Type: text/html\r\n\r\n' > "${OUT}/h"
  [ "$(http_retry_wait 1 "${OUT}/h")" = "5" ]
}

@test "http_setting: accepts non-negative integers, otherwise the default" {
  [ "$(http_setting 0 9)" = "0" ]
  [ "$(http_setting 15 9)" = "15" ]
  [ "$(http_setting "" 9)" = "9" ]
  [ "$(http_setting -1 9)" = "9" ]
  [ "$(http_setting 1.5 9)" = "9" ]
}

@test "concurrency_level: positive integer or 1" {
  CONCURRENCY=6;   [ "$(concurrency_level)" = "6" ]
  CONCURRENCY=0;   [ "$(concurrency_level)" = "1" ]
  CONCURRENCY=abc; [ "$(concurrency_level)" = "1" ]
  unset CONCURRENCY
  [ "$(concurrency_level)" = "1" ]
}

# ===========================================================================
# run_parallel
# ===========================================================================

@test "run_parallel: writes each job's output by item index" {
  worker() { echo "got:$1"; }
  run_parallel 3 "$OUT" worker a b c d e
  [ "$(cat "${OUT}/0.out")" = "got:a" ]
  [ "$(cat "${OUT}/4.out")" = "got:e" ]
  [ "$(find "$OUT" -name '*.ok' | wc -l)" -eq 5 ]
}

@test "run_parallel: returns 1 when a job fails and marks only the successes" {
  worker() { [[ "$1" != "bad" ]] && echo "$1"; }
  run run_parallel 2 "$OUT" worker a bad c
  [ "$status" -ne 0 ]
  [ -f "${OUT}/0.ok" ]
  [ ! -f "${OUT}/1.ok" ]
  [ -f "${OUT}/2.ok" ]
}

@test "run_parallel: replays stderr in item order regardless of finish order" {
  worker() { [[ "$1" == "first" ]] && command sleep 0.3; echo "log:$1" >&2; }
  run --separate-stderr run_parallel 2 "$OUT" worker first second
  [ "$status" -eq 0 ]
  [ "$stderr" = "log:first"$'\n'"log:second" ]
}

@test "run_parallel: never runs more than max_jobs at once" {
  worker() {
    : > "${OUT}/running.$1"
    find "$OUT" -name 'running.*' | wc -l
    command sleep 0.2
    rm -f "${OUT}/running.$1"
  }
  run_parallel 2 "$OUT" worker 1 2 3 4 5 6
  local i
  for i in 0 1 2 3 4 5; do
    [ "$(cat "${OUT}/${i}.out")" -le 2 ]
  done
}

@test "run_parallel: actually overlaps jobs" {
  worker() { command sleep 0.5; }
  local start end
  start=$(date +%s%N)
  run_parallel 4 "$OUT" worker 1 2 3 4
  end=$(date +%s%N)
  # Sequential would take 2s; allow generous slack for a loaded CI host.
  [ $(( (end - start) / 1000000 )) -lt 1500 ]
}

@test "run_parallel: workers run with CONCURRENCY=1 and cannot change the caller" {
  CONCURRENCY=8
  worker() { echo "$CONCURRENCY"; LEAK=1; }
  run_parallel 2 "$OUT" worker a b
  [ "$(cat "${OUT}/0.out")" = "1" ]
  [ "$CONCURRENCY" = "8" ]
  [ -z "${LEAK:-}" ]
}

@test "run_parallel: invalid max_jobs falls back to sequential" {
  worker() { echo "$1"; }
  run_parallel "x" "$OUT" worker a b
  [ "$(cat "${OUT}/1.out")" = "b" ]
}

@test "run_parallel: no items is a successful no-op" {
  worker() { echo "$1"; }
  run run_parallel 4 "$OUT" worker
  [ "$status" -eq 0 ]
}

# ===========================================================================
# Portfolio — parallel fetch
# ===========================================================================

_mock_portfolio_fetch() {
  fetch_all_metrics() {
    : > "$(mktemp "${CALLS}/fetch.XXXXXX")"
    case "$SONAR_PROJECT_KEY" in
      proj-a) command sleep 0.2; cat "${FIXTURES}/portfolio_project_a.json" ;;
      proj-b) cat "${FIXTURES}/portfolio_project_b.json" ;;
      *)      return 1 ;;
    esac
  }
}

@test "fetch_portfolio_metrics: parallel result equals the sequential one" {
  _mock_portfolio_fetch
  SONAR_PROJECT_KEYS=(proj-a proj-b)
  CONCURRENCY=1 run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  local sequential="$output"

  CONCURRENCY=4 run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Fetching 2 projects (4 in parallel)"* ]]
  [ "$(echo "$output" | jq -S 'del(.metadata.reportDate)')" = "$(echo "$sequential" | jq -S 'del(.metadata.reportDate)')" ]
}

@test "fetch_portfolio_metrics: parallel keeps key order even when a later project finishes first" {
  _mock_portfolio_fetch
  SONAR_PROJECT_KEYS=(proj-a proj-b)
  CONCURRENCY=4 run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.portfolio.projects[0].metadata.projectKey')" = "proj-a" ]
  [ "$(echo "$output" | jq -r '.portfolio.projects[1].metadata.projectKey')" = "proj-b" ]
  # Per-project log blocks are replayed in key order too.
  [[ "$stderr" == *"Project: proj-a"*"Project: proj-b"* ]]
}

@test "fetch_portfolio_metrics: parallel fails when any project fails and cleans up" {
  _mock_portfolio_fetch
  SONAR_PROJECT_KEYS=(proj-a missing-project proj-b)
  CONCURRENCY=4 run --separate-stderr fetch_portfolio_metrics
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"Failed to collect analysis data for project: missing-project"* ]]
  [ -z "$(ls -A "$SONAR_REPORT_TMP_DIR")" ]
}

@test "fetch_portfolio_metrics: parallel applies display filters per project" {
  _mock_portfolio_fetch
  SONAR_PROJECT_KEYS=(proj-a proj-b)
  SEVERITY_THRESHOLD="BLOCKER"
  CONCURRENCY=4 run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.portfolio.projects[1].metadata.filtersApplied.severityThreshold')" = "BLOCKER" ]
  [ -z "$(ls -A "$SONAR_REPORT_TMP_DIR")" ]
}

@test "fetch_portfolio_metrics: parallel errors when the work directory cannot be created" {
  _mock_portfolio_fetch
  SONAR_PROJECT_KEYS=(proj-a proj-b)
  create_temp_dir() { return 1; }
  CONCURRENCY=4 run --separate-stderr fetch_portfolio_metrics
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to create temp directory for portfolio fetch"* ]]
}

@test "fetch_portfolio_metrics: a single project stays on the sequential path" {
  _mock_portfolio_fetch
  SONAR_PROJECT_KEYS=(proj-b)
  CONCURRENCY=4 run --separate-stderr fetch_portfolio_metrics
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"in parallel"* ]]
}

# ===========================================================================
# Enrichment — parallel prefetch
# ===========================================================================

# Records every API call as a file (safe across worker subshells) and serves
# fixtures by endpoint.
_mock_enrichment_api() {
  sonar_api_get() {
    printf '%s\n' "$1" > "$(mktemp "${CALLS}/api.XXXXXX")"
    case "$1" in
      rules/show*bad*)   return 1 ;;
      rules/show*)       cat "${FIXTURES}/rule_show.json" ;;
      hotspots/show*bad*) return 1 ;;
      hotspots/show*)    cat "${FIXTURES}/hotspot_show.json" ;;
      sources/raw*bad*)  return 1 ;;
      sources/raw*)      cat "${FIXTURES}/source_raw.txt" ;;
      *)                 return 1 ;;
    esac
  }
}

api_calls() {
  find "$CALLS" -name 'api.*' | wc -l
}

ISSUES='[
  {"key":"K1","rule":"java:S1","component":"p:src/A.java","line":5,"startLine":5,"endLine":5},
  {"key":"K2","rule":"java:S2","component":"p:src/B.java","line":6,"startLine":6,"endLine":6},
  {"key":"K3","rule":"java:S1","component":"p:src/A.java","line":7,"startLine":7,"endLine":7},
  {"key":"K4","rule":"java:S3","component":"p:src/C.java","line":8,"startLine":8,"endLine":8},
  {"key":"K5","rule":"java:S3","component":"p"}
]'

HOTSPOTS='[
  {"key":"H1","rule":"java:S10","component":"p:src/A.java","line":5,"startLine":5,"endLine":5},
  {"key":"H2","rule":"java:S10","component":"p:src/A.java","line":9,"startLine":9,"endLine":9},
  {"key":"H3","rule":"java:S11","component":"p:src/B.java","line":3,"startLine":3,"endLine":3}
]'

@test "enrich_issue_objects: parallel output equals sequential output" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="short" INCLUDE_CODE_SNIPPETS="true" SNIPPET_CONTEXT="2"

  CONCURRENCY=1 run --separate-stderr enrich_issue_objects "$ISSUES"
  [ "$status" -eq 0 ]
  local sequential="$output"

  CONCURRENCY=4 run --separate-stderr enrich_issue_objects "$ISSUES"
  [ "$status" -eq 0 ]
  [ "$output" = "$sequential" ]
  [ "$(echo "$output" | jq '[.[] | select(has("ruleDescription"))] | length')" -eq 5 ]
  [ "$(echo "$output" | jq '[.[] | select(has("codeSnippet"))] | length')" -eq 4 ]
}

@test "enrich_issue_objects: parallel fetches each unique rule and file exactly once" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="short" INCLUDE_CODE_SNIPPETS="true" CONCURRENCY=4
  run --separate-stderr enrich_issue_objects "$ISSUES"
  [ "$status" -eq 0 ]
  # 3 unique rules + 3 unique files; the per-issue loop is served from cache.
  [ "$(api_calls)" -eq 6 ]
  [ "$(cat "${CALLS}"/api.* | sort -u | wc -l)" -eq 6 ]
}

@test "enrich_issue_objects: parallel fails when a rule fetch fails" {
  _mock_enrichment_api
  log_error() { echo "$*" >&2; }
  export INCLUDE_RULE_DESCRIPTIONS="short" INCLUDE_CODE_SNIPPETS="false" CONCURRENCY=4
  local issues='[{"key":"K1","rule":"java:S1"},{"key":"K2","rule":"java:bad"},{"key":"K3","rule":"java:S3"}]'
  run --separate-stderr enrich_issue_objects "$issues"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to fetch rule details for java:bad"* ]]
  [[ "$stderr" == *"Failed to prefetch rule details"* ]]
  # Each rule was attempted once — the failure is not retried sequentially.
  [ "$(api_calls)" -eq 3 ]
}

@test "enrich_issue_objects: parallel fails when a source fetch fails" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="" INCLUDE_CODE_SNIPPETS="true" CONCURRENCY=4
  local issues='[{"key":"K1","rule":"r","component":"p:src/A.java","line":5},{"key":"K2","rule":"r","component":"p:src/bad.java","line":5}]'
  run --separate-stderr enrich_issue_objects "$issues"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to prefetch source files"* ]]
}

@test "enrich_issue_objects: a file over the cache limit is still enriched" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="" INCLUDE_CODE_SNIPPETS="true" CONCURRENCY=4
  _SOURCE_CACHE_MAX_BYTES=10
  run --separate-stderr enrich_issue_objects "$ISSUES"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq '[.[] | select(has("codeSnippet"))] | length')" -eq 4 ]
}

@test "enrich_hotspot_objects: parallel output equals sequential output" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="full" INCLUDE_CODE_SNIPPETS="true"

  CONCURRENCY=1 run --separate-stderr enrich_hotspot_objects "$HOTSPOTS"
  [ "$status" -eq 0 ]
  local sequential="$output"

  CONCURRENCY=4 run --separate-stderr enrich_hotspot_objects "$HOTSPOTS"
  [ "$status" -eq 0 ]
  [ "$output" = "$sequential" ]
  [ "$(echo "$output" | jq '[.[] | select(.ruleDescription.riskText != null)] | length')" -eq 3 ]
}

@test "enrich_hotspot_objects: parallel fetches one hotspot per rule and each file once" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="short" INCLUDE_CODE_SNIPPETS="true" CONCURRENCY=4
  run --separate-stderr enrich_hotspot_objects "$HOTSPOTS"
  [ "$status" -eq 0 ]
  # 2 unique rules + 2 unique files.
  [ "$(api_calls)" -eq 4 ]
}

@test "enrich_hotspot_objects: parallel fails when a hotspot fetch fails" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="short" INCLUDE_CODE_SNIPPETS="false" CONCURRENCY=4
  local hotspots='[{"key":"H1","rule":"java:S10"},{"key":"bad","rule":"java:S11"}]'
  run --separate-stderr enrich_hotspot_objects "$hotspots"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to prefetch hotspot details"* ]]
}

@test "enrich_hotspot_objects: parallel fails when a source fetch fails" {
  _mock_enrichment_api
  export INCLUDE_RULE_DESCRIPTIONS="" INCLUDE_CODE_SNIPPETS="true" CONCURRENCY=4
  local hotspots='[{"key":"H1","rule":"r","component":"p:src/A.java","line":5},{"key":"H2","rule":"r","component":"p:src/bad.java","line":5}]'
  run --separate-stderr enrich_hotspot_objects "$hotspots"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to prefetch source files"* ]]
}

@test "_prefetch_parallel: skips cached items and is a no-op for a single miss" {
  _mock_enrichment_api
  CONCURRENCY=4
  _RULE_CACHE["java:S1"]='{"cached":true}'
  _prefetch_parallel rule "java:S1" "java:S2" ""
  [ "$(api_calls)" -eq 0 ]
  [ "${_RULE_CACHE["java:S1"]}" = '{"cached":true}' ]
}

@test "_prefetch_parallel: rejects an unknown kind" {
  CONCURRENCY=4 run --separate-stderr _prefetch_parallel bogus a b
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Unsupported prefetch kind"* ]]
}

@test "_prefetch_parallel: errors when the work directory cannot be created" {
  create_temp_dir() { return 1; }
  CONCURRENCY=4 run --separate-stderr _prefetch_parallel rule a b
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"Failed to create temp directory for rule prefetch"* ]]
}

# ===========================================================================
# CLI wiring, validation, config
# ===========================================================================

@test "parse_args: resilience flags set their variables (both forms)" {
  parse_args --concurrency 8 --http-retries 5 --http-retry-delay 1 \
    --http-connect-timeout 3 --http-timeout 45 --project-key p
  [ "$CONCURRENCY" = "8" ]
  [ "$HTTP_RETRIES" = "5" ]
  [ "$HTTP_RETRY_DELAY" = "1" ]
  [ "$HTTP_CONNECT_TIMEOUT" = "3" ]
  [ "$HTTP_TIMEOUT" = "45" ]

  parse_args --concurrency=2 --http-retries=0 --http-retry-delay=4 \
    --http-connect-timeout=6 --http-timeout=0
  [ "$CONCURRENCY" = "2" ]
  [ "$HTTP_RETRIES" = "0" ]
  [ "$HTTP_RETRY_DELAY" = "4" ]
  [ "$HTTP_CONNECT_TIMEOUT" = "6" ]
  [ "$HTTP_TIMEOUT" = "0" ]
}

@test "apply_defaults: concurrency 4, 3 retries, 2s backoff, 10s/120s timeouts" {
  unset CONCURRENCY HTTP_RETRIES HTTP_RETRY_DELAY HTTP_CONNECT_TIMEOUT HTTP_TIMEOUT
  apply_defaults
  [ "$CONCURRENCY" = "4" ]
  [ "$HTTP_RETRIES" = "3" ]
  [ "$HTTP_RETRY_DELAY" = "2" ]
  [ "$HTTP_CONNECT_TIMEOUT" = "10" ]
  [ "$HTTP_TIMEOUT" = "120" ]
}

@test "validate_http_flags: accepts valid values and fills unset ones" {
  unset CONCURRENCY HTTP_RETRIES HTTP_RETRY_DELAY HTTP_CONNECT_TIMEOUT HTTP_TIMEOUT
  validate_http_flags
  [ "$CONCURRENCY" = "4" ]
  [ "$HTTP_TIMEOUT" = "120" ]
}

@test "validate_http_flags: rejects a non-positive or non-numeric concurrency" {
  CONCURRENCY=0 run validate_http_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"--concurrency must be a positive integer"* ]]
  CONCURRENCY=many run validate_http_flags
  [ "$status" -ne 0 ]
}

@test "validate_http_flags: clamps an excessive concurrency to 16" {
  CONCURRENCY=64
  validate_http_flags 2> "${OUT}/err"
  [ "$CONCURRENCY" = "16" ]
  grep -q "clamping to 16" "${OUT}/err"
}

@test "validate_http_flags: rejects invalid retry and timeout values" {
  HTTP_RETRIES=-1 run validate_http_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"HTTP_RETRIES must be a non-negative integer"* ]]
  HTTP_RETRY_DELAY=1.5 run validate_http_flags
  [ "$status" -ne 0 ]
  HTTP_TIMEOUT=soon run validate_http_flags
  [ "$status" -ne 0 ]
  HTTP_CONNECT_TIMEOUT=0 run validate_http_flags
  [ "$status" -ne 0 ]
  [[ "$output" == *"HTTP_CONNECT_TIMEOUT must be a positive integer"* ]]
}

@test "config: http.* YAML keys map to their variables" {
  [ "$(yaml_key_to_env_var http concurrency)" = "CONCURRENCY" ]
  [ "$(yaml_key_to_env_var http retries)" = "HTTP_RETRIES" ]
  [ "$(yaml_key_to_env_var http retry_delay)" = "HTTP_RETRY_DELAY" ]
  [ "$(yaml_key_to_env_var http connect_timeout)" = "HTTP_CONNECT_TIMEOUT" ]
  [ "$(yaml_key_to_env_var http timeout)" = "HTTP_TIMEOUT" ]
}

@test "config: http section is loaded from a YAML file" {
  unset CONCURRENCY HTTP_RETRIES HTTP_RETRY_DELAY HTTP_CONNECT_TIMEOUT HTTP_TIMEOUT
  _ENV_SNAPSHOT_VARS=""
  printf 'http:\n  concurrency: 6\n  retries: 1\n  retry_delay: 5\n  connect_timeout: 7\n  timeout: 90\n' > "${OUT}/c.yml"
  parse_yaml_config "${OUT}/c.yml"
  [ "$CONCURRENCY" = "6" ]
  [ "$HTTP_RETRIES" = "1" ]
  [ "$HTTP_RETRY_DELAY" = "5" ]
  [ "$HTTP_CONNECT_TIMEOUT" = "7" ]
  [ "$HTTP_TIMEOUT" = "90" ]
}

@test "config: resilience keys are allowed in shell-style config" {
  local k
  for k in CONCURRENCY HTTP_RETRIES HTTP_RETRY_DELAY HTTP_CONNECT_TIMEOUT HTTP_TIMEOUT; do
    is_allowed_key "$k"
  done
}

# ===========================================================================
# Webhook — timeouts
# ===========================================================================

@test "send_webhook_notification: bounds the request with timeouts and does not retry" {
  export HTTP_CONNECT_TIMEOUT=5 HTTP_TIMEOUT=20 MOCK_CURL_PLAN="503"
  run send_webhook_notification "https://hooks.example.com/test" "${FIXTURES}/report_data.json"
  [ "$status" -ne 0 ]
  [ "$(call_count)" -eq 1 ]
  grep -q -- '--connect-timeout 5 --max-time 20' "${CALLS}"/call.*
}
