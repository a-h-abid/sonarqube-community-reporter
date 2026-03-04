<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SonarQube Report — {{PROJECT_NAME}}</title>
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
      --rating-a: #00c853;
      --rating-b: #7cb342;
      --rating-c: #f9a825;
      --rating-d: #e65100;
      --rating-e: #d32f2f;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      background: var(--color-bg);
      color: var(--color-text);
      line-height: 1.6;
      padding: 24px;
      max-width: 1100px;
      margin: 0 auto;
    }
    h1 { font-size: 1.8rem; color: var(--color-heading); margin-bottom: 4px; }
    h2 { font-size: 1.3rem; color: var(--color-heading); margin: 24px 0 12px; border-bottom: 2px solid var(--color-border); padding-bottom: 6px; }
    h3 { font-size: 1.1rem; color: var(--color-muted); margin: 16px 0 8px; }
    a { color: var(--color-a); text-decoration: none; }
    a:hover { text-decoration: underline; }

    .header { display: flex; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; gap: 16px; margin-bottom: 20px; }
    .header-info { color: var(--color-muted); font-size: 0.9rem; }

    /* Quality Gate Badge */
    .qg-badge {
      display: inline-block;
      font-size: 1.2rem;
      font-weight: 700;
      padding: 10px 28px;
      border-radius: 8px;
      color: #fff;
      text-transform: uppercase;
      letter-spacing: 1px;
    }
    .qg-pass { background: var(--color-pass); }
    .qg-fail { background: var(--color-fail); }
    .qg-warn { background: var(--color-warn); }
    .qg-none { background: var(--color-muted); }

    /* Metric Cards Grid */
    .cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin: 16px 0; }
    .card {
      background: var(--color-card);
      border: 1px solid var(--color-border);
      border-radius: 8px;
      padding: 16px;
      text-align: center;
    }
    .card-label { font-size: 0.85rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.5px; }
    .card-value { font-size: 2rem; font-weight: 700; margin: 4px 0; }
    .card-sub { font-size: 0.8rem; color: var(--color-muted); }

    /* Rating badge */
    .rating {
      display: inline-block;
      width: 36px; height: 36px;
      line-height: 36px;
      text-align: center;
      border-radius: 4px;
      color: #fff;
      font-weight: 700;
      font-size: 1.2rem;
    }
    .rating-A { background: var(--rating-a); }
    .rating-B { background: var(--rating-b); }
    .rating-C { background: var(--rating-c); }
    .rating-D { background: var(--rating-d); }
    .rating-E { background: var(--rating-e); }

    /* Tables */
    table { width: 100%; border-collapse: collapse; margin: 8px 0 16px; background: var(--color-card); border-radius: 8px; overflow: hidden; }
    th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--color-border); }
    th { background: var(--color-heading); color: #fff; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; }
    tr:last-child td { border-bottom: none; }
    tr:nth-child(even) { background: #f8f9fa; }

    /* Severity badges */
    .sev { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; color: #fff; }
    .sev-BLOCKER { background: var(--color-blocker); }
    .sev-CRITICAL { background: var(--color-critical); }
    .sev-MAJOR { background: var(--color-major); color: #333; }
    .sev-MINOR { background: var(--color-minor); }
    .sev-INFO { background: var(--color-info); }

    .type-badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; background: #e3f2fd; color: #1565c0; }

    /* Footer */
    .footer { margin-top: 32px; padding-top: 12px; border-top: 1px solid var(--color-border); font-size: 0.8rem; color: var(--color-muted); text-align: center; }

    /* Conditions table status */
    .cond-ok { color: var(--color-pass); font-weight: 600; }
    .cond-error { color: var(--color-fail); font-weight: 600; }
    .cond-warn { color: var(--color-warn); font-weight: 600; }

    @media print {
      body { padding: 0; }
      .card { break-inside: avoid; }
    }
  </style>
</head>
<body>

  <!-- Header -->
  <div class="header">
    <div>
      <h1>{{PROJECT_NAME}}</h1>
      <div class="header-info">
        Project Key: <code>{{PROJECT_KEY}}</code> &nbsp;|&nbsp;
        Branch: <strong>{{BRANCH}}</strong> &nbsp;|&nbsp;
        Date: {{REPORT_DATE}}
      </div>
      <div class="header-info">
        Analysis ID: {{ANALYSIS_ID}} &nbsp;|&nbsp;
        <a href="{{SONAR_URL}}/dashboard?id={{PROJECT_KEY}}">Open in SonarQube →</a>
      </div>
    </div>
    <div>
      <span class="qg-badge {{QG_CLASS}}">Quality Gate: {{QG_STATUS}}</span>
    </div>
  </div>

  <!-- Quality Gate Conditions -->
  <h2>Quality Gate Conditions</h2>
  {{QG_CONDITIONS_TABLE}}

  <!-- Key Metrics -->
  <h2>Key Metrics</h2>
  <div class="cards">
    <div class="card">
      <div class="card-label">Bugs</div>
      <div class="card-value">{{BUGS}}</div>
      <div class="card-sub">Reliability: <span class="rating rating-{{REL_RATING}}">{{REL_RATING}}</span></div>
    </div>
    <div class="card">
      <div class="card-label">Vulnerabilities</div>
      <div class="card-value">{{VULNS}}</div>
      <div class="card-sub">Security: <span class="rating rating-{{SEC_RATING}}">{{SEC_RATING}}</span></div>
    </div>
    <div class="card">
      <div class="card-label">Code Smells</div>
      <div class="card-value">{{SMELLS}}</div>
      <div class="card-sub">Maintainability: <span class="rating rating-{{MAINT_RATING}}">{{MAINT_RATING}}</span></div>
    </div>
    <div class="card">
      <div class="card-label">Coverage</div>
      <div class="card-value">{{COVERAGE}}%</div>
      <div class="card-sub">of {{LOC}} lines</div>
    </div>
    <div class="card">
      <div class="card-label">Duplications</div>
      <div class="card-value">{{DUPLICATION}}%</div>
      <div class="card-sub">duplicated lines</div>
    </div>
    <div class="card">
      <div class="card-label">Technical Debt</div>
      <div class="card-value">{{TECH_DEBT}}</div>
      <div class="card-sub">Ratio: {{DEBT_RATIO}}%</div>
    </div>
  </div>

  <!-- Security Hotspots -->
  <h2>Security Hotspots</h2>
  <div class="cards">
    <div class="card">
      <div class="card-label">Total Hotspots</div>
      <div class="card-value">{{HOTSPOT_TOTAL}}</div>
    </div>
    <div class="card">
      <div class="card-label">To Review</div>
      <div class="card-value" style="color: var(--color-warn);">{{HOTSPOT_TO_REVIEW}}</div>
    </div>
    <div class="card">
      <div class="card-label">Reviewed</div>
      <div class="card-value" style="color: var(--color-pass);">{{HOTSPOT_REVIEWED}}</div>
    </div>
    <div class="card">
      <div class="card-label">Reviewed %</div>
      <div class="card-value">{{HOTSPOTS_REVIEWED_PCT}}%</div>
      <div class="card-sub">Security Review: <span class="rating rating-{{SEC_REVIEW_RATING}}">{{SEC_REVIEW_RATING}}</span></div>
    </div>
  </div>

  <!-- New Code Period -->
  <h2>New Code Period</h2>
  <div class="cards">
    <div class="card">
      <div class="card-label">New Bugs</div>
      <div class="card-value">{{NEW_BUGS}}</div>
    </div>
    <div class="card">
      <div class="card-label">New Vulnerabilities</div>
      <div class="card-value">{{NEW_VULNS}}</div>
    </div>
    <div class="card">
      <div class="card-label">New Code Smells</div>
      <div class="card-value">{{NEW_SMELLS}}</div>
    </div>
    <div class="card">
      <div class="card-label">New Coverage</div>
      <div class="card-value">{{NEW_COVERAGE}}%</div>
    </div>
    <div class="card">
      <div class="card-label">New Duplications</div>
      <div class="card-value">{{NEW_DUPLICATION}}%</div>
    </div>
  </div>

  <!-- Issues Summary -->
  <h2>Issues Summary</h2>
  <h3>Total Open Issues: {{TOTAL_ISSUES}}</h3>

  <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
    <div>
      <h3>By Type</h3>
      <table>
        <tr><th>Type</th><th>Count</th></tr>
        <tr><td>🐛 Bugs</td><td>{{ISSUE_BUGS}}</td></tr>
        <tr><td>🔓 Vulnerabilities</td><td>{{ISSUE_VULNS}}</td></tr>
        <tr><td>🔧 Code Smells</td><td>{{ISSUE_SMELLS}}</td></tr>
      </table>
    </div>
    <div>
      <h3>By Severity</h3>
      <table>
        <tr><th>Severity</th><th>Count</th></tr>
        <tr><td><span class="sev sev-BLOCKER">BLOCKER</span></td><td>{{SEV_BLOCKER}}</td></tr>
        <tr><td><span class="sev sev-CRITICAL">CRITICAL</span></td><td>{{SEV_CRITICAL}}</td></tr>
        <tr><td><span class="sev sev-MAJOR">MAJOR</span></td><td>{{SEV_MAJOR}}</td></tr>
        <tr><td><span class="sev sev-MINOR">MINOR</span></td><td>{{SEV_MINOR}}</td></tr>
        <tr><td><span class="sev sev-INFO">INFO</span></td><td>{{SEV_INFO}}</td></tr>
      </table>
    </div>
  </div>

  <!-- Top Issues -->
  <h2>Top Issues (Most Severe)</h2>
  {{TOP_ISSUES_TABLE}}

  <!-- Footer -->
  <div class="footer">
    Report generated by <strong>sonarqube-api-for-report</strong> on {{REPORT_DATE}}
  </div>

</body>
</html>
