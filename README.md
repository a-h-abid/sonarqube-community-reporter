# SonarQube Community Reporter

Generate analysis reports from **SonarQube Community Edition** via the Web API. Outputs reports in **JSON**, **Markdown**, **HTML**, **PDF**, **XLSX**, and **ODS** formats — ready for dashboards, audits, and CI/CD pipelines.

---

## Features

- **Multi-format reports** — JSON, Markdown, HTML (styled), PDF, XLSX, ODS, CSV, and SARIF 2.1 (GitHub code scanning) with project metadata including report date, last analysis datetime, and analysis ID
- **All key metrics** — Quality Gate, bugs, vulnerabilities, code smells, coverage, duplications, technical debt, security hotspots, ratings (A–E)
- **New Code Period** — Track metrics on newly added code
- **Issues Details** — Lists all open issues with severity, type, rule, file/line details, and effort
- **Security Hotspot Details** — Lists security hotspots with rule, file/line details, risk level, and review status
- **Optional enrichment** — Add rule descriptions ("Why is this an issue?" / "How to fix it") and affected code snippets to issues and hotspots (opt-in via `--include-rule-descriptions` / `--include-code-snippets`)
- **Quality Profiles & Gate (audit)** — Optionally record which Quality Profiles and Quality Gate were applied during analysis, in all report formats (opt-in via `--include-quality-profiles` / `--include-quality-gate-name`)
- **Issue display filters** — Limit which issues appear in reports by severity, type, or count (`--severity-threshold` / `--issue-types` / `--max-issues`) without changing what's fetched; summary counts still reflect the full project
- **Analysis polling** — Waits for SonarQube Compute Engine to finish before fetching results
- **Dry-run / offline mode** — Regenerate reports from a saved report data JSON file without making any API calls
- **Webhook notifications** — Post a summary (quality gate, issue counts, report list) to any Slack, Teams, or generic incoming webhook URL after generation
- **CI/CD ready** — GitHub Actions and GitLab CI/CD pipelines included
- **Docker Compose** — One-command SonarQube + PostgreSQL setup
- **Fail on gate** — Exit code 1 when quality gate fails (for CI enforcement)

---

## Documentation

| Guide | Contents |
|-------|----------|
| [Getting Started](docs/getting-started.md) | Prerequisites and a step-by-step quick start |
| [Usage](docs/usage.md) | CLI options, environment variables, config files, SonarCloud, enrichment, CSV export, dry-run, webhooks, and Docker |
| [Docker Compose Setup](docs/docker-compose.md) | Compose files, services, and system requirements |
| [CI/CD Integration](docs/ci-cd.md) | GitHub Actions and GitLab CI/CD templates |
| [Testing](docs/testing.md) | Running the bats test suite and coverage |
| [Project Structure](docs/project-structure.md) | Repository layout |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and fixes |
| [SonarQube API Reference](docs/api-reference.md) | Web API endpoints used by the tool |

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

## Disclaimer

This project is **not affiliated with, endorsed by, or sponsored by [SonarSource](https://www.sonarsource.com/)**. SonarQube is a trademark of SonarSource SA. All trademarks and registered trademarks are the property of their respective owners.

This tool interacts with the publicly documented SonarQube Web API and does not redistribute any SonarSource code.

---

## License

[MIT](LICENSE)
