#!/usr/bin/env bash
# ==============================================================================
# sonar-report.sh — Main entrypoint: fetch SonarQube analysis data & generate
#                    reports in JSON, Markdown, HTML, PDF, XLSX, ODS, and CSV.
# ==============================================================================
# HELP_BEGIN
# Usage:
#   ./scripts/sonar-report.sh [OPTIONS]
#
# Options:
#   --url URL              SonarQube/SonarCloud base URL (env: SONAR_URL)
#   --token TOKEN          Authentication token          (env: SONAR_TOKEN)
#   --project-key KEY      Project key                  (env: SONAR_PROJECT_KEY)
#   --branch BRANCH        Branch name (optional)       (env: SONAR_BRANCH)
#   --task-id ID           CE task ID to poll           (env: SONAR_TASK_ID)
#   --formats FMT          Comma-separated: json,md,html,pdf,xlsx,ods,csv
#                                                       (env: REPORT_FORMATS)
#   --output-dir DIR       Output directory             (env: REPORT_OUTPUT_DIR)
#   --sonarcloud           Use SonarCloud API (auto-detected from URL)
#                                                       (env: SONAR_CLOUD)
#   --organization ORG     SonarCloud organization key  (env: SONAR_ORGANIZATION)
#   --wait                 Wait for analysis to finish before generating report
#   --no-wait              Skip analysis polling (default)
#   --poll-interval SECS   Poll interval                (env: POLL_INTERVAL)
#   --poll-timeout SECS    Poll timeout                 (env: POLL_TIMEOUT)
#   --fail-on-gate         Exit 1 if quality gate failed
#   --dry-run FILE         Skip API calls; regenerate reports from a saved
#                          report data JSON file        (env: DRY_RUN_FILE)
#   --notify-webhook URL   Post a summary notification to a Slack/Teams/generic
#                          webhook URL after report generation
#                                                       (env: NOTIFY_WEBHOOK)
#   --include-rule-descriptions[=MODE]
#                          Include rule "Why is this an issue?" / "What's the
#                          risk?" text. MODE: short (default — first paragraph)
#                          or full (entire section).
#                                                       (env: INCLUDE_RULE_DESCRIPTIONS)
#   --include-code-snippets
#                          Include affected code snippets in HTML/PDF reports.
#                                                       (env: INCLUDE_CODE_SNIPPETS)
#   --snippet-context N    Lines of context around the affected lines (default: 3)
#                                                       (env: SNIPPET_CONTEXT)
#   --include-quality-profiles
#                          Show the Quality Profiles (rule sets, one per language)
#                          applied during analysis, in all report formats.
#                                                       (env: INCLUDE_QUALITY_PROFILES)
#   --include-quality-gate-name
#                          Show the name of the Quality Gate applied during
#                          analysis, in all report formats.
#                                                       (env: INCLUDE_QUALITY_GATE_NAME)
#   --config FILE          Load configuration from FILE (default: auto-detect
#                          .sonar-report.yml or sonar-report.conf)
#   -h, --help             Show this help
#
# Configuration precedence (highest to lowest):
#   1. CLI flags (--url, --token, etc.)
#   2. Environment variables (SONAR_URL, SONAR_TOKEN, etc.)
#   3. Config file (.sonar-report.yml or sonar-report.conf)
#   4. Built-in defaults
# HELP_END
# ==============================================================================
set -euo pipefail

# Require bash 4.4+: the scripts run under `set -u`, which errors on empty-array
# expansion in bash older than 4.4 (and `declare -g` needs 4.2). This runs before
# the library `source`s, so the `log_*` helpers don't exist yet — use plain echo.
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  echo "Error: requires bash 4.4+ (found ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}.${BASH_VERSINFO[2]:-0})." >&2
  echo "Upgrade bash, or run via the project's Docker image (it bundles bash 5.2)." >&2
  exit 1
fi

_MAIN_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source .env from parent directory if it exists.
# WARNING: The .env file is sourced as shell code; only use trusted content.
if [[ -f "${_MAIN_SCRIPT_DIR}/../.env" ]]; then
  # shellcheck source=/dev/null
  source "${_MAIN_SCRIPT_DIR}/../.env"
fi

# Source library modules
# shellcheck source=scripts/lib/api.sh
source "${_MAIN_SCRIPT_DIR}/lib/api.sh"
# shellcheck source=scripts/lib/config.sh
source "${_MAIN_SCRIPT_DIR}/lib/config.sh"
# shellcheck source=scripts/lib/metrics.sh
source "${_MAIN_SCRIPT_DIR}/lib/metrics.sh"
# shellcheck source=scripts/lib/report-json.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-json.sh"
# shellcheck source=scripts/lib/report-md.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-md.sh"
# shellcheck source=scripts/lib/report-html.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-html.sh"
# shellcheck source=scripts/lib/report-pdf.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-pdf.sh"
# shellcheck source=scripts/lib/report-xlsx.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-xlsx.sh"
# shellcheck source=scripts/lib/report-ods.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-ods.sh"
# shellcheck source=scripts/lib/report-csv.sh
source "${_MAIN_SCRIPT_DIR}/lib/report-csv.sh"
# shellcheck source=scripts/lib/notify.sh
source "${_MAIN_SCRIPT_DIR}/lib/notify.sh"
# shellcheck source=scripts/wait-for-analysis.sh
source "${_MAIN_SCRIPT_DIR}/wait-for-analysis.sh"

# ===========================================================================
# Snapshot environment variables set before defaults/config
# (These take precedence over config file values and defaults)
# ===========================================================================
_ENV_SNAPSHOT_VARS=""
for _var in SONAR_URL SONAR_TOKEN SONAR_PROJECT_KEY SONAR_BRANCH SONAR_TASK_ID \
            SONAR_ORGANIZATION SONAR_CLOUD REPORT_FORMATS REPORT_OUTPUT_DIR \
            POLL_INTERVAL POLL_TIMEOUT ANALYSIS_ID DRY_RUN_FILE NOTIFY_WEBHOOK \
            INCLUDE_RULE_DESCRIPTIONS INCLUDE_CODE_SNIPPETS SNIPPET_CONTEXT \
            INCLUDE_QUALITY_PROFILES INCLUDE_QUALITY_GATE_NAME \
            WAIT_FOR_ANALYSIS FAIL_ON_GATE; do
  if [[ -n "${!_var:-}" ]]; then
    _ENV_SNAPSHOT_VARS="${_ENV_SNAPSHOT_VARS} ${_var}"
  fi
done

WAIT_FOR_ANALYSIS="${WAIT_FOR_ANALYSIS:-false}"
FAIL_ON_GATE="${FAIL_ON_GATE:-false}"
REQUESTED_FORMATS=()

# ---------------------------------------------------------------------------
# apply_defaults — Sets default values for any variable not already configured
#   Called after config file loading to ensure precedence: env > config > defaults
# ---------------------------------------------------------------------------
apply_defaults() {
  [[ -z "${SONAR_URL:-}" ]]                 && SONAR_URL="http://localhost:9000"
  [[ -z "${SONAR_TOKEN:-}" ]]               && SONAR_TOKEN=""
  [[ -z "${SONAR_PROJECT_KEY:-}" ]]         && SONAR_PROJECT_KEY=""
  [[ -z "${SONAR_BRANCH:-}" ]]              && SONAR_BRANCH=""
  [[ -z "${SONAR_TASK_ID:-}" ]]             && SONAR_TASK_ID=""
  [[ -z "${SONAR_ORGANIZATION:-}" ]]        && SONAR_ORGANIZATION=""
  [[ -z "${SONAR_CLOUD:-}" ]]               && SONAR_CLOUD="false"
  [[ -z "${REPORT_FORMATS:-}" ]]            && REPORT_FORMATS="json,md,html,pdf,xlsx,ods"
  [[ -z "${REPORT_OUTPUT_DIR:-}" ]]         && REPORT_OUTPUT_DIR="./reports"
  [[ -z "${POLL_INTERVAL:-}" ]]             && POLL_INTERVAL="5"
  [[ -z "${POLL_TIMEOUT:-}" ]]              && POLL_TIMEOUT="300"
  [[ -z "${ANALYSIS_ID:-}" ]]               && ANALYSIS_ID=""
  [[ -z "${DRY_RUN_FILE:-}" ]]              && DRY_RUN_FILE=""
  [[ -z "${NOTIFY_WEBHOOK:-}" ]]            && NOTIFY_WEBHOOK=""
  [[ -z "${INCLUDE_RULE_DESCRIPTIONS:-}" ]] && INCLUDE_RULE_DESCRIPTIONS=""
  [[ -z "${INCLUDE_CODE_SNIPPETS:-}" ]]     && INCLUDE_CODE_SNIPPETS="false"
  [[ -z "${SNIPPET_CONTEXT:-}" ]]           && SNIPPET_CONTEXT="3"
  [[ -z "${INCLUDE_QUALITY_PROFILES:-}" ]]  && INCLUDE_QUALITY_PROFILES="false"
  [[ -z "${INCLUDE_QUALITY_GATE_NAME:-}" ]] && INCLUDE_QUALITY_GATE_NAME="false"
  [[ -z "${WAIT_FOR_ANALYSIS:-}" ]]         && WAIT_FOR_ANALYSIS="false"
  [[ -z "${FAIL_ON_GATE:-}" ]]              && FAIL_ON_GATE="false"

  return 0
}

# ===========================================================================
# CLI Argument Parsing
# ===========================================================================
show_help() {
  sed -n '/^# HELP_BEGIN$/,/^# HELP_END$/{/^# HELP_BEGIN$/d; /^# HELP_END$/d; s/^# \?//; p}' "$0"
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
      --sonarcloud)      SONAR_CLOUD=true;         shift   ;;
      --organization)    SONAR_ORGANIZATION="$2"; shift 2 ;;
      --wait)            WAIT_FOR_ANALYSIS=true;  shift   ;;
      --no-wait)         WAIT_FOR_ANALYSIS=false; shift   ;;
      --poll-interval)   POLL_INTERVAL="$2";      shift 2 ;;
      --poll-timeout)    POLL_TIMEOUT="$2";       shift 2 ;;
      --fail-on-gate)    FAIL_ON_GATE=true;       shift   ;;
      --dry-run)         DRY_RUN_FILE="$2";       shift 2 ;;
      --notify-webhook)  NOTIFY_WEBHOOK="$2";     shift 2 ;;
      --config)          shift 2 ;;  # Handled in main() before parse_args
      --include-rule-descriptions)
        INCLUDE_RULE_DESCRIPTIONS="short"; shift ;;
      --include-rule-descriptions=*)
        INCLUDE_RULE_DESCRIPTIONS="${1#*=}"; shift ;;
      --include-code-snippets)
        INCLUDE_CODE_SNIPPETS=true;       shift ;;
      --snippet-context)
        SNIPPET_CONTEXT="$2";             shift 2 ;;
      --include-quality-profiles)
        INCLUDE_QUALITY_PROFILES=true;    shift ;;
      --include-quality-gate-name)
        INCLUDE_QUALITY_GATE_NAME=true;   shift ;;
      -h|--help)         show_help ;;
      *)
        log_error "Unknown option: $1"
        show_help
        ;;
    esac
  done
}

normalize_format() {
  local fmt="$1"

  fmt="${fmt//[[:space:]]/}"

  case "$fmt" in
    markdown) echo "md" ;;
    *) echo "$fmt" ;;
  esac
}

contains_value() {
  local needle="$1"
  shift

  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done

  return 1
}

validate_enrichment_flags() {
  # Normalize INCLUDE_RULE_DESCRIPTIONS
  case "${INCLUDE_RULE_DESCRIPTIONS:-}" in
    "" | short | full) : ;;
    *)
      log_error "Invalid INCLUDE_RULE_DESCRIPTIONS value: '${INCLUDE_RULE_DESCRIPTIONS}' (expected short or full)"
      return 1
      ;;
  esac

  # Normalize INCLUDE_CODE_SNIPPETS to "true"/"false"
  case "${INCLUDE_CODE_SNIPPETS:-false}" in
    true|TRUE|yes|YES|1|on|ON)  INCLUDE_CODE_SNIPPETS="true"  ;;
    false|FALSE|no|NO|0|off|OFF|"") INCLUDE_CODE_SNIPPETS="false" ;;
    *)
      log_error "Invalid INCLUDE_CODE_SNIPPETS value: '${INCLUDE_CODE_SNIPPETS}'"
      return 1
      ;;
  esac

  # Validate + clamp SNIPPET_CONTEXT
  if ! [[ "${SNIPPET_CONTEXT:-3}" =~ ^[0-9]+$ ]]; then
    log_error "SNIPPET_CONTEXT must be a non-negative integer (got '${SNIPPET_CONTEXT}')"
    return 1
  fi
  if [[ "${SNIPPET_CONTEXT}" -gt 50 ]]; then
    log_warn "SNIPPET_CONTEXT=${SNIPPET_CONTEXT} is unusually large — clamping to 50"
    SNIPPET_CONTEXT=50
  fi

  # Normalize INCLUDE_QUALITY_PROFILES to "true"/"false"
  case "${INCLUDE_QUALITY_PROFILES:-false}" in
    true|TRUE|yes|YES|1|on|ON)      INCLUDE_QUALITY_PROFILES="true"  ;;
    false|FALSE|no|NO|0|off|OFF|"") INCLUDE_QUALITY_PROFILES="false" ;;
    *)
      log_error "Invalid INCLUDE_QUALITY_PROFILES value: '${INCLUDE_QUALITY_PROFILES}'"
      return 1
      ;;
  esac

  # Normalize INCLUDE_QUALITY_GATE_NAME to "true"/"false"
  case "${INCLUDE_QUALITY_GATE_NAME:-false}" in
    true|TRUE|yes|YES|1|on|ON)      INCLUDE_QUALITY_GATE_NAME="true"  ;;
    false|FALSE|no|NO|0|off|OFF|"") INCLUDE_QUALITY_GATE_NAME="false" ;;
    *)
      log_error "Invalid INCLUDE_QUALITY_GATE_NAME value: '${INCLUDE_QUALITY_GATE_NAME}'"
      return 1
      ;;
  esac
}

validate_report_formats() {
  local raw_formats=()
  local normalized_formats=()
  local raw fmt
  local errors=0

  IFS=',' read -ra raw_formats <<< "$REPORT_FORMATS"

  if [[ "${#raw_formats[@]}" -eq 0 ]]; then
    log_error "At least one report format is required"
    log_info "Supported formats: json, md, markdown, html, pdf, xlsx, ods, csv"
    return 1
  fi

  for raw in "${raw_formats[@]}"; do
    fmt=$(normalize_format "$raw")

    if [[ -z "$fmt" ]]; then
      log_error "Empty report format in '${REPORT_FORMATS}'"
      errors=$((errors + 1))
      continue
    fi

    case "$fmt" in
      json|md|html|pdf|xlsx|ods|csv)
        if contains_value "$fmt" "${normalized_formats[@]}"; then
          log_warn "Duplicate format '${raw}' requested — keeping one"
          continue
        fi
        normalized_formats+=("$fmt")
        ;;
      *)
        log_error "Unsupported report format: ${raw}"
        errors=$((errors + 1))
        ;;
    esac
  done

  if [[ "$errors" -gt 0 ]]; then
    log_info "Supported formats: json, md, markdown, html, pdf, xlsx, ods, csv"
    return 1
  fi

  if [[ "${#normalized_formats[@]}" -eq 0 ]]; then
    log_error "At least one valid report format is required"
    return 1
  fi

  REQUESTED_FORMATS=("${normalized_formats[@]}")
}

# ===========================================================================
# Validation
# ===========================================================================
validate_params() {
  local errors=0

  # Auto-detect SonarCloud from URL before validating other parameters
  detect_sonarcloud

  if [[ -n "$DRY_RUN_FILE" ]]; then
    # Dry-run mode: validate the provided JSON file; no token/URL needed.
    if [[ ! -f "$DRY_RUN_FILE" ]]; then
      log_error "Dry-run file not found: ${DRY_RUN_FILE}"
      errors=$((errors + 1))
    else
      local dry_run_key
      dry_run_key=$(jq -r '.metadata.projectKey // empty' "$DRY_RUN_FILE" 2>/dev/null) || {
        log_error "Dry-run file is not valid JSON: ${DRY_RUN_FILE}"
        errors=$((errors + 1))
      }
      # Auto-populate project key from the file when not set explicitly
      if [[ -z "$SONAR_PROJECT_KEY" ]] && [[ -n "${dry_run_key:-}" ]]; then
        SONAR_PROJECT_KEY="$dry_run_key"
        log_info "Project key from dry-run file: ${SONAR_PROJECT_KEY}"
      fi
    fi
  else
    if [[ -z "$SONAR_TOKEN" ]]; then
      log_error "SONAR_TOKEN is required (use --token or set env var)"
      errors=$((errors + 1))
    fi

    if [[ -z "$SONAR_PROJECT_KEY" ]]; then
      log_error "SONAR_PROJECT_KEY is required (use --project-key or set env var)"
      errors=$((errors + 1))
    fi

    if [[ "${SONAR_CLOUD:-false}" == "true" ]] && [[ -z "$SONAR_ORGANIZATION" ]]; then
      log_error "SONAR_ORGANIZATION is required for SonarCloud (use --organization or set env var)"
      errors=$((errors + 1))
    fi
  fi

  if ! validate_report_formats; then
    errors=$((errors + 1))
  fi

  if ! validate_enrichment_flags; then
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
  # First pass: look for --config flag only (to load config early)
  local explicit_config=""
  for arg in "$@"; do
    if [[ "$arg" == "--config" ]]; then
      # Next arg after --config is the file path
      local next_is_config=true
      continue
    fi
    if [[ "${next_is_config:-false}" == "true" ]]; then
      explicit_config="$arg"
      break
    fi
  done

  # Load config file (auto-detect or explicit)
  # This happens after .env but before parse_args, so precedence is:
  #   CLI args > env vars > config file > defaults
  if [[ -n "$explicit_config" ]]; then
    load_config_file "" "$explicit_config"
  else
    load_config_file "${_MAIN_SCRIPT_DIR}/.."
  fi

  # Apply defaults for any variables not set by env or config
  apply_defaults

  # Second pass: parse all arguments
  parse_args "$@"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║           SonarQube Analysis Report Generator               ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  validate_params

  log_info "Project:    ${SONAR_PROJECT_KEY}"
  log_info "Branch:     ${SONAR_BRANCH:-<default>}"
  if [[ -n "$DRY_RUN_FILE" ]]; then
    log_info "Mode:       dry-run (offline — using ${DRY_RUN_FILE})"
  elif [[ "${SONAR_CLOUD:-false}" == "true" ]]; then
    log_info "Mode:       SonarCloud"
    log_info "URL:        ${SONAR_URL}"
    [[ -n "$SONAR_ORGANIZATION" ]] && log_info "Org:        ${SONAR_ORGANIZATION}"
  else
    log_info "Mode:       SonarQube"
    log_info "URL:        ${SONAR_URL}"
  fi
  log_info "Formats:    ${REPORT_FORMATS}"
  log_info "Output:     ${REPORT_OUTPUT_DIR}"
  if [[ -n "${INCLUDE_RULE_DESCRIPTIONS:-}" ]]; then
    log_info "Rule descriptions: ${INCLUDE_RULE_DESCRIPTIONS}"
  fi
  if [[ "${INCLUDE_CODE_SNIPPETS:-false}" == "true" ]]; then
    log_info "Code snippets:    enabled (context=${SNIPPET_CONTEXT})"
  fi
  if [[ "${INCLUDE_QUALITY_PROFILES:-false}" == "true" ]]; then
    log_info "Quality profiles: enabled"
  fi
  if [[ "${INCLUDE_QUALITY_GATE_NAME:-false}" == "true" ]]; then
    log_info "Quality gate name: enabled"
  fi
  echo ""

  # --- Step 1: Check connectivity (skipped in dry-run mode) ---
  if [[ -z "$DRY_RUN_FILE" ]]; then
    check_connectivity || exit 1
    echo ""
  fi

  # --- Step 2: Wait for analysis (skipped in dry-run mode) ---
  if [[ "$WAIT_FOR_ANALYSIS" == "true" ]] && [[ -z "$DRY_RUN_FILE" ]]; then
    wait_for_analysis || exit 1
    echo ""
  fi

  # --- Step 3: Fetch all metrics (or reuse dry-run file) ---
  local report_data_file
  local _owned_report_data_file=""

  if [[ -n "$DRY_RUN_FILE" ]]; then
    report_data_file="$DRY_RUN_FILE"
    log_info "Loading report data from: ${DRY_RUN_FILE}"
    echo ""
  else
    log_info "Collecting analysis data ..."
    echo ""

    # Write report data to a temp file to avoid holding large JSON in shell
    # variables and passing it as function arguments (which degrades with
    # large issue sets).
    report_data_file=$(create_temp_file)
    _owned_report_data_file="yes"
    trap '[[ -n "$_owned_report_data_file" ]] && rm -f "$report_data_file"' EXIT

    fetch_all_metrics > "$report_data_file" || {
      log_error "Failed to collect analysis data"
      rm -f "$report_data_file"
      exit 1
    }
    echo ""
  fi

  # --- Step 4: Generate reports ---
  local generated_files=()
  local skipped_formats=()
  local html_file=""

  mkdir -p "$REPORT_OUTPUT_DIR"

  for fmt in "${REQUESTED_FORMATS[@]}"; do
    case "$fmt" in
      json)
        local f
        f=$(generate_json_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        generated_files+=("$f")
        ;;
      md)
        local f
        f=$(generate_md_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        generated_files+=("$f")
        ;;
      html)
        if [[ -z "$html_file" ]]; then
          html_file=$(generate_html_report "$report_data_file" "$REPORT_OUTPUT_DIR")
          generated_files+=("$html_file")
        else
          log_info "Reusing previously generated HTML report"
        fi
        ;;
      pdf)
        # PDF needs HTML — generate it first if not already done
        if [[ -z "$html_file" ]]; then
          html_file=$(generate_html_report "$report_data_file" "$REPORT_OUTPUT_DIR")
          generated_files+=("$html_file")
        fi
        local f
        f=$(generate_pdf_report "$html_file" "$REPORT_OUTPUT_DIR")
        if [[ -n "$f" ]]; then
          generated_files+=("$f")
        else
          skipped_formats+=("pdf")
        fi
        ;;
      xlsx)
        local f
        f=$(generate_xlsx_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        if [[ -n "$f" ]]; then
          generated_files+=("$f")
        else
          skipped_formats+=("xlsx")
        fi
        ;;
      ods)
        local f
        f=$(generate_ods_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        if [[ -n "$f" ]]; then
          generated_files+=("$f")
        else
          skipped_formats+=("ods")
        fi
        ;;
      csv)
        local csv_out
        csv_out=$(generate_csv_report "$report_data_file" "$REPORT_OUTPUT_DIR")
        while IFS= read -r f; do
          [[ -n "$f" ]] && generated_files+=("$f")
        done <<< "$csv_out"
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

  if [[ "${#skipped_formats[@]}" -gt 0 ]]; then
    log_warn "Skipped format(s): ${skipped_formats[*]}"
  fi
  echo "────────────────────────────────────────────────────────────────"
  echo ""

  # --- Step 6: Webhook notification (optional) ---
  if [[ -n "$NOTIFY_WEBHOOK" ]]; then
    send_webhook_notification "$NOTIFY_WEBHOOK" "$report_data_file" "${generated_files[@]}" || \
      log_warn "Webhook notification failed — continuing"
    echo ""
  fi

  # --- Step 7: Exit code ---
  if [[ "$FAIL_ON_GATE" == "true" ]] && [[ "$qg_status" == "ERROR" ]]; then
    log_error "Exiting with code 1 because quality gate failed (--fail-on-gate)"
    exit 1
  fi

  exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
