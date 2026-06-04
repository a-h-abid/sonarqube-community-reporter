# CI/CD Integration

[← Back to README](../README.md)

## GitHub Actions

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

## GitLab CI/CD

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
