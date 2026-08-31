#!/usr/bin/env bash
# ==============================================================================
# run_tests.sh — Run the full test suite using bats
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Check dependencies
# ---------------------------------------------------------------------------
if ! command -v bats &>/dev/null; then
  echo "[ERROR] bats is not installed."
  echo "        Install: sudo apt-get install -y bats"
  echo "              or: brew install bats-core"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "[ERROR] jq is not installed."
  echo "        Install: sudo apt-get install -y jq"
  exit 1
fi

# ---------------------------------------------------------------------------
# Parallelism — run tests across all available cores when a parallelizer is
# present. Override with BATS_JOBS (e.g. BATS_JOBS=1 for sequential debugging).
# bats errors if --jobs is passed without GNU parallel/rush, so guard for it.
# ---------------------------------------------------------------------------
JOBS="${BATS_JOBS:-$(nproc 2>/dev/null || echo 4)}"
BATS_PARALLEL=()
if [[ "$JOBS" -gt 1 ]] && { command -v parallel &>/dev/null || command -v rush &>/dev/null; }; then
  BATS_PARALLEL=(--jobs "$JOBS")
elif [[ "$JOBS" -gt 1 ]]; then
  echo "[WARN] GNU 'parallel' not found — running tests sequentially. Install 'parallel' to speed this up." >&2
fi

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  SonarQube Report — Test Suite               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

bats "${BATS_PARALLEL[@]}" \
  "${SCRIPT_DIR}/test_api.bats" \
  "${SCRIPT_DIR}/test_metrics.bats" \
  "${SCRIPT_DIR}/test_rule_details.bats" \
  "${SCRIPT_DIR}/test_wait_for_analysis.bats" \
  "${SCRIPT_DIR}/test_main.bats" \
  "${SCRIPT_DIR}/test_filtering.bats" \
  "${SCRIPT_DIR}/test_portfolio.bats" \
  "${SCRIPT_DIR}/test_reports.bats" \
  "${SCRIPT_DIR}/test_notify.bats" \
  "${SCRIPT_DIR}/test_config.bats" \
  "${SCRIPT_DIR}/test_trend.bats" \
  "${SCRIPT_DIR}/test_integration.bats"
