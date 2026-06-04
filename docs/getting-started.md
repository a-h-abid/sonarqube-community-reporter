# Getting Started

[← Back to README](../README.md)

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
| `kcov` | Any | Bash line coverage measurement (optional) |

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
