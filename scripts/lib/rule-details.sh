#!/usr/bin/env bash
# ==============================================================================
# rule-details.sh — Fetch and normalize rule descriptions, hotspot details,
#                   and source code snippets for issue/hotspot enrichment.
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_RULE_DETAILS_SH_LOADED:-}" ]] && return 0
_RULE_DETAILS_SH_LOADED=1

set -euo pipefail

_RULE_DETAILS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_RULE_DETAILS_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# In-memory caches (associative arrays — bash 4+).
# ---------------------------------------------------------------------------
declare -gA _RULE_CACHE=()
declare -gA _HOTSPOT_RULE_CACHE=()
declare -gA _SOURCE_CACHE=()
declare -gA _RULE_NEGATIVE=()
declare -gA _COMPONENT_NEGATIVE=()

_SOURCE_CACHE_MAX_BYTES="${_SOURCE_CACHE_MAX_BYTES:-5242880}"  # 5 MB

_validate_json_response() {
  local endpoint="$1"
  local response="$2"

  if ! jq -e . >/dev/null 2>&1 <<< "$response"; then
    log_error "Invalid JSON response from ${endpoint}"
    log_error "Response: ${response}"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# _normalize_rule_html  (stdin -> stdout)
#   SonarQube's rule HTML is trusted documentation. We defensively strip
#   <script> and <style> blocks (rare but possible in custom rules) and
#   convert heading tags to bold paragraphs for compact display.
# ---------------------------------------------------------------------------
_normalize_rule_html() {
  # kcov-skip-start
  sed -E '
    :join
    N
    $!bjoin
    s|<[Ss][Cc][Rr][Ii][Pp][Tt][^>]*>.*</[Ss][Cc][Rr][Ii][Pp][Tt]>||g
    s|<[Ss][Tt][Yy][Ll][Ee][^>]*>.*</[Ss][Tt][Yy][Ll][Ee]>||g
    s|<[Hh][1-6][^>]*>|<p><strong>|g
    s|</[Hh][1-6]>|</strong></p>|g
  '
  # kcov-skip-end
}

# ---------------------------------------------------------------------------
# _html_to_text  (stdin -> stdout)
#   Converts HTML to plain text: strips tags, decodes common entities,
#   collapses whitespace.
# ---------------------------------------------------------------------------
_html_to_text() {
  local input
  input=$(cat)
  # kcov-skip-start
  printf '%s' "$input" | sed -E '
    s|<[Bb][Rr][[:space:]]*/?[[:space:]]*>|\n|g
    s|</[Pp]>|\n\n|g
    s|</[Ll][Ii]>|\n|g
    s|</[Hh][1-6]>|\n|g
    s|<[^>]+>||g
    s|&nbsp;| |g
    s|&amp;|\&|g
    s|&lt;|<|g
    s|&gt;|>|g
    s|&quot;|"|g
    s|&#39;|\x27|g
    s|&apos;|\x27|g
    s|[[:space:]]*$||
  ' | awk '
    # Trim leading blank lines and collapse runs of blank lines
    BEGIN { started = 0; blank_run = 0 }
    {
      if ($0 ~ /^[[:space:]]*$/) {
        if (started) blank_run++
        next
      }
      if (blank_run > 0) print ""
      blank_run = 0
      started = 1
      print
    }
  '
  # kcov-skip-end
}

# ---------------------------------------------------------------------------
# _first_paragraph  (stdin -> stdout)
#   Returns text up to the first blank line; collapses internal whitespace.
# ---------------------------------------------------------------------------
_first_paragraph() {
  # kcov-skip-start
  awk '
    BEGIN { RS = "" }
    NR == 1 { gsub(/[[:space:]]+/, " "); sub(/^ /, ""); sub(/ $/, ""); print; exit }
  '
  # kcov-skip-end
}

# ---------------------------------------------------------------------------
# _split_legacy_htmldesc <html>
#   Splits a legacy htmlDesc into "why" and "how to fix" parts at the first
#   "How to fix" heading. Works for both single-line and multi-line HTML.
#   Returns JSON {whyHtml, howToFixHtml}.
# ---------------------------------------------------------------------------
_split_legacy_htmldesc() {
  local html="$1"
  local why_part="$html"
  local fix_part=""

  # Insert a control-character marker at the "How to fix" heading.
  local marker
  marker=$(printf '\1SPLIT\1')
  local marked
  marked=$(printf '%s' "$html" | sed -E "s|<[Hh][1-6][^>]*>[[:space:]]*[Hh]ow to fix[^<]*</[Hh][1-6]>|${marker}|")

  if [[ "$marked" == *"$marker"* ]]; then
    why_part="${marked%%"${marker}"*}"
    fix_part="${marked#*"${marker}"}"
  fi

  jq -n --arg whyHtml "$why_part" --arg howToFixHtml "$fix_part" \
    '{whyHtml: $whyHtml, howToFixHtml: $howToFixHtml}'
}

# ---------------------------------------------------------------------------
# _build_section_object <why_html_raw> <how_to_fix_html_raw>
#   Builds the normalized section JSON with HTML / plain text / first-paragraph
#   variants for both the "why" and "how to fix" content.
# ---------------------------------------------------------------------------
_build_section_object() {
  local why_raw="$1"
  local fix_raw="$2"

  local why_html why_text why_short
  local fix_html fix_text fix_short

  why_html=$(printf '%s' "$why_raw" | _normalize_rule_html)
  why_text=$(printf '%s' "$why_raw" | _html_to_text)
  why_short=$(printf '%s' "$why_text" | _first_paragraph)

  fix_html=$(printf '%s' "$fix_raw" | _normalize_rule_html)
  fix_text=$(printf '%s' "$fix_raw" | _html_to_text)
  fix_short=$(printf '%s' "$fix_text" | _first_paragraph)

  # kcov-skip-start
  jq -n \
    --arg whyHtml "$why_html" \
    --arg whyText "$why_text" \
    --arg whyTextShort "$why_short" \
    --arg howToFixHtml "$fix_html" \
    --arg howToFixText "$fix_text" \
    --arg howToFixTextShort "$fix_short" \
    '{
      whyHtml: $whyHtml,
      whyText: $whyText,
      whyTextShort: $whyTextShort,
      howToFixHtml: $howToFixHtml,
      howToFixText: $howToFixText,
      howToFixTextShort: $howToFixTextShort
    }'
  # kcov-skip-end
}

# ---------------------------------------------------------------------------
# fetch_rule_details <rule_key>
#   Fetches /api/rules/show and returns normalized JSON. Caches by rule_key.
# ---------------------------------------------------------------------------
fetch_rule_details() {
  local rule_key="${1:-}"
  if [[ -z "$rule_key" ]]; then
    echo "{}"
    return 0
  fi

  if [[ -n "${_RULE_CACHE[$rule_key]:-}" ]]; then
    echo "${_RULE_CACHE[$rule_key]}"
    return 0
  fi
  if [[ -n "${_RULE_NEGATIVE[$rule_key]:-}" ]]; then
    return 1
  fi

  local key_enc
  key_enc=$(printf '%s' "$rule_key" | jq -sRr @uri)

  local response
  if ! response=$(sonar_api_get "rules/show?key=${key_enc}"); then
    log_error "Failed to fetch rule details for ${rule_key}"
    _RULE_NEGATIVE[$rule_key]=1
    return 1
  fi

  if ! _validate_json_response "rules/show?key=${key_enc}" "$response"; then
    log_error "Failed to parse rule details for ${rule_key}"
    _RULE_NEGATIVE[$rule_key]=1
    return 1
  fi

  local why_raw fix_raw
  # kcov-skip-start
  why_raw=$(echo "$response" | jq -r '
    if (.rule.descriptionSections // []) | length > 0 then
      [.rule.descriptionSections[]?
        | select(.key == "root_cause" or .key == "introduction")
        | .content] | join("\n")
    else
      ""
    end
  ')
  fix_raw=$(echo "$response" | jq -r '
    if (.rule.descriptionSections // []) | length > 0 then
      [.rule.descriptionSections[]?
        | select(.key == "how_to_fix")
        | .content] | join("\n")
    else
      ""
    end
  ')
  # kcov-skip-end

  if [[ -z "$why_raw" && -z "$fix_raw" ]]; then
    local html_desc
    html_desc=$(echo "$response" | jq -r '.rule.htmlDesc // ""')
    if [[ -n "$html_desc" ]]; then
      local split
      split=$(_split_legacy_htmldesc "$html_desc")
      why_raw=$(echo "$split" | jq -r '.whyHtml // ""')
      fix_raw=$(echo "$split" | jq -r '.howToFixHtml // ""')
    fi
  fi

  local normalized
  normalized=$(_build_section_object "$why_raw" "$fix_raw")

  _RULE_CACHE[$rule_key]="$normalized"
  echo "$normalized"
}

# ---------------------------------------------------------------------------
# fetch_hotspot_details <hotspot_key> <hotspot_rule_key>
# ---------------------------------------------------------------------------
fetch_hotspot_details() {
  local hotspot_key="${1:-}"
  local rule_key="${2:-}"

  if [[ -z "$hotspot_key" ]]; then
    echo "{}"
    return 0
  fi

  if [[ -n "$rule_key" && -n "${_HOTSPOT_RULE_CACHE[$rule_key]:-}" ]]; then
    echo "${_HOTSPOT_RULE_CACHE[$rule_key]}"
    return 0
  fi

  local hs_enc
  hs_enc=$(printf '%s' "$hotspot_key" | jq -sRr @uri)

  local response
  if ! response=$(sonar_api_get "hotspots/show?hotspot=${hs_enc}"); then
    log_error "Failed to fetch hotspot details for ${hotspot_key}"
    return 1
  fi

  if ! _validate_json_response "hotspots/show?hotspot=${hs_enc}" "$response"; then
    log_error "Failed to parse hotspot details for ${hotspot_key}"
    return 1
  fi

  local risk_raw why_raw fix_raw
  risk_raw=$(echo "$response" | jq -r '.rule.riskDescription // ""')
  why_raw=$(echo "$response" | jq -r '.rule.vulnerabilityDescription // ""')
  fix_raw=$(echo "$response" | jq -r '.rule.fixRecommendations // ""')

  local base_obj risk_text normalized
  base_obj=$(_build_section_object "$why_raw" "$fix_raw")
  risk_text=$(printf '%s' "$risk_raw" | _html_to_text)
  normalized=$(echo "$base_obj" | jq --arg riskText "$risk_text" '. + {riskText: $riskText}')

  if [[ -n "$rule_key" ]]; then
    _HOTSPOT_RULE_CACHE[$rule_key]="$normalized"
  fi
  echo "$normalized"
}

# ---------------------------------------------------------------------------
# fetch_source_snippet <component_key> <start_line> <end_line> <context>
#   Fetches /api/sources/raw, slices the requested window in-memory.
# ---------------------------------------------------------------------------
fetch_source_snippet() {
  local component_key="${1:-}"
  local start_line="${2:-}"
  local end_line="${3:-}"
  local context="${4:-3}"

  if [[ -z "$component_key" || -z "$start_line" || "$start_line" == "null" ]]; then
    echo "{}"
    return 0
  fi
  if [[ -z "$end_line" || "$end_line" == "null" ]]; then
    end_line="$start_line"
  fi
  if ! [[ "$start_line" =~ ^[0-9]+$ ]] || ! [[ "$end_line" =~ ^[0-9]+$ ]]; then
    echo "{}"
    return 0
  fi
  if ! [[ "$context" =~ ^[0-9]+$ ]]; then
    context=3
  fi

  if [[ -n "${_COMPONENT_NEGATIVE[$component_key]:-}" ]]; then
    echo "{}"
    return 0
  fi

  local raw
  if [[ -n "${_SOURCE_CACHE[$component_key]:-}" ]]; then
    raw="${_SOURCE_CACHE[$component_key]}"
  else
    local comp_enc
    comp_enc=$(printf '%s' "$component_key" | jq -sRr @uri)
    if ! raw=$(sonar_api_get "sources/raw?key=${comp_enc}"); then
      log_error "Failed to fetch source snippet for ${component_key}"
      _COMPONENT_NEGATIVE[$component_key]=1
      return 1
    fi
    if [[ "${#raw}" -le "$_SOURCE_CACHE_MAX_BYTES" ]]; then
      _SOURCE_CACHE[$component_key]="$raw"
    fi
  fi

  local snip_start=$((start_line - context))
  [[ "$snip_start" -lt 1 ]] && snip_start=1
  local snip_end=$((end_line + context))

  # kcov-skip-start
  printf '%s' "$raw" | awk -v s="$snip_start" -v e="$snip_end" \
                           -v hs="$start_line" -v he="$end_line" '
    BEGIN { printf "{\"startLine\":%d,\"endLine\":%d,\"lines\":[", s, e; sep="" }
    {
      if (NR < s) next
      if (NR > e) { exit }
      line = $0
      gsub(/\\/, "\\\\", line)
      gsub(/"/,  "\\\"", line)
      gsub(/\t/, "\\t", line)
      gsub(/\r/, "", line)
      hl = (NR >= hs && NR <= he) ? "true" : "false"
      printf "%s{\"n\":%d,\"text\":\"%s\",\"highlighted\":%s}", sep, NR, line, hl
      sep = ","
    }
    END { printf "]}\n" }
  '
  # kcov-skip-end
}

# ---------------------------------------------------------------------------
# enrich_issue_objects <issues_json_array>
# ---------------------------------------------------------------------------
enrich_issue_objects() {
  local issues_json="${1:-[]}"

  local rule_mode="${INCLUDE_RULE_DESCRIPTIONS:-}"
  local with_snippets="${INCLUDE_CODE_SNIPPETS:-false}"
  local context="${SNIPPET_CONTEXT:-3}"

  if [[ -z "$rule_mode" && "$with_snippets" != "true" ]]; then
    echo "$issues_json"
    return 0
  fi

  local count
  count=$(echo "$issues_json" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    echo "$issues_json"
    return 0
  fi

  if [[ -n "$rule_mode" ]]; then
    local rk
    while IFS= read -r rk; do
      if [[ -n "$rk" && "$rk" != "null" ]]; then
        if ! fetch_rule_details "$rk" >/dev/null; then
          log_error "Failed to prefetch rule details for ${rk}"
          return 1
        fi
      fi
    done < <(echo "$issues_json" | jq -r '[.[].rule] | unique[]?')
  fi

  local tmp_out
  tmp_out=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_out'" RETURN

  local issue issue_key rule_key component start_line end_line rule_obj snippet_obj
  while IFS= read -r issue; do
    issue_key=$(echo "$issue" | jq -r '.key // ""')
    rule_key=$(echo "$issue" | jq -r '.rule // ""')
    component=$(echo "$issue" | jq -r '.component // ""')
    start_line=$(echo "$issue" | jq -r '(.startLine // .line) // empty')
    end_line=$(echo "$issue" | jq -r '(.endLine // .startLine // .line) // empty')

    rule_obj="{}"
    if [[ -n "$rule_mode" ]]; then
      if ! rule_obj=$(fetch_rule_details "$rule_key"); then
        log_error "Failed to enrich issue ${issue_key:-<unknown>} with rule details"
        return 1
      fi
    fi

    snippet_obj="{}"
    if [[ "$with_snippets" == "true" && -n "$start_line" ]]; then
      if ! snippet_obj=$(fetch_source_snippet "$component" "$start_line" "$end_line" "$context"); then
        log_error "Failed to enrich issue ${issue_key:-<unknown>} with source snippet"
        return 1
      fi
    fi

    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$rule_obj"; then
      log_error "Invalid rule details payload while enriching issue ${issue_key:-<unknown>}"
      log_error "Payload: ${rule_obj}"
      return 1
    fi
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$snippet_obj"; then
      log_error "Invalid source snippet payload while enriching issue ${issue_key:-<unknown>}"
      log_error "Payload: ${snippet_obj}"
      return 1
    fi

    # kcov-skip-start
    echo "$issue" | jq -c \
      --argjson rule "$rule_obj" \
      --argjson snippet "$snippet_obj" \
      '. + (
        (if ($rule | type) == "object" and ($rule | length) > 0 then {ruleDescription: $rule} else {} end)
        + (if ($snippet | type) == "object" and ($snippet | length) > 0 then {codeSnippet: $snippet} else {} end)
      )' >> "$tmp_out"
    # kcov-skip-end
  done < <(echo "$issues_json" | jq -c '.[]')

  jq -s '.' "$tmp_out"
}

# ---------------------------------------------------------------------------
# enrich_hotspot_objects <hotspots_json_array>
# ---------------------------------------------------------------------------
enrich_hotspot_objects() {
  local hotspots_json="${1:-[]}"

  local rule_mode="${INCLUDE_RULE_DESCRIPTIONS:-}"
  local with_snippets="${INCLUDE_CODE_SNIPPETS:-false}"
  local context="${SNIPPET_CONTEXT:-3}"

  if [[ -z "$rule_mode" && "$with_snippets" != "true" ]]; then
    echo "$hotspots_json"
    return 0
  fi

  local count
  count=$(echo "$hotspots_json" | jq 'length')
  if [[ "$count" -eq 0 ]]; then
    echo "$hotspots_json"
    return 0
  fi

  local tmp_out
  tmp_out=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$tmp_out'" RETURN

  local hotspot hs_key rule_key component start_line end_line rule_obj snippet_obj
  while IFS= read -r hotspot; do
    hs_key=$(echo "$hotspot" | jq -r '.key // ""')
    rule_key=$(echo "$hotspot" | jq -r '.rule // ""')
    component=$(echo "$hotspot" | jq -r '.component // ""')
    start_line=$(echo "$hotspot" | jq -r '(.startLine // .line) // empty')
    end_line=$(echo "$hotspot" | jq -r '(.endLine // .startLine // .line) // empty')

    rule_obj="{}"
    if [[ -n "$rule_mode" && -n "$hs_key" ]]; then
      if ! rule_obj=$(fetch_hotspot_details "$hs_key" "$rule_key"); then
        log_error "Failed to enrich hotspot ${hs_key} with rule details"
        return 1
      fi
    fi

    snippet_obj="{}"
    if [[ "$with_snippets" == "true" && -n "$start_line" ]]; then
      if ! snippet_obj=$(fetch_source_snippet "$component" "$start_line" "$end_line" "$context"); then
        log_error "Failed to enrich hotspot ${hs_key} with source snippet"
        return 1
      fi
    fi

    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$rule_obj"; then
      log_error "Invalid hotspot rule details payload while enriching hotspot ${hs_key}"
      log_error "Payload: ${rule_obj}"
      return 1
    fi
    if ! jq -e 'type == "object"' >/dev/null 2>&1 <<< "$snippet_obj"; then
      log_error "Invalid source snippet payload while enriching hotspot ${hs_key}"
      log_error "Payload: ${snippet_obj}"
      return 1
    fi

    # kcov-skip-start
    echo "$hotspot" | jq -c \
      --argjson rule "$rule_obj" \
      --argjson snippet "$snippet_obj" \
      '. + (
        (if ($rule | type) == "object" and ($rule | length) > 0 then {ruleDescription: $rule} else {} end)
        + (if ($snippet | type) == "object" and ($snippet | length) > 0 then {codeSnippet: $snippet} else {} end)
      )' >> "$tmp_out"
    # kcov-skip-end
  done < <(echo "$hotspots_json" | jq -c '.[]')

  jq -s '.' "$tmp_out"
}
