# Testing

[← Back to README](../README.md)

The repository includes a [bats](https://bats-core.readthedocs.io/) test suite (125 tests) that validates all major script functions without making real HTTP calls — all SonarQube API interactions are mocked.

## Prerequisites

Install `bats` and `jq`:

```bash
# Debian / Ubuntu
sudo apt-get install -y bats jq

# macOS
brew install bats-core jq
```

For coverage measurement, install `kcov`:

Official install instructions: https://github.com/SimonKagstrom/kcov/blob/master/INSTALL.md

```bash
# Debian / Ubuntu
sudo apt-get install -y kcov

# macOS
brew install kcov
```

## Running the Tests

```bash
bash tests/run_tests.sh
```

## Running Coverage

```bash
# Generate kcov HTML + Cobertura XML reports under reports/coverage
bash tests/run_coverage.sh

# Optional: fail if line coverage is below a threshold (CI enforces 92%)
bash tests/run_coverage.sh --min-coverage 92
```

Coverage outputs:

- `reports/coverage/index.html` — browsable HTML report
- `reports/coverage/cobertura.xml` — machine-readable coverage report

## Test Coverage

| File | Tests | What's Covered |
|------|-------|---------------|
| `tests/test_api.bats` | 40 | `rating_to_letter`, `format_duration`, `safe_jq`, `sonar_api_get` (mocked `curl`), `check_connectivity`, `sonar_api_paginated` |
| `tests/test_metrics.bats` | 31 | All `fetch_*` functions with `sonar_api_get` mocked per-test, including last analysis datetime lookup |
| `tests/test_wait_for_analysis.bats` | 18 | `extract_task_id_from_report`, `_poll_by_task_id` (including PENDING→SUCCESS transition), `_poll_by_component`, `wait_for_analysis` dispatch |
| `tests/test_main.bats` | 11 | `normalize_format`, `validate_report_formats`, `validate_params` (dry-run mode), `parse_args` (new flags) |
| `tests/test_reports.bats` | 47 | `generate_json_report`, `generate_md_report`, `generate_html_report`, `generate_csv_report` — validates file creation, content, rendered metadata, and CSV row data |
| `tests/test_notify.bats` | 12 | `send_webhook_notification` with mocked `curl` — payload structure, emoji selection, HTTP error handling |

Test fixtures (JSON files representing every SonarQube API response shape) live in `tests/fixtures/`.

The test suite also runs automatically in CI via the **Lint and Test** GitHub Actions workflow (`.github/workflows/test.yml`) on every push and pull request.
The same workflow also runs `kcov` coverage and uploads `reports/coverage/` as a workflow artifact (`coverage-report`).
