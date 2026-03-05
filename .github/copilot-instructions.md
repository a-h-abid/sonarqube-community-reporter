# Copilot Instructions

## Project Overview

This is a **Bash-based** tool that generates analysis reports from **SonarQube Community Edition** via the Web API. It outputs reports in JSON, Markdown, HTML, and PDF formats, designed for dashboards, audits, and CI/CD pipelines.

## Tech Stack

- **Language:** Bash 4.0+ (100% shell scripts — no other languages)
- **Dependencies:** `curl` (API calls), `jq` 1.6+ (JSON processing), `wkhtmltopdf` + `xvfb` (optional PDF generation)
- **Containerization:** Docker + Docker Compose v2+
- **CI/CD:** GitHub Actions (`.github/workflows/sonar-report.yml`) and GitLab CI (`.gitlab-ci.yml`)

## Project Structure

```
scripts/
├── sonar-report.sh          # Main entrypoint — argument parsing, orchestration
├── wait-for-analysis.sh     # CE task polling logic
└── lib/
    ├── api.sh               # Shared API helpers (auth, HTTP, pagination, logging)
    ├── metrics.sh            # Data fetching (measures, issues, hotspots)
    ├── report-json.sh        # JSON report generator
    ├── report-md.sh          # Markdown report generator
    ├── report-html.sh        # HTML report generator
    └── report-pdf.sh         # PDF report generator
templates/
└── report.html.tpl           # Styled HTML template (used by report-html.sh)
```

## Coding Conventions

### Shell Script Standards

- **Shebang:** Always use `#!/usr/bin/env bash`
- **Strict mode:** Always set `set -euo pipefail` at the top of every script
- **Quoting:** Always double-quote variables: `"$var"`, `"${var}"`

### Source Guard Pattern

Library scripts in `scripts/lib/` use a source guard to prevent redundant re-sourcing:

```bash
[[ -n "${_API_SH_LOADED:-}" ]] && return 0
_API_SH_LOADED=1
```

Each lib file must have its own unique guard variable (e.g., `_API_SH_LOADED`, `_METRICS_SH_LOADED`).

### Variable Naming

- **UPPERCASE** for environment variables and configuration constants (e.g., `SONAR_URL`, `REPORT_FORMATS`)
- **Prefixed `_SCRIPT_DIR` variables** to avoid collisions when scripts are sourced together (e.g., `_METRICS_SCRIPT_DIR`, `_REPORT_HTML_SCRIPT_DIR`)
- **`local`** keyword for all function-scoped variables

### Functions

- Use `snake_case` for function names
- Use **`# shellcheck source=`** directives before every `source` command
- Clean up temporary files with `trap 'rm -f "$tmpfile"' RETURN`

### Logging

Use the shared logging helpers from `scripts/lib/api.sh`:

- `log_info` — informational messages (cyan)
- `log_ok` — success messages (green)
- `log_warn` — warnings (yellow)
- `log_error` — errors (red, stderr)

Do **not** use bare `echo` for status messages — always use the appropriate log helper.

### Error Handling

- Functions should `return 1` on failure (not `exit 1`), except in `main()`
- Validate required parameters early and provide clear error messages
- Use `|| return 1` or `|| exit 1` after critical commands

## Linting

Use [ShellCheck](https://www.shellcheck.net/) to lint all shell scripts:

```bash
shellcheck scripts/sonar-report.sh scripts/wait-for-analysis.sh scripts/lib/*.sh
```

## Testing

There is no test infrastructure in this project. When making changes, manually verify behavior by running the scripts with appropriate arguments or by reviewing generated output.

## Building and Running

### Local

```bash
./scripts/sonar-report.sh \
  --url http://localhost:9000 \
  --token YOUR_TOKEN \
  --project-key my-project \
  --formats json,md,html,pdf \
  --wait
```

### Docker

```bash
docker build -t sonar-report-tool .
docker run --rm \
  -e SONAR_URL=http://host.docker.internal:9000 \
  -e SONAR_TOKEN=squ_xxxxx \
  -e SONAR_PROJECT_KEY=my-project \
  -e REPORT_FORMATS=json,md,html,pdf \
  -v $(pwd)/reports:/reports \
  sonar-report-tool --wait
```

## Important Notes

- Never commit secrets or tokens — use environment variables or `.env` files (`.env` is gitignored)
- The `reports/` directory is gitignored — only `.gitkeep` is tracked
- PDF generation depends on `wkhtmltopdf` and `xvfb`; always handle the case where they are unavailable
- The HTML report uses `templates/report.html.tpl` as its template — keep the template and generator in sync
