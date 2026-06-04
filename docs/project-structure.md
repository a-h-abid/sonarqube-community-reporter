# Project Structure

[← Back to README](../README.md)

```
├── docker-compose.yml                # SonarQube CE + PostgreSQL
├── Dockerfile                        # Report tool Docker image
├── .env.example                      # Environment variable template
├── scripts/
│   ├── sonar-report.sh               # Main entrypoint
│   ├── wait-for-analysis.sh          # CE task polling
│   └── lib/
│       ├── api.sh                    # API helpers (auth, HTTP, pagination)
│       ├── metrics.sh                # Data fetching (measures, issues, hotspots)
│       ├── notify.sh                 # Webhook notification helper
│       ├── report-json.sh            # JSON report generator
│       ├── report-md.sh              # Markdown report generator
│       ├── report-html.sh            # HTML report generator
│       ├── report-pdf.sh             # PDF report generator (wkhtmltopdf)
│       ├── report-spreadsheet.sh     # Shared CSV/spreadsheet helpers
│       ├── report-xlsx.sh            # XLSX report generator (ssconvert)
│       ├── report-ods.sh             # ODS report generator (ssconvert)
│       └── report-csv.sh             # CSV report generator (jq only)
├── templates/
│   └── report.html.tpl               # Styled HTML template
├── tests/
│   ├── run_tests.sh                  # Single-command test runner
│   ├── run_coverage.sh               # kcov coverage runner for bats tests
│   ├── helpers.bash                  # Shared bats helpers (counter mocks)
│   ├── test_api.bats                 # Tests for scripts/lib/api.sh
│   ├── test_metrics.bats             # Tests for scripts/lib/metrics.sh
│   ├── test_wait_for_analysis.bats   # Tests for scripts/wait-for-analysis.sh
│   ├── test_reports.bats             # Tests for report generators
│   └── fixtures/                     # JSON API response fixtures
├── .github/
│   └── workflows/
│       ├── sonar-report.yml.example  # GitHub Actions workflow (scan & report)
│       ├── test.yml                  # GitHub Actions workflow (lint & test)
│       └── publish-ghcr.yml          # GitHub Actions workflow (build/push image on tag/release)
├── .gitlab-ci.yml.example            # GitLab CI/CD pipeline
├── reports/                          # Output directory (gitignored)
│   └── .gitkeep
├── .gitignore
└── README.md
```
