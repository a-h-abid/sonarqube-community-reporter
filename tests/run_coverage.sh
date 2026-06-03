#!/usr/bin/env bash
# ==============================================================================
# run_coverage.sh — Run bats tests with kcov line coverage measurement
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

COVERAGE_DIR="${REPO_ROOT}/reports/coverage"
MIN_COVERAGE=""

TEST_FILES=(
  "${SCRIPT_DIR}/test_api.bats"
  "${SCRIPT_DIR}/test_metrics.bats"
  "${SCRIPT_DIR}/test_rule_details.bats"
  "${SCRIPT_DIR}/test_wait_for_analysis.bats"
  "${SCRIPT_DIR}/test_main.bats"
  "${SCRIPT_DIR}/test_reports.bats"
  "${SCRIPT_DIR}/test_notify.bats"
  "${SCRIPT_DIR}/test_config.bats"
)

usage() {
  cat <<'EOF'
Usage: bash tests/run_coverage.sh [OPTIONS]

Options:
  --output-dir DIR        Coverage output directory (default: reports/coverage)
  --min-coverage PERCENT  Fail if overall line coverage is below PERCENT
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      COVERAGE_DIR="$2"
      shift 2
      ;;
    --min-coverage)
      MIN_COVERAGE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v bats &>/dev/null; then
  echo "[ERROR] bats is not installed." >&2
  echo "        Install: sudo apt-get install -y bats" >&2
  echo "              or: brew install bats-core" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "[ERROR] jq is not installed." >&2
  echo "        Install: sudo apt-get install -y jq" >&2
  exit 1
fi

if ! command -v kcov &>/dev/null; then
  echo "[ERROR] kcov is not installed." >&2
  echo "        Install: sudo apt-get install -y kcov" >&2
  echo "              or: brew install kcov" >&2
  exit 1
fi

if [[ -n "$MIN_COVERAGE" ]] && ! [[ "$MIN_COVERAGE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "[ERROR] --min-coverage must be a number (0-100): ${MIN_COVERAGE}" >&2
  exit 1
fi

RAW_DIR="${COVERAGE_DIR}/raw"
rm -rf "${COVERAGE_DIR}"
mkdir -p "${RAW_DIR}"

echo ""
echo "Running bats test suite with kcov..."

for test_file in "${TEST_FILES[@]}"; do
  test_name="$(basename "${test_file}" .bats)"
  echo "  - ${test_name}"

  kcov \
    --clean \
    --include-pattern="${REPO_ROOT}/scripts" \
    --exclude-pattern="${REPO_ROOT}/tests,${REPO_ROOT}/reports" \
    "${RAW_DIR}/${test_name}" \
    bats "${test_file}"
done

echo ""
echo "Merging coverage reports..."
kcov --clean --merge "${COVERAGE_DIR}" "${RAW_DIR}"/*

# kcov output layout varies by version. Prefer normalized top-level outputs.
COBERTURA_PATH=""
if [[ -f "${COVERAGE_DIR}/cobertura.xml" ]]; then
  COBERTURA_PATH="${COVERAGE_DIR}/cobertura.xml"
elif [[ -f "${COVERAGE_DIR}/kcov-merged/cobertura.xml" ]]; then
  COBERTURA_PATH="${COVERAGE_DIR}/kcov-merged/cobertura.xml"
else
  COBERTURA_PATH="$(find "${COVERAGE_DIR}" -type f -name 'cobertura.xml' | head -n1 || true)"
fi

if [[ -z "$COBERTURA_PATH" ]]; then
  echo "[ERROR] coverage file not found under: ${COVERAGE_DIR}" >&2
  exit 1
fi

if [[ "$COBERTURA_PATH" != "${COVERAGE_DIR}/cobertura.xml" ]]; then
  cp "$COBERTURA_PATH" "${COVERAGE_DIR}/cobertura.xml"
  COBERTURA_PATH="${COVERAGE_DIR}/cobertura.xml"
fi

line_rate="$(grep -o 'line-rate="[0-9.]*"' "$COBERTURA_PATH" | head -n1 | sed 's/line-rate="\([0-9.]*\)"/\1/')"
if [[ -z "$line_rate" ]]; then
  echo "[ERROR] failed to parse line-rate from cobertura.xml" >&2
  exit 1
fi

coverage_percent="$(awk -v rate="$line_rate" 'BEGIN { printf "%.2f", rate * 100 }')"

echo ""
echo "Coverage summary"
echo "  Line coverage: ${coverage_percent}%"
echo "  HTML report:   ${COVERAGE_DIR}/index.html"
echo "  XML report:    ${COVERAGE_DIR}/cobertura.xml"

if [[ -n "$MIN_COVERAGE" ]]; then
  if awk -v got="$coverage_percent" -v min="$MIN_COVERAGE" 'BEGIN { exit !(got + 0 < min + 0) }'; then
    echo "[ERROR] Coverage ${coverage_percent}% is below minimum ${MIN_COVERAGE}%" >&2
    exit 1
  fi
  echo "Minimum coverage check passed (${coverage_percent}% >= ${MIN_COVERAGE}%)"
fi
