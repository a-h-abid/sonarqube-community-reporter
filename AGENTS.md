# Agents Instructions

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

Always run [ShellCheck](https://www.shellcheck.net/) to lint all shell scripts, specially after any changes made:

```bash
shellcheck scripts/sonar-report.sh scripts/wait-for-analysis.sh scripts/lib/*.sh
```

## Testing

Always run the tests for code changes, all of them must pass.

```bash
bash tests/run_tests.sh
```

Run Code Coverage, target minimum 90% coverage.

```bash
bash tests/run_coverage.sh --min-coverage 90
```

## Important Notes

- Never commit secrets or tokens — use environment variables or `.env` files (`.env` is gitignored)
- The `reports/` directory is gitignored — only `.gitkeep` is tracked
- PDF generation depends on `wkhtmltopdf` and `xvfb`; always handle the case where they are unavailable
- The HTML report uses `templates/report.html.tpl` as its template — keep the template and generator in sync
