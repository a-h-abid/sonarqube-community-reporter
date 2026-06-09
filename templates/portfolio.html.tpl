<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SonarQube Portfolio Report</title>
  <style>
    :root {
      --color-pass: #2ecc71;
      --color-fail: #e74c3c;
      --color-warn: #f39c12;
      --color-bg: #f8f9fa;
      --color-card: #ffffff;
      --color-border: #dee2e6;
      --color-text: #212529;
      --color-muted: #6c757d;
      --color-heading: #343a40;
      --color-a: #1a73e8;
      --color-blocker: #d32f2f;
      --color-critical: #e65100;
      --color-major: #f9a825;
      --color-minor: #1976d2;
      --color-info: #90a4ae;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      background: var(--color-bg);
      color: var(--color-text);
      line-height: 1.6;
      padding: 24px;
      max-width: 1280px;
      margin: 0 auto;
    }
    h1 { font-size: 1.8rem; color: var(--color-heading); margin-bottom: 4px; }
    h2 { font-size: 1.3rem; color: var(--color-heading); margin: 24px 0 12px; border-bottom: 2px solid var(--color-border); padding-bottom: 6px; }
    h3 { font-size: 1.1rem; color: var(--color-heading); margin: 18px 0 8px; }
    h4 { font-size: 0.95rem; color: var(--color-muted); margin: 12px 0 6px; text-transform: uppercase; letter-spacing: 0.5px; }
    a { color: var(--color-a); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-size: 0.85em; color: var(--color-muted); }
    .mono { font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-size: 0.84rem; }

    .header { margin-bottom: 20px; }
    .header-info { color: var(--color-muted); font-size: 0.9rem; }

    /* Metric cards */
    .cards { margin: 16px -8px; }
    .cards::after { content: ""; display: table; clear: both; }
    .card-wrap { float: left; width: 25%; padding: 0 8px 16px; }
    .cards-5 .card-wrap { width: 20%; }
    .card {
      background: var(--color-card);
      border: 1px solid var(--color-border);
      border-radius: 8px;
      padding: 16px;
      text-align: center;
      min-height: 110px;
    }
    .card-label { font-size: 0.85rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.5px; }
    .card-value { font-size: 2rem; font-weight: 700; margin: 4px 0; }
    .card-sub { font-size: 0.8rem; color: var(--color-muted); }

    /* Tables */
    .table-shell {
      width: 100%; max-width: 100%; overflow-x: auto;
      margin: 8px 0 16px; border: 1px solid var(--color-border);
      border-radius: 8px; background: var(--color-card);
    }
    table { width: 100%; border-collapse: collapse; background: var(--color-card); }
    th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--color-border); }
    th { background: var(--color-heading); color: #fff; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; }
    tr:last-child td { border-bottom: none; }
    tr:nth-child(even) { background: #f8f9fa; }

    /* Quality-gate pill */
    .qg-pill { display: inline-block; padding: 2px 10px; border-radius: 4px; font-size: 0.75rem; font-weight: 700; color: #fff; text-transform: uppercase; letter-spacing: 0.5px; }
    .qg-pass { background: var(--color-pass); }
    .qg-fail { background: var(--color-fail); }
    .qg-warn { background: var(--color-warn); }
    .qg-none { background: var(--color-muted); }

    /* Severity badges */
    .sev { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; color: #fff; }
    .sev-BLOCKER { background: var(--color-blocker); }
    .sev-CRITICAL { background: var(--color-critical); }
    .sev-MAJOR { background: var(--color-major); color: #333; }
    .sev-MINOR { background: var(--color-minor); }
    .sev-INFO { background: var(--color-info); }

    .project-section { margin-bottom: 28px; padding-bottom: 8px; border-bottom: 1px dashed var(--color-border); }

    .footer { margin-top: 32px; padding-top: 12px; border-top: 1px solid var(--color-border); font-size: 0.8rem; color: var(--color-muted); text-align: center; }
  </style>
</head>
<body>

  <!-- Header -->
  <div class="header">
    <h1>SonarQube Portfolio Report</h1>
    <div class="header-info">
      {{ORGANIZATION_ROW}}
      Projects: <strong>{{PROJECT_COUNT}}</strong> &nbsp;|&nbsp;
      Date: {{REPORT_DATE}} &nbsp;|&nbsp;
      <a href="{{SONAR_URL}}">Open SonarQube →</a>
    </div>
  </div>

  <!-- Quality Gates -->
  <h2>Quality Gates</h2>
  <div class="cards">
    <div class="card-wrap"><div class="card">
      <div class="card-label">Projects</div>
      <div class="card-value">{{PROJECT_COUNT}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Passed</div>
      <div class="card-value" style="color: var(--color-pass);">{{GATES_PASSED}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Failed</div>
      <div class="card-value" style="color: var(--color-fail);">{{GATES_FAILED}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Other</div>
      <div class="card-value" style="color: var(--color-muted);">{{GATES_OTHER}}</div>
    </div></div>
  </div>

  <!-- Organization Totals -->
  <h2>Organization Totals</h2>
  <div class="cards cards-5">
    <div class="card-wrap"><div class="card">
      <div class="card-label">Bugs</div>
      <div class="card-value">{{TOTAL_BUGS}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Vulnerabilities</div>
      <div class="card-value">{{TOTAL_VULNS}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Code Smells</div>
      <div class="card-value">{{TOTAL_SMELLS}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Total Issues</div>
      <div class="card-value">{{TOTAL_ISSUES}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Hotspots</div>
      <div class="card-value">{{TOTAL_HOTSPOTS}}</div>
      <div class="card-sub">{{HOTSPOTS_TO_REVIEW}} to review</div>
    </div></div>
  </div>
  <div class="cards cards-5">
    <div class="card-wrap"><div class="card">
      <div class="card-label">Lines of Code</div>
      <div class="card-value">{{TOTAL_LOC}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Technical Debt</div>
      <div class="card-value">{{TECH_DEBT}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Weighted Coverage</div>
      <div class="card-value">{{AVG_COVERAGE}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Weighted Duplications</div>
      <div class="card-value">{{AVG_DUPLICATION}}</div>
    </div></div>
    <div class="card-wrap"><div class="card">
      <div class="card-label">Blocker + Critical</div>
      <div class="card-value">{{SEV_BLOCKER_CRITICAL}}</div>
    </div></div>
  </div>

  <!-- Worst Offenders -->
  <h2>Worst Offenders</h2>
  <p class="header-info">Ranked by failed quality gate, then Blocker+Critical issues, then total issues.</p>
  {{WORST_OFFENDERS_TABLE}}

  <!-- Per-Project Comparison -->
  <h2>Per-Project Comparison</h2>
  {{COMPARISON_TABLE}}

  <!-- Project Details -->
  <h2>Project Details</h2>
  {{PER_PROJECT_SECTIONS}}

  <!-- Footer -->
  <div class="footer">
    Report generated by <strong>sonarqube-community-reporter</strong> on {{REPORT_DATE}}
  </div>

</body>
</html>
