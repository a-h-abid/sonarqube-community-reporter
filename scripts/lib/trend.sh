#!/usr/bin/env bash
# ==============================================================================
# trend.sh — Compare the current report data against a previously saved
#            report-data JSON file (the baseline) and attach a normalized
#            `.trend` object that every report generator can render.
#
# The baseline is any report data JSON previously produced by this tool (the
# same shape `--dry-run` consumes). Nothing is written back to the baseline.
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_TREND_SH_LOADED:-}" ]] && return 0
_TREND_SH_LOADED=1

set -euo pipefail

_TREND_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/api.sh
source "${_TREND_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# validate_baseline_file <path>
#   Ensures the baseline exists, is readable, and holds report data JSON.
#   Returns 1 (with a logged error) when it does not.
# ---------------------------------------------------------------------------
validate_baseline_file() {
  local baseline_file="$1"

  if [[ ! -f "$baseline_file" ]]; then
    log_error "Baseline report file not found: ${baseline_file}"
    return 1
  fi
  if [[ ! -r "$baseline_file" ]]; then
    log_error "Baseline report file is not readable: ${baseline_file}"
    return 1
  fi
  if ! jq -e 'type == "object"' "$baseline_file" >/dev/null 2>&1; then
    log_error "Baseline report file is not valid report data JSON: ${baseline_file}"
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# compute_trend <current_report_data_file> <baseline_file>
#   Emits the current report data with a `.trend` object added, on stdout.
#   Returns 1 on failure.
# ---------------------------------------------------------------------------
compute_trend() {
  local current_file="$1"
  local baseline_file="$2"

  if ! jq \
      --slurpfile base "$baseline_file" \
      --arg baselineFile "$baseline_file" \
      -f "${_TREND_SCRIPT_DIR}/jq/trend.jq" \
      "$current_file"; then
    log_error "Failed to compute trend against baseline: ${baseline_file}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# apply_trend <current_report_data_file> <baseline_file>
#   Writes the trend-enriched report data to a new temp file and echoes its
#   path. The input file is left untouched. Returns 1 on failure.
# ---------------------------------------------------------------------------
apply_trend() {
  local current_file="$1"
  local baseline_file="$2"

  validate_baseline_file "$baseline_file" || return 1

  local out_file
  out_file=$(create_temp_file) || return 1

  if ! compute_trend "$current_file" "$baseline_file" > "$out_file"; then
    rm -f "$out_file"
    return 1
  fi

  echo "$out_file"
}

# ---------------------------------------------------------------------------
# trend_has_regression <report_data_file>
#   Returns 0 when the attached trend reports a regression (a key metric moved
#   in the wrong direction, or the quality gate flipped to ERROR), 1 otherwise.
# ---------------------------------------------------------------------------
trend_has_regression() {
  local report_data_file="$1"

  jq -e '(.trend.regression // false) == true' "$report_data_file" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# log_trend_summary <report_data_file>
#   Logs a one-line-per-signal summary of the computed trend.
# ---------------------------------------------------------------------------
log_trend_summary() {
  local report_data_file="$1"

  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && log_info "$line"
  done < <(jq -r '
    if (.trend // null) == null then empty else
      .trend as $t |
      ("Trend baseline: " + ($t.baseline.file // "?") +
        (if ($t.baseline.reportDate // "") != "" then " (" + $t.baseline.reportDate + ")" else "" end)),
      ("Quality gate: " + $t.qualityGate.previous + " → " + $t.qualityGate.current),
      ([$t.metrics | to_entries[] |
        .value.label + " " + .value.indicator + " " +
        (if .value.delta == null then "n/a" else (.value.delta | tostring) end)] | join(", ")),
      ("Issues: " + ($t.issues.new | tostring) + " new, " + ($t.issues.fixed | tostring) + " fixed")
    end' "$report_data_file" 2>/dev/null || true)
}
