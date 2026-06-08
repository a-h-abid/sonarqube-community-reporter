#!/usr/bin/env bash
# ==============================================================================
# api.sh — Shared SonarQube API helper functions
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_API_SH_LOADED:-}" ]] && return 0
_API_SH_LOADED=1

set -euo pipefail

_API_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_API_PROJECT_ROOT="$(cd "${_API_SCRIPT_DIR}/../.." && pwd)"

# Colours (disabled when stdout is not a terminal)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

# ---------------------------------------------------------------------------
# SonarCloud configuration globals
#   SONAR_CLOUD        — "true" when targeting SonarCloud; else "false"
#   SONAR_ORGANIZATION — SonarCloud organization key (required when SONAR_CLOUD=true)
# ---------------------------------------------------------------------------
SONAR_CLOUD="${SONAR_CLOUD:-false}"
SONAR_ORGANIZATION="${SONAR_ORGANIZATION:-}"

# ---------------------------------------------------------------------------
# detect_sonarcloud
#   Sets SONAR_CLOUD=true when the host in SONAR_URL is exactly sonarcloud.io
#   or a subdomain ending in .sonarcloud.io.
#   Safe to call multiple times (idempotent — only ever sets true).
# ---------------------------------------------------------------------------
detect_sonarcloud() {
  local url="${SONAR_URL:-}"
  # Extract host by stripping scheme, path, and port
  local host="${url#*://}"
  host="${host%%/*}"
  host="${host%%:*}"
  if [[ "$host" == "sonarcloud.io" ]] || [[ "$host" == *.sonarcloud.io ]]; then
    SONAR_CLOUD=true
  fi
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info()  { echo -e "${CYAN}[INFO]${NC}  $*" >&2; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ---------------------------------------------------------------------------
# Project-local temp helpers
# ---------------------------------------------------------------------------
project_tmp_dir() {
  local preferred_tmp_dir="${SONAR_REPORT_TMP_DIR:-${_API_PROJECT_ROOT}/tmp}"
  if mkdir -p "$preferred_tmp_dir" 2>/dev/null && [[ -w "$preferred_tmp_dir" ]]; then
    echo "$preferred_tmp_dir"
    return 0
  fi

  fallback_tmp_dir
}

fallback_tmp_dir() {
  local tmp_dir="${TMPDIR:-/tmp}/sonar-report"
  mkdir -p "$tmp_dir" || return 1
  [[ -w "$tmp_dir" ]] || return 1
  echo "$tmp_dir"
}

create_temp_path() {
  local temp_kind="${1:-}"
  case "$temp_kind" in
    file|dir) ;;
    *)
      log_error "Unsupported temp path kind: ${temp_kind}"
      return 1
      ;;
  esac

  local preferred_tmp_dir="${SONAR_REPORT_TMP_DIR:-${_API_PROJECT_ROOT}/tmp}"
  local tmp_path
  if mkdir -p "$preferred_tmp_dir" 2>/dev/null && [[ -w "$preferred_tmp_dir" ]]; then
    if [[ "$temp_kind" == "dir" ]]; then
      tmp_path=$(mktemp -d "${preferred_tmp_dir}/sonar-report.XXXXXX" 2>/dev/null) || true
    else
      tmp_path=$(mktemp "${preferred_tmp_dir}/sonar-report.XXXXXX" 2>/dev/null) || true
    fi
    if [[ -n "$tmp_path" ]]; then
      echo "$tmp_path"
      return 0
    fi
  fi

  local tmp_dir
  tmp_dir=$(fallback_tmp_dir) || return 1
  if [[ "$temp_kind" == "dir" ]]; then
    mktemp -d "${tmp_dir}/sonar-report.XXXXXX"
  else
    mktemp "${tmp_dir}/sonar-report.XXXXXX"
  fi
}

create_temp_file() {
  create_temp_path "file"
}

create_temp_dir() {
  create_temp_path "dir"
}

# ---------------------------------------------------------------------------
# sonar_api_get <endpoint> [extra_curl_args...]
#   Makes an authenticated GET request to the SonarQube/SonarCloud API.
#   Prints the JSON response body to stdout.
#   Returns non-zero on HTTP errors (4xx/5xx).
#
#   When SONAR_ORGANIZATION is set the organization query parameter is
#   appended automatically (required by most SonarCloud endpoints).
# ---------------------------------------------------------------------------
sonar_api_get() {
  local endpoint="$1"; shift

  # Inject organization param transparently for SonarCloud.
  # Skip injection when SONAR_ORGANIZATION is empty or when the endpoint
  # already contains organization= (prevents duplicate parameters).
  if [[ -n "${SONAR_ORGANIZATION:-}" ]] && [[ "$endpoint" != *"organization="* ]]; then
    local org_encoded
    org_encoded=$(printf '%s' "${SONAR_ORGANIZATION}" | jq -sRr @uri)
    if [[ "$endpoint" == *"?"* ]]; then
      endpoint="${endpoint}&organization=${org_encoded}"
    else
      endpoint="${endpoint}?organization=${org_encoded}"
    fi
  fi

  local url="${SONAR_URL}/api/${endpoint}"
  local http_code body

  # Use a temp file for body so we can capture HTTP status separately
  local tmpfile
  tmpfile=$(create_temp_file)
  # Guard prevents the trap from failing when it fires in an outer caller's
  # scope (where $tmpfile is unset) due to bash RETURN traps being shell-wide.
  trap '[[ -n "${tmpfile:-}" ]] && rm -f "$tmpfile"' RETURN

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
  local total_fetched=0
  local params=("$@")

  # Accumulate pages into a temp file (one JSON array per line) to avoid
  # O(n²) in-memory merging that degrades badly on large datasets.
  local tmp_pages
  tmp_pages=$(create_temp_file)
  trap '[[ -n "${tmp_pages:-}" ]] && rm -f "$tmp_pages"' RETURN

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

    # Append page array to temp file (one JSON array per line)
    echo "$items" >> "$tmp_pages"
    total_fetched=$((total_fetched + count))

    # Check if we have more pages
    local total
    total=$(echo "$response" | jq '.paging.total // .total // 0')

    if [[ "$total_fetched" -ge "$total" ]] || [[ "$count" -eq 0 ]]; then
      break
    fi

    page=$((page + 1))

    if [[ "$max_pages" -gt 0 ]] && [[ "$page" -gt "$max_pages" ]]; then
      log_warn "Reached max pages limit (${max_pages}) for ${endpoint}"
      break
    fi
  done

  # Merge all page arrays into a single flat array
  jq -s 'add // []' "$tmp_pages"
}

# ---------------------------------------------------------------------------
# check_connectivity
#   Validates that SONAR_URL and SONAR_TOKEN are set, the server is reachable,
#   and the token is valid.
#
#   SonarCloud mode (SONAR_CLOUD=true or auto-detected from URL):
#     Skips the system/status check (endpoint does not exist on SonarCloud)
#     and validates only via authentication/validate.
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

  detect_sonarcloud

  log_info "Checking connectivity to ${SONAR_URL} ..."

  if [[ "${SONAR_CLOUD:-false}" != "true" ]]; then
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

  if [[ "${SONAR_CLOUD:-false}" == "true" ]]; then
    log_ok "Connected to SonarCloud (auth: valid)"
  else
    log_ok "Connected to SonarQube (status: UP, auth: valid)"
  fi
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
