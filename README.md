# SonarQube Community Reporter

Generate analysis reports from **SonarQube Community Edition** via the Web API. Outputs reports in **JSON**, **Markdown**, **HTML**, **PDF**, **XLSX**, and **ODS** formats — ready for dashboards, audits, and CI/CD pipelines.

---

## Features

- **Multi-format reports** — JSON, Markdown, HTML (styled), PDF, XLSX, ODS, and CSV with project metadata including report date, last analysis datetime, and analysis ID
- **All key metrics** — Quality Gate, bugs, vulnerabilities, code smells, coverage, duplications, technical debt, security hotspots, ratings (A–E)
- **New Code Period** — Track metrics on newly added code
- **Issues Details** — Lists all open issues with severity, type, rule, file/line details, and effort
- **Security Hotspot Details** — Lists security hotspots with rule, file/line details, risk level, and review status
- **Analysis polling** — Waits for SonarQube Compute Engine to finish before fetching results
- **Dry-run / offline mode** — Regenerate reports from a saved report data JSON file without making any API calls
- **Webhook notifications** — Post a summary (quality gate, issue counts, report list) to any Slack, Teams, or generic incoming webhook URL after generation
- **CI/CD ready** — GitHub Actions and GitLab CI/CD pipelines included
- **Docker Compose** — One-command SonarQube + PostgreSQL setup
- **Fail on gate** — Exit code 1 when quality gate fails (for CI enforcement)

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Docker + Docker Compose | v2+ (Compose Specification) | Run SonarQube and the report tool |
| `bash` | 4.0+ | Script runtime |
| `curl` | Any | API calls |
| `jq` | 1.6+ | JSON processing |
| `wkhtmltopdf` | Any | PDF generation (optional) |
| `gnumeric` (`ssconvert`) | Any | XLSX/ODS generation (optional) |
| `bats` | 1.x | Running the test suite (optional) |

---

## Quick Start

### 1. Start SonarQube

```bash
# Required kernel parameter (Linux)
sudo sysctl -w vm.max_map_count=524288

# Start SonarQube + PostgreSQL
docker compose -f docker-compose.sonarqube.yml up -d

# Wait for SonarQube to be ready (takes ~1-2 minutes)
docker compose -f docker-compose.sonarqube.yml logs -f sonarqube
# Look for: "SonarQube is operational"
```

SonarQube will be available at **http://localhost:9000** (default credentials: `admin` / `admin`).

### 2. Generate a Token

1. Log in to SonarQube → **My Account** → **Security** → **Tokens**
2. Generate a new token (type: **User Token**)
3. Copy the token value

### 3. Create a Project & Run a Scan

```bash
# Install sonar-scanner CLI (if not using Docker)
# https://docs.sonarsource.com/sonarqube/latest/analyzing-source-code/scanners/sonarscanner/

# Run scanner on your project
sonar-scanner \
  -Dsonar.projectKey=my-project \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.token=YOUR_TOKEN
```

### 4. Generate the Report

```bash
# Configure
cp .env.example .env
# Edit .env with your token and project key

# Run the report tool
./scripts/sonar-report.sh \
  --url http://localhost:9000 \
  --token YOUR_TOKEN \
  --project-key my-project \
  --formats json,md,html,pdf,xlsx,ods \
  --wait
```

Reports will be saved to `./reports/`.

---

## Usage

### CLI Options

```
./scripts/sonar-report.sh [OPTIONS]

Options:
  --url URL              SonarQube base URL         (env: SONAR_URL)
  --token TOKEN          Authentication token       (env: SONAR_TOKEN)
  --project-key KEY      Project key                (env: SONAR_PROJECT_KEY)
  --branch BRANCH        Branch name (optional)     (env: SONAR_BRANCH)
  --task-id ID           CE task ID to poll         (env: SONAR_TASK_ID)
  --formats FMT          Comma-separated formats    (env: REPORT_FORMATS)
                         Supported: json,md,html,pdf,xlsx,ods,csv
  --output-dir DIR       Output directory           (env: REPORT_OUTPUT_DIR)
  --wait                 Wait for analysis to complete
  --no-wait              Skip analysis polling (default)
  --poll-interval SECS   Seconds between polls      (env: POLL_INTERVAL)
  --poll-timeout SECS    Max wait time in seconds   (env: POLL_TIMEOUT)
  --fail-on-gate         Exit 1 if quality gate fails
  --dry-run FILE         Skip API calls; use saved report data JSON
                                                    (env: DRY_RUN_FILE)
  --notify-webhook URL   Post summary to a webhook after generation
                                                    (env: NOTIFY_WEBHOOK)
  -h, --help             Show help
```

### Environment Variables

All CLI options can be set via environment variables. Create a `.env` file from the template:

```bash
cp .env.example .env
```

### CSV Export

The `csv` format generates three plain-text CSV files — summary, issues, and hotspots — that require no additional tools beyond `jq` (already a prerequisite):

```bash
./scripts/sonar-report.sh \
  --url http://localhost:9000 \
  --token YOUR_TOKEN \
  --project-key my-project \
  --formats csv
```

Three files are written to the output directory:
- `{project_key}_{timestamp}_summary.csv` — KPI-level metrics
- `{project_key}_{timestamp}_issues.csv` — All open issues
- `{project_key}_{timestamp}_hotspots.csv` — All security hotspots

### Dry-Run / Offline Mode

Use `--dry-run FILE` to regenerate reports from a previously saved JSON report data file without making any SonarQube API calls. This is useful for iterating on report formatting or re-exporting in a different format:

```bash
# Regenerate HTML and CSV from an existing JSON report data file
./scripts/sonar-report.sh \
  --dry-run ./reports/my-project_20240601_120000.json \
  --formats html,csv \
  --output-dir ./reports/regen
```

- `SONAR_TOKEN` and `SONAR_URL` are not required in dry-run mode
- `SONAR_PROJECT_KEY` is auto-populated from the file's metadata if not set

### Webhook Notifications

Use `--notify-webhook URL` to post a summary to a Slack Incoming Webhook, Microsoft Teams Incoming Webhook, or any generic HTTP endpoint that accepts a JSON POST:

```bash
./scripts/sonar-report.sh \
  --url http://localhost:9000 \
  --token YOUR_TOKEN \
  --project-key my-project \
  --formats json,html \
  --notify-webhook https://hooks.slack.com/services/T.../B.../xxx
```

The payload is a standard `{"text": "..."}` JSON body compatible with both Slack and Teams webhooks. It includes:
- Project name, key, and branch
- Quality gate status (with ✅ / ❌ / ⚠️ emoji)
- Bug, vulnerability, code smell, and total issue counts
- Hotspot count
- Report date and SonarQube URL
- List of generated file names

The webhook is also configurable via the `NOTIFY_WEBHOOK` environment variable.

### Using Docker

```bash
# Build the report tool image
docker build -t sonar-report-tool .

# Run standalone
docker run --rm \
  -e SONAR_URL=http://host.docker.internal:9000 \
  -e SONAR_TOKEN=squ_xxxxx \
  -e SONAR_PROJECT_KEY=my-project \
  -e REPORT_FORMATS=json,md,html,pdf,xlsx,ods \
  -v $(pwd)/reports:/reports \
  sonar-report-tool --wait

# Or via Docker Compose (report service)
SONAR_TOKEN=squ_xxxxx SONAR_PROJECT_KEY=my-project \
  docker compose -f docker-compose.yml run --rm report-tool --wait
```

### Using Published GHCR Image

This repository publishes container images to GitHub Container Registry (GHCR).

Run with `latest`:

```bash
docker pull ghcr.io/a-h-abid/sonarqube-community-reporter:latest

docker run --rm \
  -e SONAR_URL=http://host.docker.internal:9000 \
  -e SONAR_TOKEN=squ_xxxxx \
  -e SONAR_PROJECT_KEY=my-project \
  -e REPORT_FORMATS=json,md,html,pdf,xlsx,ods \
  -v "$(pwd)/reports:/reports" \
  ghcr.io/a-h-abid/sonarqube-community-reporter:latest --wait
```

For specific version, [see here](https://github.com/users/a-h-abid/packages/container/package/sonarqube-community-reporter).

If the package is private, authenticate first:

```bash
echo "<GITHUB_TOKEN>" | docker login ghcr.io -u <github-username> --password-stdin
```

---

## Docker Compose Setup

This repository provides two Compose files using the modern **Compose Specification** (no `version:` key):

| File | Services |
|------|----------|
| `docker-compose.sonarqube.yml` | `sonarqube`, `db` |
| `docker-compose.yml` | `report-tool` |

Start local SonarQube stack:

```bash
docker compose -f docker-compose.sonarqube.yml up -d
```

Run the report container:

```bash
docker compose -f docker-compose.yml run --rm report-tool --wait
```

### System Requirements

SonarQube requires increased kernel limits on Linux:

```bash
# Temporary (resets on reboot)
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072

# Permanent (add to /etc/sysctl.conf)
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

---

## CI/CD Integration

### GitHub Actions

The template workflow at `.github/workflows/sonar-report.yml.example`:

1. Runs SonarQube Scanner on push/PR
2. Waits for analysis to complete
3. Generates reports in all formats
4. Uploads reports as workflow artifacts (30-day retention)
5. Posts the Markdown report as a PR comment

**Setup:**

1. Copy the template into an active workflow file:
  ```bash
  cp .github/workflows/sonar-report.yml.example .github/workflows/sonar-report.yml
  ```
2. Add repository secrets:
   - `SONAR_TOKEN` — SonarQube token
   - `SONAR_HOST_URL` — SonarQube server URL
3. Add repository variable:
   - `SONAR_PROJECT_KEY` — Project key
4. Add a `sonar-project.properties` file to your repo root (or configure in the workflow)

**Manual trigger:** Go to Actions → "SonarQube Analysis & Report" → Run workflow.

### GitLab CI/CD

The template pipeline at `.gitlab-ci.yml.example`:

1. Scans with `sonarsource/sonar-scanner-cli`
2. Generates reports with inline dependency installation
3. Stores reports as GitLab artifacts (30-day retention)

**Setup:**

1. Copy the template into an active pipeline file:
  ```bash
  cp .gitlab-ci.yml.example .gitlab-ci.yml
  ```
2. Add CI/CD variables (Settings → CI/CD → Variables):
   - `SONAR_TOKEN`
   - `SONAR_HOST_URL`
   - `SONAR_PROJECT_KEY`

The pipeline runs on:
- Merge requests
- Pushes to the default branch and `develop`
- Manual triggers via the web UI

---

## Testing

The repository includes a [bats](https://bats-core.readthedocs.io/) test suite (125 tests) that validates all major script functions without making real HTTP calls — all SonarQube API interactions are mocked.

### Prerequisites

Install `bats` and `jq`:

```bash
# Debian / Ubuntu
sudo apt-get install -y bats jq

# macOS
brew install bats-core jq
```

### Running the Tests

```bash
bash tests/run_tests.sh
```

### Test Coverage

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

---

## Report Contents

Each report includes the following sections:

### Project Information
Project name, key, branch, report date, last analysis datetime, analysis ID, and SonarQube URL.

### Quality Gate
Pass/fail status with all gate conditions (metric, actual value, threshold, comparator).

### Key Metrics
| Category | Metrics |
|----------|---------|
| **Reliability** | Bugs, Reliability Rating (A–E) |
| **Security** | Vulnerabilities, Security Rating, Hotspots Reviewed %, Security Review Rating |
| **Maintainability** | Code Smells, Maintainability Rating, Technical Debt, Debt Ratio |
| **Coverage** | Coverage %, Lines of Code |
| **Duplications** | Duplicated Lines Density % |

### New Code Period
Bugs, vulnerabilities, code smells, coverage, and duplications on newly added code.

### Issues Summary
Counts by type (Bug, Vulnerability, Code Smell) and severity (Blocker, Critical, Major, Minor, Info).

### Security Hotspots
Total count, to-review count, reviewed count, plus hotspot details including review status.

### Issues Details
All open issues sorted by severity, with file path, line number, rule, message, and effort.

---

## Project Structure

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

---

## Troubleshooting

### SonarQube won't start

```bash
# Check logs
docker compose logs sonarqube

# Most common: vm.max_map_count too low
sudo sysctl -w vm.max_map_count=524288
docker compose restart sonarqube
```

### "Token authentication failed"

- Ensure the token hasn't expired
- Token must be of type **User Token** or **Global Analysis Token**
- Verify the token works: `curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:9000/api/authentication/validate`

### "No analysis has ever been run"

Run a SonarQube scan first. The report tool reads results from previous analyses — it doesn't perform the scan itself.

### wkhtmltopdf issues

If PDF generation fails:
- The Docker image includes `xvfb` for headless rendering
- On bare metal, try: `apt-get install -y wkhtmltopdf xvfb`
- Alternatively, skip PDF: `--formats json,md,html`

### API rate limiting

The tool uses efficient faceted queries. If you hit limits:
- Increase `POLL_INTERVAL` to reduce CE polling frequency
- The issues summary uses `ps=1` with facets (single request, not bulk fetching)

---

## SonarQube API Reference

This tool uses the following SonarQube Web API endpoints:

| Endpoint | Purpose |
|----------|---------|
| `GET /api/system/status` | Health check |
| `GET /api/authentication/validate` | Token validation |
| `GET /api/ce/task` | Compute Engine task status |
| `GET /api/ce/component` | Component analysis status |
| `GET /api/qualitygates/project_status` | Quality gate result |
| `GET /api/measures/component` | Project metrics/measures |
| `GET /api/issues/search` | Issues with facets |
| `GET /api/hotspots/search` | Security hotspots |

Full API documentation is available at: `http://YOUR_SONARQUBE/web_api`

---

## Disclaimer

This project is **not affiliated with, endorsed by, or sponsored by [SonarSource](https://www.sonarsource.com/)**. SonarQube is a trademark of SonarSource SA. All trademarks and registered trademarks are the property of their respective owners.

This tool interacts with the publicly documented SonarQube Web API and does not redistribute any SonarSource code.

---

## License

[MIT](LICENSE)
