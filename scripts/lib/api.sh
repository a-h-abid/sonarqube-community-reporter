#!/usr/bin/env bash
# ==============================================================================
# api.sh — Shared SonarQube API helper functions
# ==============================================================================
set -euo pipefail

# Colours (disabled when stdout is not a terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# sonar_api_get <endpoint> [extra_curl_args...]
#   Makes an authenticated GET request to the SonarQube API.
#   Prints the JSON response body to stdout.
#   Returns non-zero on HTTP errors (4xx/5xx).
# ---------------------------------------------------------------------------
sonar_api_get() {
  local endpoint="$1"; shift
  local url="${SONAR_URL}/api/${endpoint}"
  local http_code body

  # Use a temp file for body so we can capture HTTP status separately
  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' RETURN

  http_code=$(curl -s -o "$tmpfile" -w '%{http_code}' \
    -H "Authorization: Bearer ${SONAR_TOKEN}" \
    "$@" \
    "$url")

  body=$(cat "$tmpfile")

  if [[ "$http_code" -ge 400 ]]; then
    log_error "API ${http_code} — GET ${endpoint}"
    log_error "Response: ${body}"
    return 1
  fi

  echo "$body"
}

# ---------------------------------------------------------------------------
# sonar_api_paginated <endpoint> <jq_items_path> <max_pages> [extra_params...]
#   Fetches all pages from a paginated SonarQube API endpoint.
#   Outputs a JSON array with all collected items merged.
#
#   jq_items_path  — jq expression to extract the items array, e.g. ".issues"
#   max_pages      — safety limit (0 = unlimited)
#   extra_params   — additional query params, e.g. "types=BUG" "ps=500"
# ---------------------------------------------------------------------------
sonar_api_paginated() {
  local endpoint="$1"
  local jq_path="$2"
  local max_pages="${3:-0}"
  shift 3

  local page=1
  local page_size=500
  local all_items="[]"
  local params=("$@")

  while true; do
    local query_string
    query_string=$(IFS='&'; echo "${params[*]+"${params[*]}"}")
    [[ -n "$query_string" ]] && query_string="${query_string}&"
    query_string="${query_string}p=${page}&ps=${page_size}"

    local response
    response=$(sonar_api_get "${endpoint}?${query_string}") || return 1

    local items
    items=$(echo "$response" | jq -c "${jq_path} // []")

    local count
    count=$(echo "$items" | jq 'length')

    # Merge into accumulator
    all_items=$(echo "$all_items" "$items" | jq -s '.[0] + .[1]')

    # Check if we have more pages
    local total
    total=$(echo "$response" | jq '.paging.total // .total // 0')
    local fetched
    fetched=$(echo "$all_items" | jq 'length')

    if [[ "$fetched" -ge "$total" ]] || [[ "$count" -eq 0 ]]; then
      break
    fi

    page=$((page + 1))

    if [[ "$max_pages" -gt 0 ]] && [[ "$page" -gt "$max_pages" ]]; then
      log_warn "Reached max pages limit (${max_pages}) for ${endpoint}"
      break
    fi
  done

  echo "$all_items"
}

# ---------------------------------------------------------------------------
# check_connectivity
#   Validates that SONAR_URL and SONAR_TOKEN are set, SonarQube is reachable,
#   and the token is valid.
# ---------------------------------------------------------------------------
check_connectivity() {
  if [[ -z "${SONAR_URL:-}" ]]; then
    log_error "SONAR_URL is not set"
    return 1
  fi
  if [[ -z "${SONAR_TOKEN:-}" ]]; then
    log_error "SONAR_TOKEN is not set"
    return 1
  fi

  log_info "Checking connectivity to ${SONAR_URL} ..."

  local response
  response=$(sonar_api_get "system/status") || {
    log_error "Cannot reach SonarQube at ${SONAR_URL}"
    return 1
  }

  local status
  status=$(echo "$response" | jq -r '.status // "UNKNOWN"')

  if [[ "$status" != "UP" ]]; then
    log_error "SonarQube status is '${status}' (expected 'UP')"
    return 1
  fi

  # Validate authentication by hitting a protected endpoint
  local auth_check
  auth_check=$(sonar_api_get "authentication/validate") || {
    log_error "Authentication check failed"
    return 1
  }

  local valid
  valid=$(echo "$auth_check" | jq -r '.valid // false')

  if [[ "$valid" != "true" ]]; then
    log_error "Token authentication failed — ensure SONAR_TOKEN is valid"
    return 1
  fi

  log_ok "Connected to SonarQube (status: UP, auth: valid)"
}

# ---------------------------------------------------------------------------
# rating_to_letter <numeric_rating>
#   Converts SonarQube numeric rating (1.0–5.0) to letter grade (A–E).
# ---------------------------------------------------------------------------
rating_to_letter() {
  local rating="${1:-0}"
  # Handle float values — take integer part
  local int_rating
  int_rating=$(echo "$rating" | awk '{printf "%d", $1}')

  case "$int_rating" in
    1) echo "A" ;;
    2) echo "B" ;;
    3) echo "C" ;;
    4) echo "D" ;;
    5) echo "E" ;;
    *) echo "?" ;;
  esac
}

# ---------------------------------------------------------------------------
# format_duration <minutes>
#   Converts minutes to a human-readable duration string.
# ---------------------------------------------------------------------------
format_duration() {
  local minutes="${1:-0}"
  local int_min
  int_min=$(echo "$minutes" | awk '{printf "%d", $1}')

  if [[ "$int_min" -lt 60 ]]; then
    echo "${int_min}min"
  elif [[ "$int_min" -lt 1440 ]]; then
    echo "$((int_min / 60))h $((int_min % 60))min"
  else
    echo "$((int_min / 1440))d $((int_min % 1440 / 60))h"
  fi
}

# ---------------------------------------------------------------------------
# safe_jq <json_string> <jq_expression> [default_value]
#   Safely extract a value using jq, returning default if null/missing.
# ---------------------------------------------------------------------------
safe_jq() {
  local json="$1"
  local expr="$2"
  local default="${3:-N/A}"

  local result
  result=$(echo "$json" | jq -r "${expr} // empty" 2>/dev/null) || true

  if [[ -z "$result" ]]; then
    echo "$default"
  else
    echo "$result"
  fi
}
