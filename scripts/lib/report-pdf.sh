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

  wkhtmltopdf \
    --quiet \
    --page-size A4 \
    --orientation Portrait \
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
    "$html_file" \
    "$filepath" 2>/dev/null || {
      log_error "wkhtmltopdf failed for ${html_file}"
      return 1
    }

  log_ok "PDF report  → ${filepath}"
  echo "$filepath"
}
