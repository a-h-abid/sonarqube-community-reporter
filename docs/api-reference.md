# SonarQube API Reference

[← Back to README](../README.md)

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
| `GET /api/rules/show` | Rule descriptions (only when `--include-rule-descriptions` is set) |
| `GET /api/hotspots/show` | Hotspot rule descriptions (only when `--include-rule-descriptions` is set) |
| `GET /api/sources/raw` | Source code for affected lines (only when `--include-code-snippets` is set) |
| `GET /api/qualitygates/get_by_project` | Quality gate name (only when `--include-quality-gate-name` is set) |
| `GET /api/qualityprofiles/search` | Quality profiles applied (only when `--include-quality-profiles` is set) |

Full API documentation is available at: `http://YOUR_SONARQUBE/web_api`
