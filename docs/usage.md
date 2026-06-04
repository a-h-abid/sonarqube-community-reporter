# Usage

[← Back to README](../README.md)

## CLI Options

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
  --include-rule-descriptions[=MODE]
                         Include rule "Why is this an issue?" text (all formats).
                         MODE: short (default — first paragraph) or full.
                                                    (env: INCLUDE_RULE_DESCRIPTIONS)
  --include-code-snippets
                         Include affected code snippets in HTML/PDF.
                                                    (env: INCLUDE_CODE_SNIPPETS)
  --snippet-context N    Lines of context around the affected lines (default: 3)
                                                    (env: SNIPPET_CONTEXT)
  -h, --help             Show help
```

## Environment Variables

All CLI options can be set via environment variables. Create a `.env` file from the template:

```bash
cp .env.example .env
```

## Configuration Files

As an alternative to environment variables and CLI flags, you can use configuration files to manage your settings. The tool supports two formats:

### Shell-style config: `sonar-report.conf`

```bash
# Copy and edit the example
cp sonar-report.conf.example sonar-report.conf

# Example content:
SONAR_URL=http://localhost:9000
SONAR_TOKEN=your_token_here
SONAR_PROJECT_KEY=my-project
REPORT_FORMATS=json,md,html,pdf
```

### YAML config: `.sonar-report.yml`

```yaml
# Copy and edit the example
cp .sonar-report.yml.example .sonar-report.yml

# Example content:
sonar:
  url: http://localhost:9000
  token: your_token_here
  project_key: my-project

report:
  formats: json,md,html,pdf
  output_dir: ./reports
```

### Configuration Precedence

Settings are applied in the following order (highest to lowest priority):

1. **CLI flags** — `--url`, `--token`, etc.
2. **Environment variables** — `SONAR_URL`, `SONAR_TOKEN`, etc.
3. **Config file** — `sonar-report.conf` or `.sonar-report.yml`
4. **Built-in defaults**

### Auto-detection

The tool automatically searches for config files in the project root:

- Prefers `.sonar-report.yml` if it exists
- Falls back to `sonar-report.conf` if YAML not found
- No error if neither file exists

To use a config file at a custom location:

```bash
./scripts/sonar-report.sh --config /path/to/my-config.yml
```

### Docker Usage

Mount your config file into the container:

```bash
docker run --rm \
  -v $(pwd)/.sonar-report.yml:/app/.sonar-report.yml \
  -v $(pwd)/reports:/reports \
  sonar-report-tool
```

## SonarCloud Support

The tool works with **SonarCloud** in addition to self-hosted SonarQube Community Edition.
SonarCloud is auto-detected when the URL contains `sonarcloud.io`, or you can enable it
explicitly with `--sonarcloud`.

### Key differences handled automatically

| Behaviour | SonarQube | SonarCloud |
|-----------|-----------|------------|
| `system/status` check | ✅ performed | ⏭ skipped (endpoint absent) |
| CE task polling (`--wait`) | ✅ supported | ⚠️ skipped with a warning |
| `project_analyses/search` | ✅ fetched | ⏭ skipped |
| `organization=` param | not required | required on most endpoints |

### Usage

```bash
./scripts/sonar-report.sh \
  --url https://sonarcloud.io \
  --token YOUR_SONARCLOUD_TOKEN \
  --project-key my-org_my-project \
  --organization my-org \
  --formats json,md,html \
  --output-dir ./reports
```

Or via environment variables:

```bash
export SONAR_URL=https://sonarcloud.io
export SONAR_TOKEN=YOUR_SONARCLOUD_TOKEN
export SONAR_PROJECT_KEY=my-org_my-project
export SONAR_ORGANIZATION=my-org
export REPORT_FORMATS=json,md,html

./scripts/sonar-report.sh
```

### Notes

- `--organization` / `SONAR_ORGANIZATION` is **required** when targeting SonarCloud.
- `--wait` is accepted but has no effect on SonarCloud (CE endpoints are not available); a warning is logged and execution continues normally.
- SonarCloud is auto-detected from the URL, so `--sonarcloud` is optional when using `https://sonarcloud.io`.

## Issue & Hotspot Enrichment

By default, each issue and hotspot in the report shows only the basics returned by SonarQube's search APIs — rule ID, severity, message, file, line. Enable the optional enrichment flags to make the report self-contained:

| Flag (env var) | Effect | Formats |
|---|---|---|
| `--include-rule-descriptions[=short\|full]` (`INCLUDE_RULE_DESCRIPTIONS`) | Adds **"Why is this an issue?"** / **"What's the risk?"** text on each issue and hotspot. `short` (default) shows only the first paragraph; `full` shows the entire section. | All formats |
| `--include-code-snippets` (`INCLUDE_CODE_SNIPPETS`) | Embeds the affected code lines with surrounding context. The flagged lines are highlighted. | HTML/PDF only (data also in JSON) |
| `--snippet-context N` (`SNIPPET_CONTEXT`, default `3`) | Number of context lines shown before/after the affected lines. | HTML/PDF |

When `--include-rule-descriptions` is enabled, the **"How to fix it"** section is also rendered in HTML and PDF.

Example:

```bash
./scripts/sonar-report.sh \
  --url http://localhost:9000 \
  --token YOUR_TOKEN \
  --project-key my-project \
  --include-rule-descriptions=full \
  --include-code-snippets \
  --snippet-context 5 \
  --formats html,pdf,json
```

**API cost.** Enabling these flags adds one `/api/rules/show` call per unique rule (issues) and `/api/hotspots/show` call per unique hotspot rule, plus one `/api/sources/raw` call per unique file (when snippets are on). Results are cached in-process so duplicates collapse to a single fetch. On a typical project with 200 issues across 30 rules and 50 files, expect ~85 extra API calls instead of 400.

**Permissions.** Source snippet fetching requires the token to have *Browse* permission on the project. Missing rules or unavailable source files are skipped silently with a warning to stderr — the run never aborts on enrichment failures.

**SonarQube version notes.** SonarQube 9.5+ exposes structured rule sections (`descriptionSections[]`) that cleanly separate "Why" and "How to fix"; older versions return a single `htmlDesc` and the split is heuristic.

## CSV Export

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

## Dry-Run / Offline Mode

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

## Webhook Notifications

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

## Using Docker

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

## Using Published GHCR Image

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
