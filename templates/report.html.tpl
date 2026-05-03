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
      max-width: 1280px;
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

    /* Metric Cards Layout */
    .cards {
      margin: 16px -8px;
    }
    .cards::after,
    .summary-grid::after {
      content: "";
      display: table;
      clear: both;
    }
    .card-wrap {
      float: left;
      width: 33.3333%;
      padding: 0 8px 16px;
    }
    .cards-4 .card-wrap { width: 25%; }
    .cards-5 .card-wrap { width: 20%; }
    .cards-6 .card-wrap { width: 25%; }
    .cards-4 .card-wrap:nth-child(4n + 1),
    .cards-6 .card-wrap:nth-child(4n + 1) { clear: left; }
    .cards-5 .card-wrap:nth-child(5n + 1) { clear: left; }
    .card {
      background: var(--color-card);
      border: 1px solid var(--color-border);
      border-radius: 8px;
      padding: 16px;
      text-align: center;
      height: 100%;
      min-height: 136px;
      page-break-inside: avoid;
      break-inside: avoid;
    }
    .card-label { font-size: 0.85rem; color: var(--color-muted); text-transform: uppercase; letter-spacing: 0.5px; }
    .card-value { font-size: 2rem; font-weight: 700; margin: 4px 0; }
    .card-sub { font-size: 0.8rem; color: var(--color-muted); }

    .summary-grid {
      margin: 16px -8px;
    }
    .summary-panel {
      float: left;
      width: 50%;
      padding: 0 8px 16px;
    }

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
    .table-shell {
      width: 100%;
      max-width: 100%;
      overflow-x: auto;
      margin: 8px 0 16px;
      border: 1px solid var(--color-border);
      border-radius: 8px;
      background: var(--color-card);
    }
    table { width: 100%; border-collapse: collapse; background: var(--color-card); }
    th, td { padding: 10px 14px; text-align: left; border-bottom: 1px solid var(--color-border); }
    th { background: var(--color-heading); color: #fff; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px; }
    tr:last-child td { border-bottom: none; }
    tr:nth-child(even) { background: #f8f9fa; }

    .issues-table {
      min-width: 100%;
      font-size: 0.9rem;
    }
    .issues-table th,
    .issues-table td {
      vertical-align: top;
      overflow-wrap: anywhere;
      word-break: break-word;
    }
    .issues-table thead th:nth-child(1) { width: 5%; }
    .issues-table thead th:nth-child(2) { width: 14%; }
    .issues-table thead th:nth-child(3) { width: 14%; }
    .issues-table thead th:nth-child(4) { width: 45%; }
    .issues-table thead th:nth-child(5) { width: 8%; }
    .issues-table thead th:nth-child(6) { width: 14%; }

    .issue-entry {
      break-inside: avoid;
      page-break-inside: avoid;
    }
    .issue-summary-row td {
      background: #fff;
      border-bottom: none;
      font-weight: 600;
    }
    .issue-detail-row td {
      padding-top: 0;
      background: #fcfcfd;
    }
    .issue-detail {
      border-top: 1px solid var(--color-border);
      padding-top: 10px;
    }
    .issue-detail-line + .issue-detail-line {
      margin-top: 8px;
    }
    .issue-detail-label {
      display: inline-block;
      min-width: 74px;
      margin-right: 8px;
      color: var(--color-muted);
      font-size: 0.78rem;
      font-weight: 700;
      letter-spacing: 0.4px;
      text-transform: uppercase;
    }
    .issue-detail-text,
    .issue-component-path {
      overflow-wrap: anywhere;
      word-break: break-word;
    }
    .issue-component-path {
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.84rem;
    }
    .issue-index {
      white-space: nowrap;
    }

    .hotspots-table {
      min-width: 100%;
      font-size: 0.9rem;
    }
    .hotspots-table th,
    .hotspots-table td {
      vertical-align: top;
      overflow-wrap: anywhere;
      word-break: break-word;
    }
    .hotspots-table thead th:nth-child(1) { width: 5%; }
    .hotspots-table thead th:nth-child(2) { width: 18%; }
    .hotspots-table thead th:nth-child(3) { width: 15%; }
    .hotspots-table thead th:nth-child(4) { width: 50%; }
    .hotspots-table thead th:nth-child(5) { width: 12%; }

    .hotspot-entry {
      break-inside: avoid;
      page-break-inside: avoid;
    }
    .hotspot-summary-row td {
      background: #fff;
      border-bottom: none;
      font-weight: 600;
    }
    .hotspot-detail-row td {
      padding-top: 0;
      background: #fcfcfd;
    }
    .hotspot-detail {
      border-top: 1px solid var(--color-border);
      padding-top: 10px;
    }
    .hotspot-detail-line + .hotspot-detail-line {
      margin-top: 8px;
    }
    .hotspot-detail-label {
      display: inline-block;
      min-width: 74px;
      margin-right: 8px;
      color: var(--color-muted);
      font-size: 0.78rem;
      font-weight: 700;
      letter-spacing: 0.4px;
      text-transform: uppercase;
    }
    .hotspot-detail-text,
    .hotspot-component-path {
      overflow-wrap: anywhere;
      word-break: break-word;
    }
    .hotspot-component-path {
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.84rem;
    }
    .hotspot-index {
      white-space: nowrap;
    }

    /* Severity badges */
    .sev { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; color: #fff; }
    .sev-BLOCKER { background: var(--color-blocker); }
    .sev-CRITICAL { background: var(--color-critical); }
    .sev-MAJOR { background: var(--color-major); color: #333; }
    .sev-MINOR { background: var(--color-minor); }
    .sev-INFO { background: var(--color-info); }

    .type-badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; background: #e3f2fd; color: #1565c0; }
    .status-badge { display: inline-block; padding: 2px 8px; border-radius: 4px; font-size: 0.75rem; font-weight: 600; }
    .status-reviewed { background: #e8f5e9; color: #1b5e20; }
    .status-to-review { background: #fff3cd; color: #7c5700; }
    .status-unknown { background: #eceff1; color: #455a64; }

    /* Footer */
    .footer { margin-top: 32px; padding-top: 12px; border-top: 1px solid var(--color-border); font-size: 0.8rem; color: var(--color-muted); text-align: center; }

    /* Conditions table status */
    .cond-ok { color: var(--color-pass); font-weight: 600; }
    .cond-error { color: var(--color-fail); font-weight: 600; }
    .cond-warn { color: var(--color-warn); font-weight: 600; }

    @media (max-width: 960px) {
      .cards-5 .card-wrap,
      .cards-6 .card-wrap {
        width: 33.3333%;
      }

      .cards-5 .card-wrap:nth-child(5n + 1),
      .cards-6 .card-wrap:nth-child(4n + 1) {
        clear: none;
      }

      .cards-5 .card-wrap:nth-child(3n + 1),
      .cards-6 .card-wrap:nth-child(3n + 1) {
        clear: left;
      }
    }

    @media (max-width: 720px) {
      .cards-4 .card-wrap,
      .cards-5 .card-wrap,
      .cards-6 .card-wrap,
      .summary-panel {
        width: 50%;
      }

      .cards-4 .card-wrap:nth-child(4n + 1),
      .cards-5 .card-wrap:nth-child(5n + 1),
      .cards-5 .card-wrap:nth-child(3n + 1),
      .cards-6 .card-wrap:nth-child(4n + 1),
      .cards-6 .card-wrap:nth-child(3n + 1) {
        clear: none;
      }

      .cards-4 .card-wrap:nth-child(2n + 1),
      .cards-5 .card-wrap:nth-child(2n + 1),
      .cards-6 .card-wrap:nth-child(2n + 1) {
        clear: left;
      }
    }

    @media (max-width: 520px) {
      .card-wrap,
      .summary-panel {
        width: 100%;
      }

      .card-wrap {
        clear: left;
      }
    }

    @media print {
      body { padding: 0; }
      .cards {
        margin-left: -6px;
        margin-right: -6px;
      }
      .cards-4 .card-wrap,
      .cards-5 .card-wrap,
      .cards-6 .card-wrap {
        width: 25% !important;
      }
      .card-wrap,
      .summary-panel {
        padding-left: 6px;
        padding-right: 6px;
      }
      .table-shell { overflow: visible; }
      .issues-table { font-size: 0.84rem; }
      .hotspots-table { font-size: 0.84rem; }
      .issues-table th,
      .issues-table td { padding: 8px 10px; }
      .hotspots-table th,
      .hotspots-table td { padding: 8px 10px; }
      .issues-table,
      .hotspots-table,
      .issues-table thead,
      .hotspots-table thead,
      .issues-table tbody,
      .hotspots-table tbody,
      .issues-table tr,
      .hotspots-table tr,
      .issues-table td,
      .hotspots-table td,
      .issues-table th,
      .hotspots-table th {
        display: block;
        width: 100%;
        box-sizing: border-box;
      }
      .issues-table thead,
      .hotspots-table thead {
        margin-bottom: 8px;
      }
      .issues-table thead tr,
      .hotspots-table thead tr {
        display: table;
        table-layout: fixed;
      }
      .issues-table thead th,
      .hotspots-table thead th {
        display: table-cell;
      }
      .issue-entry,
      .hotspot-entry {
        display: block;
        break-inside: avoid !important;
        page-break-inside: avoid !important;
        margin-bottom: 8px;
      }
      .issue-summary-row,
      .hotspot-summary-row {
        display: table;
        table-layout: fixed;
      }
      .issue-summary-row td,
      .hotspot-summary-row td {
        display: table-cell;
      }
      .issue-detail-row,
      .hotspot-detail-row,
      .issue-detail-row td,
      .hotspot-detail-row td {
        display: block;
      }
      .issue-summary-row td:nth-child(1) { width: 5%; }
      .issue-summary-row td:nth-child(2) { width: 14%; }
      .issue-summary-row td:nth-child(3) { width: 14%; }
      .issue-summary-row td:nth-child(4) { width: 45%; }
      .issue-summary-row td:nth-child(5) { width: 8%; }
      .issue-summary-row td:nth-child(6) { width: 14%; }
      .hotspot-summary-row td:nth-child(1) { width: 5%; }
      .hotspot-summary-row td:nth-child(2) { width: 18%; }
      .hotspot-summary-row td:nth-child(3) { width: 15%; }
      .hotspot-summary-row td:nth-child(4) { width: 50%; }
      .hotspot-summary-row td:nth-child(5) { width: 12%; }
      .issue-detail-label {
        min-width: 64px;
      }
      .hotspot-detail-label {
        min-width: 64px;
      }
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
        Last Analysis: {{LAST_ANALYSIS_DATE}} &nbsp;|&nbsp;
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
  <div class="cards cards-6">
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">Bugs</div>
      <div class="card-value">{{BUGS}}</div>
      <div class="card-sub">Reliability: <span class="rating rating-{{REL_RATING}}">{{REL_RATING}}</span></div>
    </div>
    </div>
    <div class="card-wrap">
    <div class="card">
      <div class="card-label">Vulnerabilities</div>
      <div class="card-value">{{VULNS}}</div>
      <div class="card-sub">Security: <span class="rating rating-{{SEC_RATING}}">{{SEC_RATING}}</span></div>
    </div>
    </div>
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">Code Smells</div>
      <div class="card-value">{{SMELLS}}</div>
      <div class="card-sub">Maintainability: <span class="rating rating-{{MAINT_RATING}}">{{MAINT_RATING}}</span></div>
    </div>
    </div>
    <div class="card-wrap">
    <div class="card">
      <div class="card-label">Coverage</div>
      <div class="card-value">{{COVERAGE}}%</div>
      <div class="card-sub">of {{LOC}} lines</div>
    </div>
    </div>
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">Duplications</div>
      <div class="card-value">{{DUPLICATION}}%</div>
      <div class="card-sub">duplicated lines</div>
    </div>
    </div>
    <div class="card-wrap">
    <div class="card">
      <div class="card-label">Technical Debt</div>
      <div class="card-value">{{TECH_DEBT}}</div>
      <div class="card-sub">Ratio: {{DEBT_RATIO}}%</div>
    </div>
    </div>
  </div>

  <!-- Security Hotspots -->
  <h2>Security Hotspots</h2>
  <div class="cards cards-4">
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">Total Hotspots</div>
      <div class="card-value">{{HOTSPOT_TOTAL}}</div>
    </div>
    </div>
    <div class="card-wrap">
    <div class="card">
      <div class="card-label">To Review</div>
      <div class="card-value" style="color: var(--color-warn);">{{HOTSPOT_TO_REVIEW}}</div>
    </div>
    </div>
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">Reviewed</div>
      <div class="card-value" style="color: var(--color-pass);">{{HOTSPOT_REVIEWED}}</div>
    </div>
    </div>
    <div class="card-wrap">
    <div class="card">
      <div class="card-label">Reviewed %</div>
      <div class="card-value">{{HOTSPOTS_REVIEWED_PCT}}%</div>
      <div class="card-sub">Security Review: <span class="rating rating-{{SEC_REVIEW_RATING}}">{{SEC_REVIEW_RATING}}</span></div>
    </div>
    </div>
  </div>

  <h2>Security Hotspots Details</h2>
  {{HOTSPOTS_TABLE}}

  <!-- New Code Period -->
  <h2>New Code Period</h2>
  <div class="cards cards-5">
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">New Bugs</div>
      <div class="card-value">{{NEW_BUGS}}</div>
    </div>
    </div>
    <div class="card-wrap">
    <div class="card">
      <div class="card-label">New Vulnerabilities</div>
      <div class="card-value">{{NEW_VULNS}}</div>
    </div>
    </div>
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">New Code Smells</div>
      <div class="card-value">{{NEW_SMELLS}}</div>
    </div>
    </div>
    <div class="card-wrap">
    <div class="card">
      <div class="card-label">New Coverage</div>
      <div class="card-value">{{NEW_COVERAGE}}%</div>
    </div>
    </div>
    <div class="card-wrap pdf-row-start-2">
    <div class="card">
      <div class="card-label">New Duplications</div>
      <div class="card-value">{{NEW_DUPLICATION}}%</div>
    </div>
    </div>
  </div>

  <!-- Issues Summary -->
  <h2>Issues Summary</h2>
  <h3>Total Open Issues: {{TOTAL_ISSUES}}</h3>

  <div class="summary-grid">
    <div class="summary-panel">
      <h3>By Type</h3>
      <table>
        <tr><th>Type</th><th>Count</th></tr>
        <tr><td>🐛 Bugs</td><td>{{ISSUE_BUGS}}</td></tr>
        <tr><td>🔓 Vulnerabilities</td><td>{{ISSUE_VULNS}}</td></tr>
        <tr><td>🔧 Code Smells</td><td>{{ISSUE_SMELLS}}</td></tr>
      </table>
    </div>
    <div class="summary-panel">
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

  <!-- Issues Details -->
  <h2>Issues Details</h2>
  {{ISSUES_TABLE}}

  <!-- Footer -->
  <div class="footer">
    Report generated by <strong>sonarqube-community-reporter</strong> on {{REPORT_DATE}}
  </div>

</body>
</html>
