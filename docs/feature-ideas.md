# Feature Ideas

[← Back to README](../README.md)

A backlog of candidate features, written down for later evaluation. **Nothing here is committed or scheduled.** Each entry records what the feature is, why it could be worth doing, a rough approach, and what would need checking first.

The API endpoints and parameters named below are from memory of the SonarQube Web API and have not been tested against a server for these purposes. Verify them against your SonarQube version (`/web_api` on the instance) before building on them.

Effort is a rough guess: **S** = a day or less, **M** = a few days, **L** = a week or more.

## Summary

| # | Idea | Area | Effort |
|---|------|------|--------|
| 1 | [Pull request comment](#1-pull-request-comment-githubgitlab) | Integration | M |
| 2 | [File-level hotspots ("worst files")](#2-file-level-hotspots-worst-files) | Report content | M |
| 3 | [Historical trend from SonarQube](#3-historical-trend-from-sonarqube) | Report content | M |
| 4 | [Project auto-discovery for portfolios](#4-project-auto-discovery-for-portfolios) | Portfolio | S |
| 5 | [Handle the 10,000-issue cap](#5-handle-the-10000-issue-cap) | Reliability | M |
| 6 | [Issue ageing and ownership](#6-issue-ageing-and-ownership) | Report content | M |
| 7 | [Security compliance view (OWASP / CWE)](#7-security-compliance-view-owasp--cwe) | Report content | M |
| 8 | [Custom thresholds (local quality gate)](#8-custom-thresholds-local-quality-gate) | CI enforcement | S |
| 9 | [Accepted and false-positive issues](#9-accepted-and-false-positive-issues) | Report content | S |
| 10 | [Richer notifications](#10-richer-notifications) | Integration | M |
| 11 | [More machine-readable formats](#11-more-machine-readable-formats) | Integration | S each |
| 12 | [First-class GitHub Action](#12-first-class-github-action) | Integration | S |
| 13 | [Parallel fetching within a single project](#13-parallel-fetching-within-a-single-project) | Performance | M |
| 14 | [Temp files left behind after a run](#14-temp-files-left-behind-after-a-run) | Reliability | S |

Already done and therefore not listed: HTTP retries/timeouts and bounded concurrency for portfolio and enrichment fetches (see [Reliability & Performance](usage.md#reliability--performance)).

---

## 1. Pull request comment (GitHub/GitLab)

**What.** A `--pr-comment` mode that posts one comment on a pull/merge request with the quality gate status, metric deltas, and the top new issues, and updates that same comment on later runs instead of adding new ones.

**Why.** Pull request decoration is a paid SonarQube feature. This tool already produces Markdown and trend data, so most of the content exists. It follows the same pitch as the portfolio report: a core paid capability brought to the Community edition.

**Approach.**
- Render a compact Markdown body (a shorter variant of the existing Markdown report).
- Post through the GitHub or GitLab REST API; find the previous comment by a hidden HTML marker and edit it.
- Reuse `--compare-with` for deltas and the `newCode` tag for "new issues".

**To check.**
- Community edition has no branch or PR analysis, so the numbers describe whatever branch was last scanned into the project. The comment must say that plainly.
- Needs a second credential (`GITHUB_TOKEN` / GitLab token) and the PR number from the CI environment.
- Comment size limits on both platforms; cap the issue list.

## 2. File-level hotspots ("worst files")

**What.** A report section listing the top N files by lowest coverage, highest duplication, highest complexity, and most issues.

**Why.** Reports today carry project-level measures and a flat issue list. "Which files should we fix first" is usually the first question a reader has, and the current report does not answer it.

**Approach.**
- Fetch per-file measures with `measures/component_tree` (`qualifiers=FIL`, sorted by metric, limited page size).
- Derive "most issues per file" from the issue list already fetched; no extra call needed.
- New `--top-files N` flag (default off, or a small default such as 10).
- Add the section to every generator and to the portfolio drill-down.

**To check.**
- Cost: one sorted call per metric, per project. Should be acceptable with a small page size.
- Whether very small files should be excluded (a 5-line file at 0% coverage is noise).

## 3. Historical trend from SonarQube

**What.** A `--history 30d` (or "last N analyses") section showing how the key metrics moved over time, with inline SVG sparklines in HTML/PDF.

**Why.** `--compare-with` needs a previously saved JSON file as baseline. In ephemeral CI that means storing and restoring an artifact. SonarQube already keeps the history, so the trend can be had with no stored state.

**Approach.**
- `measures/search_history` for the tracked metrics over the requested window.
- Render a table of first/last/min/max plus a sparkline per metric (plain SVG, no JavaScript, so it survives the PDF conversion).
- Keep `--compare-with` as is; the two answer different questions (exact two-point diff versus a time series).

**To check.**
- How much history the server retains (housekeeping settings purge old snapshots).
- Whether `wkhtmltopdf` renders inline SVG reliably.
- SonarCloud support for the endpoint.

## 4. Project auto-discovery for portfolios

**What.** Select portfolio projects without listing every key: `--all-projects`, `--project-pattern 'svc-*'`, `--project-tags backend`.

**Why.** Portfolio mode needs each key spelled out, which goes stale as projects are added or renamed.

**Approach.**
- `components/search_projects` (supports tag filters and works with Browse permission) or `projects/search` (needs admin).
- Apply the glob pattern client-side, then feed the resulting list into the existing portfolio path.
- Log the resolved list, and add `--max-projects` as a guard against an accidental 500-project run.

**To check.**
- Which endpoint works with a normal user token on the supported versions.
- Behaviour for projects that were never analysed (skip with a warning rather than fail).

## 5. Handle the 10,000-issue cap

**What.** Detect when a project has more open issues than SonarQube will return, and fetch them anyway.

**Why.** `issues/search` returns at most 10,000 results. The tool pages 20 × 500 and then logs a "max pages" warning, but the report itself gives no sign that the issue list is incomplete. Summary counts stay correct (they come from facets); only the detail list is cut.

**Approach.**
- Compare the reported total with what was fetched.
- When over the cap, split the query into slices that each stay under it (by severity, then type, then directory or creation-date range) and merge the results.
- At minimum, stamp the report with a visible "issue list truncated at 10,000" note, the same way display filters are announced.

**To check.**
- The simplest slicing key that reliably keeps each slice under the cap on very large projects.
- Runtime and memory for 50k+ issues in bash/jq; may need a hard `--max-issues-fetched` limit.

## 6. Issue ageing and ownership

**What.** Age buckets (under 7 days, under 30, under 90, older), a per-author or per-assignee breakdown, and an "oldest unresolved blockers" list.

**Why.** Counts alone do not show whether debt is being paid down or just accumulating, or who is carrying it.

**Approach.**
- `creationDate` is already collected. Add `author`, `assignee`, and `tags` to the issue projection in `metrics.sh` (they come back in the same `issues/search` response).
- Compute the buckets and breakdowns in jq and add a summary table per format.

**To check.**
- Privacy: author values are usually SCM e-mail addresses. Make the per-person breakdown opt-in and consider a masking option.
- Report-data JSON gains fields; confirm older saved files still render under `--dry-run`.

## 7. Security compliance view (OWASP / CWE)

**What.** Vulnerabilities and hotspots grouped by OWASP Top 10 category, CWE, and similar standards.

**Why.** Auditors are a natural audience for the PDF, and SonarQube's own security reports are a paid feature.

**Approach.**
- Request the standards facets on `issues/search` (for example `owaspTop10-2021`, `cwe`) and group hotspots by their `securityCategory`, which is already collected.
- Render one table per standard; opt-in via `--include-security-standards`.

**To check.**
- Facet names differ between SonarQube versions; needs a fallback when a facet is rejected.
- Coverage is only as good as the rule metadata — rules without a mapping must be shown as "unmapped", not dropped.

## 8. Custom thresholds (local quality gate)

**What.** `--fail-on 'coverage<80,blocker>0,new_bugs>0'` — exit 1 when any condition holds, independent of the server-side gate.

**Why.** Lets a pipeline enforce stricter rules than the shared quality gate without admin rights on SonarQube, and lets different pipelines use different bars for the same project.

**Approach.**
- Parse `metric operator value` triples; evaluate against the measures and severity counts already in the report data.
- Show the evaluated conditions in the report next to the server gate conditions.
- Works under `--dry-run` since it needs no API call.

**To check.**
- The set of supported metric names and how to name severity counts.
- Portfolio semantics: per project, or against the aggregated totals.

## 9. Accepted and false-positive issues

**What.** A count, and optionally a section, for issues resolved as Accepted / Won't Fix / False Positive.

**Why.** Only `OPEN,CONFIRMED` issues are fetched, so anything waived is invisible. For an audit, what was waived and by whom matters as much as what is open.

**Approach.**
- One extra `issues/search` call with the resolved statuses, facets only for the count; a full fetch behind an opt-in flag for the detailed list.

**To check.**
- Status and resolution names changed across versions (`WONTFIX` became `ACCEPTED`); needs to handle both.

## 10. Richer notifications

**What.** Better webhook messages and more control over when they are sent.

**Why.** The webhook currently posts one plain `text` blob after every run.

**Approach.**
- Slack Block Kit and Teams Adaptive Card payloads, selected by `--notify-format slack|teams|generic`.
- Include trend deltas when `--compare-with` is used.
- `--notify-on always|failure|regression` to cut noise.
- Optional e-mail via SMTP with the PDF attached.

**To check.**
- Teams has been retiring the old incoming-webhook connectors in favour of Workflows; confirm which payload shape is current.
- E-mail brings a new dependency (`curl` SMTP or `msmtp`) and credentials handling.

## 11. More machine-readable formats

**What.** Additional output formats aimed at other tools:

| Format | Consumer |
|--------|----------|
| GitLab Code Quality JSON | GitLab merge request widget (the GitLab counterpart of SARIF for GitHub) |
| JUnit XML | Jenkins and other CI test reporters — one test case per quality gate condition |
| Prometheus text format | Grafana dashboards, via node_exporter's textfile collector or a Pushgateway |

**Why.** Each one puts SonarQube results into a place teams already look, with no new UI.

**Approach.** Each is a new `report-*.sh` generator driven by a jq program, following the existing SARIF generator. They are independent and can be done one at a time.

**To check.**
- GitLab Code Quality needs a stable fingerprint per issue (the SonarQube issue key should do) and has a size limit on the artifact.
- Prometheus label cardinality: label by project and branch only, never by issue.

## 12. First-class GitHub Action

**What.** An `action.yml` in this repository so that workflows can use `uses: a-h-abid/sonarqube-community-reporter@v1` with typed inputs, plus a job summary written to `$GITHUB_STEP_SUMMARY`.

**Why.** Today there is only a workflow example to copy and adapt. A real action is easier to adopt and to keep up to date.

**Approach.**
- Docker-based action wrapping the published GHCR image; inputs map one-to-one to the existing environment variables.
- Outputs: quality gate status and the report directory path.
- Write the Markdown report (or a shortened form) to the step summary.

**To check.**
- Versioning and tagging policy (`v1` moving tag).
- Whether to publish to the GitHub Marketplace.

## 13. Parallel fetching within a single project

**What.** Run a single project's API calls concurrently.

**Why.** `--concurrency` currently parallelises across portfolio projects and across enrichment lookups. Within one project, the six top-level fetches (quality gate, measures, issue summary, hotspot summary, issues, hotspots) and the pages of `issues/search` still run one after another. For a large single project this is the remaining bulk of the run time.

**Approach.**
- Run the independent top-level fetches through the existing `run_parallel` helper.
- For pagination, fetch page 1 to learn the total, then fetch the remaining pages in parallel and merge in page order.

**To check.**
- Must stay within the same `CONCURRENCY` budget when combined with portfolio mode (workers already run with `CONCURRENCY=1`, so this needs a deliberate decision).
- Output must remain identical to the sequential path, as it is for the existing parallel code.

## 14. Temp files left behind after a run

**What.** Each live run leaves a handful of `sonar-report.*` files in `tmp/` (about six per project when enrichment is on).

**Why.** Harmless on an ephemeral CI runner, but they accumulate on a long-lived host or a mounted volume.

**Likely cause (not confirmed).** Cleanup relies on `trap ... RETURN`. In bash that trap is shell-wide rather than per function, so a nested function that sets its own RETURN trap replaces the caller's, and the caller's file is never removed.

**Approach.**
- Replace the RETURN traps with explicit cleanup at each exit path, or
- create one per-run temp directory up front and remove it from a single EXIT trap in `main()`. This is simpler and also covers interrupted runs.

**To check.**
- Confirm the cause with a minimal reproduction before changing every call site.
- `AGENTS.md` currently recommends the RETURN-trap pattern; update it if the approach changes.
