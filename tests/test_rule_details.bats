#!/usr/bin/env bats
# shellcheck shell=bash
# shellcheck disable=SC2317  # bats @test blocks appear unreachable to shellcheck
# shellcheck disable=SC2089,SC2090
# ==============================================================================
# test_rule_details.bats — Unit tests for scripts/lib/rule-details.sh
#
# Covers:
#   fetch_rule_details, fetch_hotspot_details, fetch_source_snippet,
#   enrich_issue_objects, enrich_hotspot_objects
#
# sonar_api_get is mocked so no real HTTP calls occur. The in-memory caches
# are reset in setup() between tests so they don't leak.
# ==============================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
FIXTURES="${REPO_ROOT}/tests/fixtures"

# shellcheck source=helpers.bash
load 'helpers'

setup() {
  # shellcheck source=../scripts/lib/rule-details.sh
  source "${REPO_ROOT}/scripts/lib/rule-details.sh"

  # Reset caches between tests (the module declares them with -gA so they're
  # global; clearing all keys keeps the variables intact for the next test).
  _RULE_CACHE=()
  _HOTSPOT_RULE_CACHE=()
  _SOURCE_CACHE=()
  _RULE_NEGATIVE=()
  _COMPONENT_NEGATIVE=()

  export SONAR_URL="http://sonar.example.com"
  export SONAR_TOKEN="test-token"
  export SONAR_CLOUD=false
  export SONAR_ORGANIZATION=""

  # Silence log output by default
  log_info() { :; }
  log_ok()   { :; }
  log_warn() { :; }
  log_error() { :; }
  export -f log_info log_ok log_warn log_error
}

# ===========================================================================
# fetch_rule_details
# ===========================================================================

@test "fetch_rule_details: returns object with why and how-to-fix fields" {
  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get

  run fetch_rule_details "java:S2259"
  [ "$status" -eq 0 ]
  has_why=$(echo "$output" | jq 'has("whyText")')
  has_fix=$(echo "$output" | jq 'has("howToFixText")')
  [ "$has_why" = "true" ]
  [ "$has_fix" = "true" ]
}

@test "fetch_rule_details: extracts root_cause from descriptionSections as whyText" {
  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get

  run fetch_rule_details "java:S2259"
  [ "$status" -eq 0 ]
  why=$(echo "$output" | jq -r '.whyText')
  [[ "$why" == *"NullPointerException"* ]]
}

@test "fetch_rule_details: extracts how_to_fix from descriptionSections" {
  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get

  run fetch_rule_details "java:S2259"
  [ "$status" -eq 0 ]
  fix=$(echo "$output" | jq -r '.howToFixText')
  [[ "$fix" == *"Check the variable"* ]]
}

@test "fetch_rule_details: whyTextShort is the first paragraph only" {
  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get

  run fetch_rule_details "java:S2259"
  [ "$status" -eq 0 ]
  short=$(echo "$output" | jq -r '.whyTextShort')
  full=$(echo "$output" | jq -r '.whyText')
  # Short must be shorter or equal to full
  [ "${#short}" -le "${#full}" ]
  # Short should not contain the second paragraph
  [[ "$short" != *"hide the real reason"* ]]
}

@test "fetch_rule_details: preserves HTML in whyHtml" {
  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get

  run fetch_rule_details "java:S2259"
  [ "$status" -eq 0 ]
  html=$(echo "$output" | jq -r '.whyHtml')
  [[ "$html" == *"<p>"* ]]
}

@test "fetch_rule_details: falls back to htmlDesc when descriptionSections missing" {
  sonar_api_get() { cat "${FIXTURES}/rule_show_legacy.json"; }
  export -f sonar_api_get

  run fetch_rule_details "java:S3776"
  [ "$status" -eq 0 ]
  why=$(echo "$output" | jq -r '.whyText')
  fix=$(echo "$output" | jq -r '.howToFixText')
  [[ "$why" == *"Cognitive Complexity"* ]]
  [[ "$fix" == *"Refactor the method"* ]]
}

@test "fetch_rule_details: returns empty object on API failure" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_rule_details "java:S2259"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "fetch_rule_details: returns empty object on empty rule" {
  sonar_api_get() { cat "${FIXTURES}/rule_show_empty.json"; }
  export -f sonar_api_get

  run fetch_rule_details "java:S0000"
  [ "$status" -eq 0 ]
  # Empty rule yields an object with empty/null fields — accept either {} or {"whyText":"",...}
  why=$(echo "$output" | jq -r '.whyText // ""')
  [ -z "$why" ]
}

@test "fetch_rule_details: caches subsequent calls for the same rule" {
  export _CALL_CTR
  _CALL_CTR=$(counter_file_new)

  sonar_api_get() {
    counter_file_increment "$_CALL_CTR" >/dev/null
    cat "${FIXTURES}/rule_show.json"
  }
  export -f sonar_api_get counter_file_increment

  fetch_rule_details "java:S2259" >/dev/null
  fetch_rule_details "java:S2259" >/dev/null
  fetch_rule_details "java:S2259" >/dev/null
  local count
  count=$(cat "$_CALL_CTR")
  rm -f "$_CALL_CTR"
  [ "$count" -eq 1 ]
}

@test "fetch_rule_details: negative cache prevents retry after failure" {
  export _CALL_CTR
  _CALL_CTR=$(counter_file_new)

  sonar_api_get() {
    counter_file_increment "$_CALL_CTR" >/dev/null
    return 1
  }
  export -f sonar_api_get counter_file_increment

  fetch_rule_details "java:S2259" >/dev/null
  fetch_rule_details "java:S2259" >/dev/null
  local count
  count=$(cat "$_CALL_CTR")
  rm -f "$_CALL_CTR"
  [ "$count" -eq 1 ]
}

@test "fetch_rule_details: returns {} on empty rule key without calling API" {
  export _CALL_CTR
  _CALL_CTR=$(counter_file_new)

  sonar_api_get() {
    counter_file_increment "$_CALL_CTR" >/dev/null
    cat "${FIXTURES}/rule_show.json"
  }
  export -f sonar_api_get counter_file_increment

  run fetch_rule_details ""
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
  local count
  count=$(cat "$_CALL_CTR")
  rm -f "$_CALL_CTR"
  [ "$count" -eq 0 ]
}

# ===========================================================================
# fetch_hotspot_details
# ===========================================================================

@test "fetch_hotspot_details: extracts whyHtml from vulnerabilityDescription" {
  sonar_api_get() { cat "${FIXTURES}/hotspot_show.json"; }
  export -f sonar_api_get

  run fetch_hotspot_details "HS1" "java:S3649"
  [ "$status" -eq 0 ]
  html=$(echo "$output" | jq -r '.whyHtml')
  [[ "$html" == *"<p>"* ]]
  [[ "$html" == *"malicious SQL"* ]]
}

@test "fetch_hotspot_details: extracts riskText from riskDescription" {
  sonar_api_get() { cat "${FIXTURES}/hotspot_show.json"; }
  export -f sonar_api_get

  run fetch_hotspot_details "HS1" "java:S3649"
  [ "$status" -eq 0 ]
  risk=$(echo "$output" | jq -r '.riskText')
  [[ "$risk" == *"SQL injection occurs"* ]]
}

@test "fetch_hotspot_details: extracts howToFixHtml from fixRecommendations" {
  sonar_api_get() { cat "${FIXTURES}/hotspot_show.json"; }
  export -f sonar_api_get

  run fetch_hotspot_details "HS1" "java:S3649"
  [ "$status" -eq 0 ]
  fix=$(echo "$output" | jq -r '.howToFixHtml')
  [[ "$fix" == *"PreparedStatement"* ]]
}

@test "fetch_hotspot_details: caches by rule key, not hotspot key" {
  export _CALL_CTR
  _CALL_CTR=$(counter_file_new)

  sonar_api_get() {
    counter_file_increment "$_CALL_CTR" >/dev/null
    cat "${FIXTURES}/hotspot_show.json"
  }
  export -f sonar_api_get counter_file_increment

  # Two different hotspot keys, same rule key → only one fetch
  fetch_hotspot_details "HS1" "java:S3649" >/dev/null
  fetch_hotspot_details "HS2" "java:S3649" >/dev/null
  fetch_hotspot_details "HS3" "java:S3649" >/dev/null
  local count
  count=$(cat "$_CALL_CTR")
  rm -f "$_CALL_CTR"
  [ "$count" -eq 1 ]
}

@test "fetch_hotspot_details: returns empty object on API failure" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_hotspot_details "HS1" "java:S3649"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

# ===========================================================================
# fetch_source_snippet
# ===========================================================================

@test "fetch_source_snippet: returns lines window with surrounding context" {
  sonar_api_get() { cat "${FIXTURES}/source_raw.txt"; }
  export -f sonar_api_get

  run fetch_source_snippet "my-project:src/Sample.java" 14 14 2
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq '.lines | length')
  # start=14 ± 2 → lines 12..16 = 5 lines
  [ "$count" -eq 5 ]
}

@test "fetch_source_snippet: marks the affected lines as highlighted" {
  sonar_api_get() { cat "${FIXTURES}/source_raw.txt"; }
  export -f sonar_api_get

  run fetch_source_snippet "my-project:src/Sample.java" 14 15 1
  [ "$status" -eq 0 ]
  hl_count=$(echo "$output" | jq '[.lines[] | select(.highlighted == true)] | length')
  total_count=$(echo "$output" | jq '.lines | length')
  [ "$hl_count" -eq 2 ]
  # Range is 14-15 with 1 line context → 13,14,15,16 = 4 lines, 2 highlighted
  [ "$total_count" -eq 4 ]
}

@test "fetch_source_snippet: line numbers are 1-based and contiguous" {
  sonar_api_get() { cat "${FIXTURES}/source_raw.txt"; }
  export -f sonar_api_get

  run fetch_source_snippet "my-project:src/Sample.java" 5 5 0
  [ "$status" -eq 0 ]
  first_n=$(echo "$output" | jq '.lines[0].n')
  last_n=$(echo "$output" | jq '.lines[-1].n')
  [ "$first_n" = "5" ]
  [ "$last_n" = "5" ]
}

@test "fetch_source_snippet: caches per component" {
  export _CALL_CTR
  _CALL_CTR=$(counter_file_new)

  sonar_api_get() {
    counter_file_increment "$_CALL_CTR" >/dev/null
    cat "${FIXTURES}/source_raw.txt"
  }
  export -f sonar_api_get counter_file_increment

  fetch_source_snippet "my-project:src/Sample.java" 5  5  0 >/dev/null
  fetch_source_snippet "my-project:src/Sample.java" 14 15 1 >/dev/null
  fetch_source_snippet "my-project:src/Sample.java" 22 26 2 >/dev/null
  local count
  count=$(cat "$_CALL_CTR")
  rm -f "$_CALL_CTR"
  [ "$count" -eq 1 ]
}

@test "fetch_source_snippet: clamps start_line to 1 when context goes negative" {
  sonar_api_get() { cat "${FIXTURES}/source_raw.txt"; }
  export -f sonar_api_get

  run fetch_source_snippet "my-project:src/Sample.java" 1 1 5
  [ "$status" -eq 0 ]
  first_n=$(echo "$output" | jq '.lines[0].n')
  [ "$first_n" = "1" ]
}

@test "fetch_source_snippet: handles end_line beyond file length" {
  sonar_api_get() { cat "${FIXTURES}/source_raw.txt"; }
  export -f sonar_api_get

  run fetch_source_snippet "my-project:src/Sample.java" 25 9999 0
  [ "$status" -eq 0 ]
  count=$(echo "$output" | jq '.lines | length')
  [ "$count" -gt 0 ]
}

@test "fetch_source_snippet: returns empty object on API failure" {
  sonar_api_get() { return 1; }
  export -f sonar_api_get

  run fetch_source_snippet "my-project:src/Missing.java" 1 1 3
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "fetch_source_snippet: returns empty object on missing line" {
  sonar_api_get() { cat "${FIXTURES}/source_raw.txt"; }
  export -f sonar_api_get

  run fetch_source_snippet "my-project:src/Sample.java" "" "" 3
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "fetch_source_snippet: negative-caches a failed component" {
  export _CALL_CTR
  _CALL_CTR=$(counter_file_new)

  sonar_api_get() {
    counter_file_increment "$_CALL_CTR" >/dev/null
    return 1
  }
  export -f sonar_api_get counter_file_increment

  fetch_source_snippet "my-project:src/Missing.java" 1 1 3 >/dev/null
  fetch_source_snippet "my-project:src/Missing.java" 2 2 3 >/dev/null
  fetch_source_snippet "my-project:src/Missing.java" 3 3 3 >/dev/null
  local count
  count=$(cat "$_CALL_CTR")
  rm -f "$_CALL_CTR"
  [ "$count" -eq 1 ]
}

# ===========================================================================
# enrich_issue_objects
# ===========================================================================

@test "enrich_issue_objects: short-circuits to passthrough when both flags off" {
  export INCLUDE_RULE_DESCRIPTIONS=""
  export INCLUDE_CODE_SNIPPETS="false"

  sonar_api_get() {
    echo "SHOULD NOT BE CALLED" >&2
    return 1
  }
  export -f sonar_api_get

  local issues='[{"key":"K1","rule":"java:S2259","component":"p:src/A.java","line":5,"startLine":5,"endLine":5}]'
  run enrich_issue_objects "$issues"
  [ "$status" -eq 0 ]
  [ "$output" = "$issues" ]
}

@test "enrich_issue_objects: adds ruleDescription when INCLUDE_RULE_DESCRIPTIONS is set" {
  export INCLUDE_RULE_DESCRIPTIONS="short"
  export INCLUDE_CODE_SNIPPETS="false"

  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get

  local issues='[{"key":"K1","rule":"java:S2259","component":"p:src/A.java","line":5,"startLine":5,"endLine":5}]'
  run enrich_issue_objects "$issues"
  [ "$status" -eq 0 ]
  has_desc=$(echo "$output" | jq '.[0] | has("ruleDescription")')
  [ "$has_desc" = "true" ]
}

@test "enrich_issue_objects: adds codeSnippet when INCLUDE_CODE_SNIPPETS is true" {
  export INCLUDE_RULE_DESCRIPTIONS=""
  export INCLUDE_CODE_SNIPPETS="true"
  export SNIPPET_CONTEXT="2"

  sonar_api_get() { cat "${FIXTURES}/source_raw.txt"; }
  export -f sonar_api_get

  local issues='[{"key":"K1","rule":"java:S2259","component":"p:src/A.java","line":14,"startLine":14,"endLine":14}]'
  run enrich_issue_objects "$issues"
  [ "$status" -eq 0 ]
  has_snip=$(echo "$output" | jq '.[0] | has("codeSnippet")')
  [ "$has_snip" = "true" ]
}

@test "enrich_issue_objects: preserves all original fields" {
  export INCLUDE_RULE_DESCRIPTIONS="short"
  export INCLUDE_CODE_SNIPPETS="false"

  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get

  local issues='[{"key":"K1","severity":"CRITICAL","type":"BUG","rule":"java:S2259","component":"p:src/A.java","line":5,"startLine":5,"endLine":5,"effort":"5min","creationDate":"2024-01-01"}]'
  run enrich_issue_objects "$issues"
  [ "$status" -eq 0 ]
  key=$(echo "$output" | jq -r '.[0].key')
  sev=$(echo "$output" | jq -r '.[0].severity')
  effort=$(echo "$output" | jq -r '.[0].effort')
  [ "$key" = "K1" ]
  [ "$sev" = "CRITICAL" ]
  [ "$effort" = "5min" ]
}

# ===========================================================================
# enrich_hotspot_objects
# ===========================================================================

@test "enrich_hotspot_objects: short-circuits when both flags off" {
  export INCLUDE_RULE_DESCRIPTIONS=""
  export INCLUDE_CODE_SNIPPETS="false"

  sonar_api_get() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
  export -f sonar_api_get

  local hotspots='[{"key":"HS1","rule":"java:S3649","component":"p:src/A.java","line":5,"startLine":5,"endLine":5}]'
  run enrich_hotspot_objects "$hotspots"
  [ "$status" -eq 0 ]
  [ "$output" = "$hotspots" ]
}

@test "enrich_hotspot_objects: adds ruleDescription with riskText" {
  export INCLUDE_RULE_DESCRIPTIONS="short"
  export INCLUDE_CODE_SNIPPETS="false"

  sonar_api_get() { cat "${FIXTURES}/hotspot_show.json"; }
  export -f sonar_api_get

  local hotspots='[{"key":"HS1","rule":"java:S3649","component":"p:src/Db.java","line":21,"startLine":21,"endLine":21}]'
  run enrich_hotspot_objects "$hotspots"
  [ "$status" -eq 0 ]
  has_risk=$(echo "$output" | jq '.[0].ruleDescription | has("riskText")')
  [ "$has_risk" = "true" ]
}

# ==============================================================================
# Additional edge / branch coverage
# ==============================================================================

@test "fetch_hotspot_details: returns empty object when hotspot key missing" {
  run fetch_hotspot_details "" "java:S1"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "fetch_source_snippet: defaults end_line to start_line when missing" {
  sonar_api_get() { printf 'l1\nl2\nl3\nl4\nl5\n'; }
  export -f sonar_api_get
  run fetch_source_snippet "p:F.java" "3" "" "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"endLine"'* ]]
}

@test "fetch_source_snippet: returns empty for non-numeric line" {
  run fetch_source_snippet "p:F.java" "abc" "5" "3"
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "fetch_source_snippet: clamps non-numeric context to default" {
  sonar_api_get() { printf 'a\nb\nc\nd\ne\nf\ng\n'; }
  export -f sonar_api_get
  run fetch_source_snippet "p:F.java" "4" "4" "xyz"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"lines"'* ]]
}

@test "enrich_issue_objects: pre-fetches rule details when descriptions enabled" {
  export INCLUDE_RULE_DESCRIPTIONS="short"
  export INCLUDE_CODE_SNIPPETS="false"
  sonar_api_get() { cat "${FIXTURES}/rule_show.json"; }
  export -f sonar_api_get
  local issues='[{"key":"I1","rule":"java:S2259","component":"p:Main.java","line":42,"startLine":42,"endLine":42}]'
  run enrich_issue_objects "$issues"
  [ "$status" -eq 0 ]
  has_rd=$(echo "$output" | jq '.[0] | has("ruleDescription")')
  [ "$has_rd" = "true" ]
}

@test "enrich_issue_objects: includes code snippet when snippets enabled" {
  export INCLUDE_RULE_DESCRIPTIONS=""
  export INCLUDE_CODE_SNIPPETS="true"
  export SNIPPET_CONTEXT="2"
  sonar_api_get() { printf 'l1\nl2\nl3\nl4\nl5\n'; }
  export -f sonar_api_get
  local issues='[{"key":"I1","rule":"java:S1","component":"p:Main.java","line":3,"startLine":3,"endLine":3}]'
  run enrich_issue_objects "$issues"
  [ "$status" -eq 0 ]
  has_cs=$(echo "$output" | jq '.[0] | has("codeSnippet")')
  [ "$has_cs" = "true" ]
}

@test "enrich_hotspot_objects: includes code snippet when snippets enabled" {
  export INCLUDE_RULE_DESCRIPTIONS=""
  export INCLUDE_CODE_SNIPPETS="true"
  export SNIPPET_CONTEXT="2"
  sonar_api_get() { printf 'a\nb\nc\nd\ne\n'; }
  export -f sonar_api_get
  local hs='[{"key":"HS1","rule":"java:S3649","component":"p:Db.java","line":3,"startLine":3,"endLine":3}]'
  run enrich_hotspot_objects "$hs"
  [ "$status" -eq 0 ]
  has_cs=$(echo "$output" | jq '.[0] | has("codeSnippet")')
  [ "$has_cs" = "true" ]
}
