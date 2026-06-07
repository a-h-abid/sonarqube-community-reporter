# Agents Instructions

## Repo Map

- `scripts/sonar-report.sh`: main CLI, orchestration, config precedence, `--dry-run`.
- `scripts/wait-for-analysis.sh`: standalone SonarQube CE task polling.
- `scripts/lib/api.sh`: HTTP helpers, pagination, shared logging helpers.
- `scripts/lib/config.sh`: config parsing and safe key allowlist (`is_allowed_key`).
- `scripts/lib/metrics.sh`: quality gate, issues, hotspots, rules, and measures collection.
- `scripts/lib/report-*.sh`: JSON, Markdown, HTML, CSV, PDF, XLSX, and ODS generators.
- `scripts/lib/notify.sh`: webhook delivery.
- `scripts/lib/rule-details.sh`: optional rule description and source snippet enrichment.

## Shell Patterns

- Target Bash 4.4+. `scripts/sonar-report.sh` enforces this; avoid Bash 5+ features.
- Every script uses `#!/usr/bin/env bash`, `set -euo pipefail`, and double-quoted variables.
- Function names use `snake_case`; function-scoped variables use `local`.
- Environment variables and constants are `UPPERCASE`; sourced-script path variables are prefixed, such as `_METRICS_SCRIPT_DIR`.
- Put `# shellcheck source=...` before every `source` command.
- Library files in `scripts/lib/` must use a unique source guard:

```bash
[[ -n "${_API_SH_LOADED:-}" ]] && return 0
_API_SH_LOADED=1
```

- Functions return `1` on failure; only `main()` should `exit`.
- Validate required inputs early and chain critical commands with `|| return 1` or `|| exit 1`.
- Use `log_info`, `log_ok`, `log_warn`, and `log_error` from `api.sh`; do not use bare `echo` for status messages.
- Create temp files under the project `tmp/` directory when it is available; if the configured/project temp directory cannot be created or is not writable (for example on a read-only mount), fall back to `${TMPDIR:-/tmp}/sonar-report`, and clean temp files with traps such as `trap 'rm -f "$tmpfile"' RETURN`.

## Validation

Run ShellCheck after shell changes:

```bash
shellcheck scripts/sonar-report.sh scripts/wait-for-analysis.sh scripts/lib/*.sh
```

Run all tests after code changes:

```bash
bash tests/run_tests.sh
```

Use sequential mode when debugging order-sensitive failures:

```bash
BATS_JOBS=1 bash tests/run_tests.sh
```

Run coverage when behavior or report generation changes; CI enforces 92% minimum:

```bash
bash tests/run_coverage.sh --min-coverage 92
```

Tests must be parallel-safe: isolate mutable state in `setup()` with unique `mktemp` paths or ports, and never depend on test order. Integration tests use `--dry-run` plus PATH sandboxing for fake `wkhtmltopdf`, `xvfb-run`, and spreadsheet tools.

## Project Constraints

- Config precedence is CLI flags, environment variables, config file (`.sonar-report.yml` or `sonar-report.conf`), then defaults.
- Never commit secrets or tokens; use environment variables or `.env` files (`.env` is gitignored).
- `reports/` is gitignored except `.gitkeep`; generated reports do not belong in commits.
- Keep `templates/report.html.tpl` and `scripts/lib/report-html.sh` in sync.
- PDF generation depends on `wkhtmltopdf` and `xvfb`; spreadsheet generation depends on external converters. Handle missing tools gracefully.
- `ssconvert --merge-to` names XLSX/ODS sheets from CSV filenames, including the `.csv` suffix.
- Rule enrichment (`--include-rule-descriptions`) is optional and must degrade cleanly on API errors or insufficient permissions.
- Put large reusable jq/awk programs in `scripts/lib/jq/` or `scripts/lib/awk/`; wrap smaller embedded programs with `# kcov-skip-start` / `# kcov-skip-end` when coverage would be misleading.
- Keep awk portable for mawk: prefer `length()` checks over interval quantifiers like `{32,128}`.
