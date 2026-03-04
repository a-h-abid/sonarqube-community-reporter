# ==============================================================================
# Dockerfile — SonarQube Report Tool
# ==============================================================================
# Lightweight image with bash + curl + jq + wkhtmltopdf for generating
# SonarQube analysis reports from the Web API.
#
# Build:
#   docker build -t sonar-report-tool .
#
# Run:
#   docker run --rm \
#     -e SONAR_URL=http://sonarqube:9000 \
#     -e SONAR_TOKEN=squ_xxxxx \
#     -e SONAR_PROJECT_KEY=my-project \
#     -e REPORT_FORMATS=json,md,html,pdf \
#     -v $(pwd)/reports:/reports \
#     sonar-report-tool
# ==============================================================================

FROM debian:bookworm-slim

LABEL maintainer="sonarqube-api-for-report"
LABEL description="SonarQube Analysis Report Generator"

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      curl \
      ca-certificates \
      jq \
      wkhtmltopdf \
      xvfb \
    && rm -rf /var/lib/apt/lists/*

# Create a wrapper for wkhtmltopdf with xvfb (needed for headless PDF gen)
RUN printf '#!/bin/bash\nxvfb-run -a --server-args="-screen 0, 1024x768x24" /usr/bin/wkhtmltopdf "$@"\n' \
      > /usr/local/bin/wkhtmltopdf-xvfb && \
    chmod +x /usr/local/bin/wkhtmltopdf-xvfb

# Copy scripts and templates
COPY scripts/ /opt/sonar-report/scripts/
COPY templates/ /opt/sonar-report/templates/

# Make all scripts executable
RUN chmod +x /opt/sonar-report/scripts/*.sh && \
    chmod +x /opt/sonar-report/scripts/lib/*.sh

# Default output directory
RUN mkdir -p /reports

# Set working directory
WORKDIR /opt/sonar-report

# Default environment
ENV SONAR_URL=http://localhost:9000 \
    SONAR_BRANCH="" \
    SONAR_TASK_ID="" \
    POLL_INTERVAL=5 \
    POLL_TIMEOUT=300 \
    REPORT_FORMATS="json,md,html,pdf" \
    REPORT_OUTPUT_DIR="/reports"

ENTRYPOINT ["/opt/sonar-report/scripts/sonar-report.sh"]
