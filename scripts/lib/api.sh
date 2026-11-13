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
# HTTP resilience + concurrency settings (read at call time, so they can be
# set by CLI flags, environment variables, or the config file):
#   HTTP_RETRIES          — retries after a transient failure   (default 3)
#   HTTP_RETRY_DELAY      — base backoff seconds, doubled per retry (default 2)
#   HTTP_CONNECT_TIMEOUT  — seconds to establish a connection   (default 10)
#   HTTP_TIMEOUT          — seconds per request, 0 = unlimited  (default 120)
#   CONCURRENCY           — parallel API workers; 1 = sequential (default 1
#                           here; the CLI defaults it to 4)
# ---------------------------------------------------------------------------
_HTTP_RETRY_MAX_WAIT=60

# http_setting <value> <default> — <value> when it is a non-negative integer.
http_setting() {
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    echo "$1"
  else
    echo "$2"
  fi
}

# concurrency_level — CONCURRENCY when it is a positive integer, otherwise 1.
concurrency_level() {
  if [[ "${CONCURRENCY:-}" =~ ^[1-9][0-9]*$ ]]; then
    echo "$CONCURRENCY"
  else
    echo 1
  fi
}

# ---------------------------------------------------------------------------
# http_retry_wait <attempt> <headers_file>
#   Seconds to sleep before retry number <attempt>: exponential backoff from
#   HTTP_RETRY_DELAY, raised to the server's Retry-After (seconds form) when
#   that is longer, capped at _HTTP_RETRY_MAX_WAIT.
# ---------------------------------------------------------------------------
http_retry_wait() {
  local attempt="$1"
  local headers_file="${2:-}"

  local delay wait_secs
  delay=$(http_setting "${HTTP_RETRY_DELAY:-}" 2)
  # Clamp the exponent so a large retry count cannot overflow the shift.
  local exponent=$((attempt - 1))
  [[ "$exponent" -gt 10 ]] && exponent=10
  wait_secs=$((delay * (1 << exponent)))

  if [[ -n "$headers_file" && -s "$headers_file" ]]; then
    local retry_after
    # kcov-skip-start
    retry_after=$(awk 'tolower($1) == "retry-after:" { v = $2 } END { gsub(/[^0-9]/, "", v); print v }' \
      "$headers_file" 2>/dev/null) || retry_after=""
    # kcov-skip-end
    if [[ "$retry_after" =~ ^[0-9]+$ ]] && [[ "$retry_after" -gt "$wait_secs" ]]; then
      wait_secs="$retry_after"
    fi
  fi

  [[ "$wait_secs" -gt "$_HTTP_RETRY_MAX_WAIT" ]] && wait_secs="$_HTTP_RETRY_MAX_WAIT"
  echo "$wait_secs"
}

# ---------------------------------------------------------------------------
# run_parallel <max_jobs> <out_dir> <func> [item...]
#   Runs "<func> <item>" for every item in background subshells, at most
#   <max_jobs> at a time. Job N (0-based, in item order) writes its stdout to
#   <out_dir>/N.out and gets <out_dir>/N.ok on success. Each job's stderr is
#   buffered and replayed in item order once all jobs finish, so log output
#   stays grouped instead of interleaving.
#   Jobs run with CONCURRENCY=1 so nested fan-out cannot multiply the load.
#   Returns 1 when any job failed. Jobs are subshells: variables they set
#   (caches included) do not reach the caller — read the .out files instead.
# ---------------------------------------------------------------------------
run_parallel() {
  local max_jobs="$1"
  local out_dir="$2"
  local func="$3"
  shift 3

  [[ "$max_jobs" =~ ^[1-9][0-9]*$ ]] || max_jobs=1

  local idx=0 running=0 item
  for item in "$@"; do
    if [[ "$running" -ge "$max_jobs" ]]; then
      wait -n 2>/dev/null || true
      running=$((running - 1))
    fi
    (
      CONCURRENCY=1 "$func" "$item" > "${out_dir}/${idx}.out" 2> "${out_dir}/${idx}.err" \
        && : > "${out_dir}/${idx}.ok"
    ) &
    idx=$((idx + 1))
    running=$((running + 1))
  done
  wait || true

  local failed=0 i
  for ((i = 0; i < idx; i++)); do
    [[ -s "${out_dir}/${i}.err" ]] && cat "${out_dir}/${i}.err" >&2
    [[ -f "${out_dir}/${i}.ok" ]] || failed=$((failed + 1))
  done

  [[ "$failed" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# sonar_api_get <endpoint> [extra_curl_args...]
#   Makes an authenticated GET request to the SonarQube/SonarCloud API.
#   Prints the JSON response body to stdout.
#   Returns non-zero on HTTP errors (4xx/5xx) and on transport failures.
#
#   Transient failures (connection errors, timeouts, HTTP 408/429/502/503/504)
#   are retried up to HTTP_RETRIES times with exponential backoff. Every
#   request is bounded by HTTP_CONNECT_TIMEOUT and HTTP_TIMEOUT.
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

  local retries connect_timeout max_time
  retries=$(http_setting "${HTTP_RETRIES:-}" 3)
  connect_timeout=$(http_setting "${HTTP_CONNECT_TIMEOUT:-}" 10)
  max_time=$(http_setting "${HTTP_TIMEOUT:-}" 120)

  # Use a temp file for body so we can capture HTTP status separately. The
  # response headers go to a sibling file (read only to honour Retry-After).
  local tmpfile
  tmpfile=$(create_temp_file)
  # Guard prevents the trap from failing when it fires in an outer caller's
  # scope (where $tmpfile is unset) due to bash RETURN traps being shell-wide.
  trap '[[ -n "${tmpfile:-}" ]] && rm -f "$tmpfile" "${tmpfile}.hdr"' RETURN

  local attempt=0 curl_rc reason wait_secs
  while true; do
    attempt=$((attempt + 1))
    curl_rc=0
    : > "$tmpfile"
    http_code=$(curl -s -o "$tmpfile" -D "${tmpfile}.hdr" -w '%{http_code}' \
      --connect-timeout "$connect_timeout" --max-time "$max_time" \
      -H "Authorization: Bearer ${SONAR_TOKEN}" \
      "$@" \
      "$url") || curl_rc=$?
    [[ "$http_code" =~ ^[0-9]+$ ]] || http_code=0

    # Transient failures only: transport errors (refused, reset, timeout, DNS)
    # and the gateway/throttling statuses. Other 4xx/5xx are deterministic.
    if [[ "$curl_rc" -ne 0 ]]; then
      reason="curl exit ${curl_rc}"
    else
      case "$http_code" in
        408|429|502|503|504) reason="HTTP ${http_code}" ;;
        *) break ;;
      esac
    fi

    [[ "$attempt" -gt "$retries" ]] && break

    wait_secs=$(http_retry_wait "$attempt" "${tmpfile}.hdr")
    log_warn "GET ${endpoint} failed (${reason}) — retry ${attempt}/${retries} in ${wait_secs}s"
    sleep "$wait_secs"
  done

  if [[ "$curl_rc" -ne 0 ]]; then
    log_error "Request failed (curl exit ${curl_rc}) — GET ${endpoint}"
    return 1
  fi

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
