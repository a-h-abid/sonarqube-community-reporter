#!/usr/bin/env bash
# ==============================================================================
# report-pdf.sh — Generate PDF report from HTML using wkhtmltopdf
# ==============================================================================
# Source guard — prevent multiple inclusions
[[ -n "${_REPORT_PDF_SH_LOADED:-}" ]] && return 0
_REPORT_PDF_SH_LOADED=1

set -euo pipefail

_REPORT_PDF_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=api.sh
source "${_REPORT_PDF_SCRIPT_DIR}/api.sh"

# ---------------------------------------------------------------------------
# generate_pdf_report <html_file_path> <output_dir>
#   Converts an HTML report to PDF using wkhtmltopdf.
#   Requires: wkhtmltopdf installed in PATH.
# ---------------------------------------------------------------------------
generate_pdf_report() {
  local html_file="$1"
  local output_dir="$2"
  local render_html="$html_file"
  local temp_html

  # Check if wkhtmltopdf is available
  if ! command -v wkhtmltopdf &>/dev/null; then
    log_warn "wkhtmltopdf not found — skipping PDF generation"
    log_warn "Install: apt-get install -y wkhtmltopdf  OR  brew install wkhtmltopdf"
    return 0
  fi

  if [[ ! -f "$html_file" ]]; then
    log_error "HTML file not found: ${html_file}"
    return 1
  fi

  # Derive PDF filename from HTML filename
  local basename
  basename=$(basename "$html_file" .html)
  local filepath="${output_dir}/${basename}.pdf"
  mkdir -p "$output_dir"

  temp_html=$(mktemp "${TMPDIR:-/tmp}/sonar-report-pdf.XXXXXX.html")
  trap 'rm -f "$temp_html"' RETURN

  awk '
    /<\/head>/ && !inserted {
      print "  <style>"
      print "    .cards .card-wrap { width: 50% !important; clear: none !important; }"
      print "    .cards .card-wrap.pdf-row-start-2 { clear: left !important; }"
      print "  </style>"
      inserted=1
    }
    { print }
  ' "$html_file" > "$temp_html"
  render_html="$temp_html"

  wkhtmltopdf \
    --quiet \
    --page-size A4 \
    --orientation Portrait \
    --print-media-type \
    --viewport-size 1280x1024 \
    --margin-top 10mm \
    --margin-bottom 10mm \
    --margin-left 10mm \
    --margin-right 10mm \
    --encoding UTF-8 \
    --enable-local-file-access \
    --no-stop-slow-scripts \
    --footer-center "Page [page] of [topage]" \
    --footer-font-size 8 \
    --footer-spacing 5 \
    "$render_html" \
    "$filepath" 2>/dev/null || {
      log_error "wkhtmltopdf failed for ${html_file}"
      return 1
    }

  log_ok "PDF report  → ${filepath}"
  echo "$filepath"
}
