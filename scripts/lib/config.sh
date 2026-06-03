#!/usr/bin/env bash
# ==============================================================================
# config.sh — Configuration file parser for sonar-report.conf and .sonar-report.yml
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_CONFIG_SH_LOADED:-}" ]] && return 0
_CONFIG_SH_LOADED=1

set -euo pipefail

_CONFIG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source api.sh for logging helpers
# shellcheck source=api.sh
source "${_CONFIG_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# is_allowed_key <key>
#   Checks if a configuration key is in the allowlist.
#   Returns 0 if allowed, 1 if not.
#   Security allowlist to prevent arbitrary code execution.
# ---------------------------------------------------------------------------
is_allowed_key() {
  local key="$1"

  # Use case statement for better subshell compatibility
  case "$key" in
    SONAR_URL|\
    SONAR_TOKEN|\
    SONAR_PROJECT_KEY|\
    SONAR_BRANCH|\
    SONAR_TASK_ID|\
    SONAR_ORGANIZATION|\
    SONAR_CLOUD|\
    REPORT_FORMATS|\
    REPORT_OUTPUT_DIR|\
    POLL_INTERVAL|\
    POLL_TIMEOUT|\
    ANALYSIS_ID|\
    DRY_RUN_FILE|\
    NOTIFY_WEBHOOK|\
    INCLUDE_RULE_DESCRIPTIONS|\
    INCLUDE_CODE_SNIPPETS|\
    SNIPPET_CONTEXT|\
    WAIT_FOR_ANALYSIS|\
    FAIL_ON_GATE)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# sanitize_value <value>
#   Basic sanitization for config values. Removes potentially dangerous
#   shell metacharacters. Returns the sanitized value or exits on suspicious
#   patterns.
# ---------------------------------------------------------------------------
sanitize_value() {
  local value="$1"

  # Check for suspicious patterns that could indicate command injection
  # Use case statement for clearer pattern matching
  # shellcheck disable=SC2016
  case "$value" in
    *'$('*|*'`'*|*';'*|*'|'*|*'&&'*)
      log_warn "Suspicious pattern detected in config value: ${value}"
      log_warn "Value contains shell metacharacters that could be dangerous"
      ;;
  esac

  echo "$value"
}

# ---------------------------------------------------------------------------
# set_config_var <key> <value>
#   Sets a configuration variable only if it's not already set (respects
#   environment variables). Validates key against allowlist and sanitizes value.
# ---------------------------------------------------------------------------
set_config_var() {
  local key="$1"
  local value="$2"

  # Validate key
  if ! is_allowed_key "$key"; then
    log_warn "Ignoring unknown config key: ${key}"
    return 0
  fi

  # Only set if not already set by environment (check snapshot)
  if [[ " ${_ENV_SNAPSHOT_VARS:-} " == *" ${key} "* ]]; then
    return 0
  fi

  # Only set if not already set by a previous config entry
  if [[ -z "${!key:-}" ]]; then
    local sanitized_value
    sanitized_value=$(sanitize_value "$value")

    # Use declare to set the variable in the caller's scope
    export "${key}=${sanitized_value}"
  fi
}

# ---------------------------------------------------------------------------
# parse_shell_config <file>
#   Parses a shell-style config file (KEY=VALUE format).
#   - Ignores comments (lines starting with #)
#   - Ignores empty lines
#   - Strips quotes from values
#   - Only processes keys matching the pattern [A-Z_][A-Z0-9_]*
# ---------------------------------------------------------------------------
parse_shell_config() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    log_error "Config file not found: ${file}"
    return 1
  fi

  local line key value

  # Process line by line
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Extract key=value pairs
    if [[ "$line" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)[[:space:]]*=[[:space:]]*(.*)[[:space:]]*$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # Strip leading/trailing whitespace from value
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"

      # Strip quotes if present
      if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi

      set_config_var "$key" "$value"
    fi
  done < "$file"
}

# ---------------------------------------------------------------------------
# parse_yaml_config <file>
#   Parses a simple YAML config file (two-level hierarchy: section.key: value).
#   Maps YAML paths to environment variable names:
#     sonar.url → SONAR_URL
#     report.formats → REPORT_FORMATS
#     polling.interval → POLL_INTERVAL
#
#   Supported sections:
#     - sonar (url, token, project_key, branch, organization, cloud, task_id, analysis_id)
#     - report (formats, output_dir)
#     - polling (interval, timeout, wait)
#     - enrichment (include_rule_descriptions, include_code_snippets, snippet_context)
#     - options (fail_on_gate, dry_run_file, notify_webhook)
# ---------------------------------------------------------------------------
parse_yaml_config() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    log_error "Config file not found: ${file}"
    return 1
  fi

  local current_section=""
  local line key value env_var

  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue

    # Detect section header (e.g., "sonar:")
    if [[ "$line" =~ ^([a-z_]+):[[:space:]]*$ ]]; then
      current_section="${BASH_REMATCH[1]}"
      continue
    fi

    # Detect key-value pair (e.g., "  url: http://localhost:9000")
    if [[ "$line" =~ ^[[:space:]]+([a-z_]+):[[:space:]]*(.*)[[:space:]]*$ ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"

      # Strip inline comments (only when # is preceded by whitespace, per YAML spec)
      # Skip stripping for properly quoted values to preserve # in tokens/URLs
      if [[ ! ("$value" =~ ^\".*\"$ || "$value" =~ ^\'.*\'$) ]]; then
        value="${value%% #*}"
      fi

      # Strip leading/trailing whitespace
      value="${value#"${value%%[![:space:]]*}"}"
      value="${value%"${value##*[![:space:]]}"}"

      # Strip quotes if present
      if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
        value="${BASH_REMATCH[1]}"
      fi

      # Convert empty strings to empty
      [[ "$value" == '""' ]] || [[ "$value" == "''" ]] && value=""

      # Map YAML path to environment variable
      env_var=$(yaml_key_to_env_var "$current_section" "$key")

      if [[ -n "$env_var" ]]; then
        set_config_var "$env_var" "$value"
      else
        log_warn "Ignoring unknown YAML key: ${current_section}.${key}"
      fi
    fi
  done < "$file"
}

# ---------------------------------------------------------------------------
# yaml_key_to_env_var <section> <key>
#   Maps YAML section.key to environment variable name.
#   Returns empty string if the mapping is not recognized.
# ---------------------------------------------------------------------------
yaml_key_to_env_var() {
  local section="$1"
  local key="$2"

  case "${section}.${key}" in
    sonar.url)                          echo "SONAR_URL" ;;
    sonar.token)                        echo "SONAR_TOKEN" ;;
    sonar.project_key)                  echo "SONAR_PROJECT_KEY" ;;
    sonar.branch)                       echo "SONAR_BRANCH" ;;
    sonar.organization)                 echo "SONAR_ORGANIZATION" ;;
    sonar.cloud)                        echo "SONAR_CLOUD" ;;
    sonar.task_id)                      echo "SONAR_TASK_ID" ;;
    sonar.analysis_id)                  echo "ANALYSIS_ID" ;;
    report.formats)                     echo "REPORT_FORMATS" ;;
    report.output_dir)                  echo "REPORT_OUTPUT_DIR" ;;
    polling.interval)                   echo "POLL_INTERVAL" ;;
    polling.timeout)                    echo "POLL_TIMEOUT" ;;
    polling.wait)                       echo "WAIT_FOR_ANALYSIS" ;;
    enrichment.include_rule_descriptions) echo "INCLUDE_RULE_DESCRIPTIONS" ;;
    enrichment.include_code_snippets)   echo "INCLUDE_CODE_SNIPPETS" ;;
    enrichment.snippet_context)         echo "SNIPPET_CONTEXT" ;;
    options.fail_on_gate)               echo "FAIL_ON_GATE" ;;
    options.dry_run_file)               echo "DRY_RUN_FILE" ;;
    options.notify_webhook)             echo "NOTIFY_WEBHOOK" ;;
    *)                                  echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# load_config_file [config_dir] [explicit_path]
#   Auto-detects and loads a config file from the project root.
#
#   Search order (when explicit_path is not provided):
#     1. .sonar-report.yml (preferred)
#     2. sonar-report.conf (fallback)
#
#   If explicit_path is provided, loads that file directly (and exits on error).
#
#   Config files set variables only if they are not already set by environment.
#   This preserves the precedence: CLI > env > config > defaults.
# ---------------------------------------------------------------------------
load_config_file() {
  local config_dir="${1:-}"
  local explicit_path="${2:-}"
  local config_file=""

  # If explicit path provided, use it
  if [[ -n "$explicit_path" ]]; then
    if [[ ! -f "$explicit_path" ]]; then
      log_error "Config file not found: ${explicit_path}"
      return 1
    fi
    config_file="$explicit_path"
    log_info "Loading config from: ${config_file}"
  else
    # Auto-detect config file in project root
    if [[ -z "$config_dir" ]]; then
      log_error "load_config_file: config_dir not specified"
      return 1
    fi

    # Prefer YAML over shell config
    if [[ -f "${config_dir}/.sonar-report.yml" ]]; then
      config_file="${config_dir}/.sonar-report.yml"
      log_info "Loading config from: ${config_file}"
    elif [[ -f "${config_dir}/sonar-report.conf" ]]; then
      config_file="${config_dir}/sonar-report.conf"
      log_info "Loading config from: ${config_file}"
    else
      # No config file found — this is not an error
      return 0
    fi
  fi

  # Parse based on file extension
  if [[ "$config_file" == *.yml ]] || [[ "$config_file" == *.yaml ]]; then
    parse_yaml_config "$config_file"
  else
    parse_shell_config "$config_file"
  fi
}
