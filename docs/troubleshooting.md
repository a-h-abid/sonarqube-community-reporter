# Troubleshooting

[← Back to README](../README.md)

## SonarQube won't start

```bash
# Check logs
docker compose logs sonarqube

# Most common: vm.max_map_count too low
sudo sysctl -w vm.max_map_count=524288
docker compose restart sonarqube
```

## "Token authentication failed"

- Ensure the token hasn't expired
- Token must be of type **User Token** or **Global Analysis Token**
- Verify the token works: `curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:9000/api/authentication/validate`

## "No analysis has ever been run"

Run a SonarQube scan first. The report tool reads results from previous analyses — it doesn't perform the scan itself.

## wkhtmltopdf issues

If PDF generation fails:
- The Docker image includes `xvfb` for headless rendering
- On bare metal, try: `apt-get install -y wkhtmltopdf xvfb`
- Alternatively, skip PDF: `--formats json,md,html`

## API rate limiting

The tool uses efficient faceted queries. If you hit limits:
- Increase `POLL_INTERVAL` to reduce CE polling frequency
- The issues summary uses `ps=1` with facets (single request, not bulk fetching)
