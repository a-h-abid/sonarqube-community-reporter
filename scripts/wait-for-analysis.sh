#!/usr/bin/env bash
# ==============================================================================
# wait-for-analysis.sh — Poll SonarQube Compute Engine until analysis completes
# ==============================================================================
# Exports:  ANALYSIS_ID  (on success)
#
# Usage:
#   source scripts/wait-for-analysis.sh
#   wait_for_analysis                   # Uses SONAR_TASK_ID or polls component
#
# Environment:
#   SONAR_TASK_ID    — (optional) specific CE task ID to track
#   SONAR_PROJECT_KEY — project key (used if SONAR_TASK_ID is not set)
#   POLL_INTERVAL    — seconds between polls (default: 5)
#   POLL_TIMEOUT     — max seconds to wait (default: 300)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/api.sh
source "${SCRIPT_DIR}/lib/api.sh"

# ---------------------------------------------------------------------------
# wait_for_analysis
#   Polls until the SonarQube background analysis is finished.
#   Sets global ANALYSIS_ID on success.
# ---------------------------------------------------------------------------
wait_for_analysis() {
  local interval="${POLL_INTERVAL:-5}"
  local timeout="${POLL_TIMEOUT:-300}"
  local elapsed=0

  ANALYSIS_ID=""

  if [[ -n "${SONAR_TASK_ID:-}" ]]; then
    _poll_by_task_id "$interval" "$timeout"
  else
    _poll_by_component "$interval" "$timeout"
  fi
}

# ---------------------------------------------------------------------------
# _poll_by_task_id <interval> <timeout>
#   Tracks a specific Compute Engine task by its ID.
# ---------------------------------------------------------------------------
_poll_by_task_id() {
  local interval="$1"
  local timeout="$2"
  local elapsed=0

  log_info "Waiting for CE task ${SONAR_TASK_ID} to complete (timeout: ${timeout}s) ..."

  while true; do
    local response
    response=$(sonar_api_get "ce/task?id=${SONAR_TASK_ID}") || {
      log_error "Failed to query CE task"
      return 1
    }

    local status
    status=$(echo "$response" | jq -r '.task.status // "UNKNOWN"')

    case "$status" in
      SUCCESS)
        ANALYSIS_ID=$(echo "$response" | jq -r '.task.analysisId // empty')
        log_ok "Analysis completed (task: ${SONAR_TASK_ID}, analysisId: ${ANALYSIS_ID:-N/A})"
        export ANALYSIS_ID
        return 0
        ;;
      FAILED)
        local error_msg
        error_msg=$(echo "$response" | jq -r '.task.errorMessage // "unknown error"')
        log_error "Analysis FAILED: ${error_msg}"
        return 1
        ;;
      CANCELED)
        log_error "Analysis was CANCELED"
        return 1
        ;;
      PENDING|IN_PROGRESS)
        log_info "  Status: ${status} (${elapsed}s / ${timeout}s)"
        ;;
      *)
        log_warn "  Unknown status: ${status}"
        ;;
    esac

    if [[ "$elapsed" -ge "$timeout" ]]; then
      log_error "Timed out waiting for analysis after ${timeout}s"
      return 1
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
}

# ---------------------------------------------------------------------------
# _poll_by_component <interval> <timeout>
#   Polls the component's CE queue until no tasks are PENDING/IN_PROGRESS.
# ---------------------------------------------------------------------------
_poll_by_component() {
  local interval="$1"
  local timeout="$2"
  local elapsed=0

  if [[ -z "${SONAR_PROJECT_KEY:-}" ]]; then
    log_error "Neither SONAR_TASK_ID nor SONAR_PROJECT_KEY is set — cannot wait"
    return 1
  fi

  log_info "Waiting for analysis on project '${SONAR_PROJECT_KEY}' (timeout: ${timeout}s) ..."

  while true; do
    local response
    response=$(sonar_api_get "ce/component?component=${SONAR_PROJECT_KEY}") || {
      log_error "Failed to query CE component status"
      return 1
    }

    # Check if there's a currently running task
    local current_status
    current_status=$(echo "$response" | jq -r '.current.status // "NONE"')

    local queue_count
    queue_count=$(echo "$response" | jq '.queue | length // 0')

    case "$current_status" in
      SUCCESS)
        if [[ "$queue_count" -eq 0 ]]; then
          ANALYSIS_ID=$(echo "$response" | jq -r '.current.analysisId // empty')
          log_ok "Analysis completed (analysisId: ${ANALYSIS_ID:-N/A})"
          export ANALYSIS_ID
          return 0
        fi
        log_info "  Last task succeeded, but ${queue_count} task(s) still queued (${elapsed}s / ${timeout}s)"
        ;;
      FAILED)
        local error_msg
        error_msg=$(echo "$response" | jq -r '.current.errorMessage // "unknown error"')
        log_error "Latest analysis FAILED: ${error_msg}"
        return 1
        ;;
      CANCELED)
        log_error "Latest analysis was CANCELED"
        return 1
        ;;
      PENDING|IN_PROGRESS)
        log_info "  Status: ${current_status}, queued: ${queue_count} (${elapsed}s / ${timeout}s)"
        ;;
      NONE)
        # No task found at all — check if there was a previous analysis
        local has_current
        has_current=$(echo "$response" | jq 'has("current")')
        if [[ "$has_current" == "false" ]]; then
          log_warn "No analysis has ever been run for '${SONAR_PROJECT_KEY}'"
          log_info "  Proceeding with current data (if any exists)"
          return 0
        fi
        log_info "  No active task (${elapsed}s / ${timeout}s)"
        # If no active task and no queue, the analysis is done
        if [[ "$queue_count" -eq 0 ]]; then
          ANALYSIS_ID=$(echo "$response" | jq -r '.current.analysisId // empty')
          log_ok "No pending analysis — using latest (analysisId: ${ANALYSIS_ID:-N/A})"
          export ANALYSIS_ID
          return 0
        fi
        ;;
    esac

    if [[ "$elapsed" -ge "$timeout" ]]; then
      log_error "Timed out waiting for analysis after ${timeout}s"
      return 1
    fi

    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
}

# ---------------------------------------------------------------------------
# extract_task_id_from_report <path_to_report_task_txt>
#   Parses .scannerwork/report-task.txt to extract the CE task ID.
# ---------------------------------------------------------------------------
extract_task_id_from_report() {
  local report_file="${1:-.scannerwork/report-task.txt}"

  if [[ ! -f "$report_file" ]]; then
    log_warn "report-task.txt not found at ${report_file}"
    return 1
  fi

  local task_id
  task_id=$(grep '^ceTaskId=' "$report_file" | cut -d= -f2)

  if [[ -z "$task_id" ]]; then
    log_error "Could not extract ceTaskId from ${report_file}"
    return 1
  fi

  echo "$task_id"
}
