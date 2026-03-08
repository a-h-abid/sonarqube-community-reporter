#!/usr/bin/env bash
# ==============================================================================
# sonar-report.sh — Main entrypoint: fetch SonarQube analysis data & generate
#                    reports in JSON, Markdown, HTML, PDF, XLSX, and ODS.
# ==============================================================================
# Usage:
#   ./scripts/sonar-report.sh [OPTIONS]
#
# Options:
#   --url URL              SonarQube base URL         (env: SONAR_URL)
#   --token TOKEN          Authentication token       (env: SONAR_TOKEN)
#   --project-key KEY      Project key                (env: SONAR_PROJECT_KEY)
#   --branch BRANCH        Branch name (optional)     (env: SONAR_BRANCH)
#   --task-id ID           CE task ID to poll         (env: SONAR_TASK_ID)
#   --formats FMT          Comma-separated: json,md,html,pdf,xlsx,ods (env: REPORT_FORMATS)
#   --output-dir DIR       Output directory           (env: REPORT_OUTPUT_DIR)
#   --wait                 Wait for analysis to finish before generating report
#   --no-wait              Skip analysis polling (default)
#   --poll-interval SECS   Poll interval              (env: POLL_INTERVAL)
#   --poll-timeout SECS    Poll timeout               (env: POLL_TIMEOUT)
#   --fail-on-gate         Exit 1 if quality gate failed
#   -h, --help             Show this help
# ==============================================================================
set -euo pipefail

_MAIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source .env from parent directory if it exists.
# WARNING: The .env file is sourced as shell code; only use trusted content.
if [[ -f "${_MAIN_SCRIPT_DIR}/../.env" ]]; then
  # shellcheck source=/dev/null
  source "${_MAIN_SCRIPT_DIR}/../.env"
fi

# Source library modules
# shellcheck source=lib/api.sh
source "${_MAIN_SCRIPT_DIR}/lib/api.sh"
# shellcheck source=lib/metrics.sh
source "${_MAIN_SCRIPT_DIR}/lib/metrics.sh"
# shellcheck source=lib/report-json.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-json.sh"
# shellcheck source=lib/report-md.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-md.sh"
# shellcheck source=lib/report-html.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-html.sh"
# shellcheck source=lib/report-pdf.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-pdf.sh"
# shellcheck source=lib/report-xlsx.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-xlsx.sh"
# shellcheck source=lib/report-ods.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-ods.sh"
# shellcheck source=wait-for-analysis.sh
source "${_MAIN_SCRIPT_DIR}/wait-for-analysis.sh"

# ===========================================================================
# Defaults (can be overridden by env vars or CLI args)
# ===========================================================================
SONAR_URL="${SONAR_URL:-http://localhost:9000}"
SONAR_TOKEN="${SONAR_TOKEN:-}"
SONAR_PROJECT_KEY="${SONAR_PROJECT_KEY:-}"
SONAR_BRANCH="${SONAR_BRANCH:-}"
SONAR_TASK_ID="${SONAR_TASK_ID:-}"
REPORT_FORMATS="${REPORT_FORMATS:-json,md,html,pdf,xlsx,ods}"
REPORT_OUTPUT_DIR="${REPORT_OUTPUT_DIR:-./reports}"
POLL_INTERVAL="${POLL_INTERVAL:-5}"
POLL_TIMEOUT="${POLL_TIMEOUT:-300}"
ANALYSIS_ID="${ANALYSIS_ID:-}"

WAIT_FOR_ANALYSIS=false
FAIL_ON_GATE=false

# ===========================================================================
# CLI Argument Parsing
# ===========================================================================
show_help() {
  head -n 23 "$0" | grep '^#' | sed 's/^# \?//'
  exit 0
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)             SONAR_URL="$2";          shift 2 ;;
      --token)           SONAR_TOKEN="$2";        shift 2 ;;
      --project-key)     SONAR_PROJECT_KEY="$2";  shift 2 ;;
      --branch)          SONAR_BRANCH="$2";       shift 2 ;;
      --task-id)         SONAR_TASK_ID="$2";      shift 2 ;;
      --formats)         REPORT_FORMATS="$2";     shift 2 ;;
      --output-dir)      REPORT_OUTPUT_DIR="$2";  shift 2 ;;
      --wait)            WAIT_FOR_ANALYSIS=true;  shift   ;;
      --no-wait)         WAIT_FOR_ANALYSIS=false; shift   ;;
      --poll-interval)   POLL_INTERVAL="$2";      shift 2 ;;
      --poll-timeout)    POLL_TIMEOUT="$2";       shift 2 ;;
      --fail-on-gate)    FAIL_ON_GATE=true;       shift   ;;
      -h|--help)         show_help ;;
      *)
        log_error "Unknown option: $1"
        show_help
        ;;
    esac
  done
}

# ===========================================================================
# Validation
# ===========================================================================
validate_params() {
  local errors=0

  if [[ -z "$SONAR_TOKEN" ]]; then
    log_error "SONAR_TOKEN is required (use --token or set env var)"
    errors=$((errors + 1))
  fi

  if [[ -z "$SONAR_PROJECT_KEY" ]]; then
    log_error "SONAR_PROJECT_KEY is required (use --project-key or set env var)"
    errors=$((errors + 1))
  fi

  if [[ "$errors" -gt 0 ]]; then
    echo ""
    log_info "Run with --help for usage information"
    exit 1
  fi
}

# ===========================================================================
# Main
# ===========================================================================
main() {
  parse_args "$@"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           SonarQube Analysis Report Generator               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  validate_params

  log_info "Project:    ${SONAR_PROJECT_KEY}"
  log_info "Branch:     ${SONAR_BRANCH:-<default>}"
  log_info "URL:        ${SONAR_URL}"
  log_info "Formats:    ${REPORT_FORMATS}"
  log_info "Output:     ${REPORT_OUTPUT_DIR}"
  echo ""

  # --- Step 1: Check connectivity ---
  check_connectivity || exit 1
  echo ""

  # --- Step 2: Wait for analysis (if requested) ---
  if [[ "$WAIT_FOR_ANALYSIS" == "true" ]]; then
    wait_for_analysis || exit 1
    echo ""
  fi

  # --- Step 3: Fetch all metrics ---
  log_info "Collecting analysis data ..."
  echo ""

  # Write report data to a temp file to avoid holding large JSON in shell
  # variables and passing it as function arguments (which degrades with
  # large issue sets).
  local report_data_file
  report_data_file=$(mktemp)
  trap 'rm -f "$report_data_file"' EXIT

  fetch_all_metrics > "$report_data_file" || {
    log_error "Failed to collect analysis data"
    rm -f "$report_data_file"
    exit 1
  }
  echo ""

  # --- Step 4: Generate reports ---
  local generated_files=()
  local html_file=""

  mkdir -p "$REPORT_OUTPUT_DIR"

  IFS=',' read -ra formats <<< "$REPORT_FORMATS"
  for fmt in "${formats[@]}"; do
    fmt=$(echo "$fmt" | tr -d ' ')
    case "$fmt" in
      json)
        local f
        f=$(generate_json_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        generated_files+=("$f")
        ;;
      md|markdown)
        local f
        f=$(generate_md_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        generated_files+=("$f")
        ;;
      html)
        html_file=$(generate_html_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        generated_files+=("$html_file")
        ;;
      pdf)
        # PDF needs HTML — generate it first if not already done
        if [[ -z "$html_file" ]]; then
          html_file=$(generate_html_report "$report_data_file" "$REPORT_OUTPUT_DIR")
          generated_files+=("$html_file")
        fi
        local f
        f=$(generate_pdf_report "$html_file" "$REPORT_OUTPUT_DIR")
        [[ -n "$f" ]] && generated_files+=("$f")
        ;;
      xlsx)
        local f
        f=$(generate_xlsx_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        [[ -n "$f" ]] && generated_files+=("$f")
        ;;
      ods)
        local f
        f=$(generate_ods_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        [[ -n "$f" ]] && generated_files+=("$f")
        ;;
      *)
        log_warn "Unknown format '${fmt}' — skipping"
        ;;
    esac
  done

  # --- Step 5: Summary ---
  echo ""
  echo "────────────────────────────────────────────────────────────────"
  local qg_status
  qg_status=$(jq -r '.qualityGate.status // "UNKNOWN"' "$report_data_file")

  if [[ "$qg_status" == "OK" ]]; then
    log_ok "Quality Gate: PASSED ✅"
  elif [[ "$qg_status" == "ERROR" ]]; then
    log_error "Quality Gate: FAILED ❌"
  else
    log_warn "Quality Gate: ${qg_status}"
  fi

  echo ""
  log_info "Generated ${#generated_files[@]} report(s):"
  for f in "${generated_files[@]}"; do
    echo "  → ${f}"
  done
  echo "────────────────────────────────────────────────────────────────"
  echo ""

  # --- Step 6: Exit code ---
  if [[ "$FAIL_ON_GATE" == "true" ]] && [[ "$qg_status" == "ERROR" ]]; then
    log_error "Exiting with code 1 because quality gate failed (--fail-on-gate)"
    exit 1
  fi

  exit 0
}

main "$@"
