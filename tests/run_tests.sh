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
# Run tests
# ---------------------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  SonarQube Report — Test Suite               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

bats \
  "${SCRIPT_DIR}/test_api.bats" \
  "${SCRIPT_DIR}/test_metrics.bats" \
  "${SCRIPT_DIR}/test_wait_for_analysis.bats" \
  "${SCRIPT_DIR}/test_main.bats" \
  "${SCRIPT_DIR}/test_reports.bats" \
  "${SCRIPT_DIR}/test_notify.bats"
