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

Both `run_tests.sh` and `run_coverage.sh` parallelize across all available cores
by default (auto-detected via `nproc`), which requires GNU `parallel` to be
installed (`sudo apt-get install -y parallel`); without it they fall back to
sequential. Override the job count with `BATS_JOBS` — use `BATS_JOBS=1` for a
deterministic, sequential run when debugging a single test.

```bash
BATS_JOBS=1 bash tests/run_tests.sh   # sequential, for debugging
```

New tests must stay **parallel-safe**: isolate all mutable state in `setup()`
via `mktemp`/`mktemp -d`, never use fixed temp paths or ports, and don't depend
on execution order across tests — consistent with the existing test pattern.

Run Code Coverage, target minimum 92% coverage (aim for ~95%). CI enforces the 92% gate.

```bash
bash tests/run_coverage.sh --min-coverage 92
```

### Coverage conventions

- **Embedded `jq`/`awk`/`sed` programs and kcov:** kcov cannot mark individual
  physical lines inside a multi-line single-quoted program (e.g.
  `var=$(echo "$x" | jq '<newline>…multi-line…<newline>')`) as hit, even though
  they execute. Two patterns keep coverage honest:
  - **Large / reusable report-generator programs** live in external files under
    `scripts/lib/jq/*.jq` and `scripts/lib/awk/*.awk`, loaded with `jq -f` /
    `awk -f`. kcov does not instrument these, and they ship via the Dockerfile's
    `COPY scripts/`.
  - **Smaller embedded programs** (in `metrics.sh`, `rule-details.sh`,
    `notify.sh`, `report-pdf.sh`) are wrapped in `# kcov-skip-start` …
    `# kcov-skip-end` marker comments. `tests/run_coverage.sh` passes
    `--exclude-region='kcov-skip-start:kcov-skip-end'` on **both** the per-file
    `kcov` runs and the `kcov --merge` step (the flag is required on the merge
    too, or the regions get re-included).
- **`main()` and the entrypoint** are exercised end-to-end in
  `tests/test_integration.bats` via `--dry-run` and mocked collaborators; the PDF
  and spreadsheet tools are faked through a PATH sandbox so tests stay
  deterministic and fast.

## Important Notes

- Never commit secrets or tokens — use environment variables or `.env` files (`.env` is gitignored)
- The `reports/` directory is gitignored — only `.gitkeep` is tracked
- PDF generation depends on `wkhtmltopdf` and `xvfb`; always handle the case where they are unavailable
- The HTML report uses `templates/report.html.tpl` as its template — keep the template and generator in sync
- For any temporary files, use the `tmp/` directory in this project root, do not go output this project directory.
