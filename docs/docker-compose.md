# Docker Compose Setup

[← Back to README](../README.md)

This repository provides two Compose files using the modern **Compose Specification** (no `version:` key):

| File | Services |
|------|----------|
| `docker-compose.sonarqube.yml` | `sonarqube`, `db` |
| `docker-compose.yml` | `report-tool` |

Start local SonarQube stack:

```bash
docker compose -f docker-compose.sonarqube.yml up -d
```

Run the report container:

```bash
docker compose -f docker-compose.yml run --rm report-tool --wait
```

## System Requirements

SonarQube requires increased kernel limits on Linux:

```bash
# Temporary (resets on reboot)
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072

# Permanent (add to /etc/sysctl.conf)
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
echo "fs.file-max=131072" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
