# ==============================================================================
# md-portfolio.jq — Render a portfolio (multi-project) report as Markdown.
#
# Input : a portfolio report object (.metadata.reportType == "portfolio").
# Output: the full Markdown document as raw text (jq -r).
# ==============================================================================

def esc: (. // "") | tostring | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def component_path: (. // "") | split(":") | last // "";
def n($x): ($x // 0) | (tonumber? // 0);

# minutes -> human-readable technical-debt string (mirrors api.sh format_duration)
def fmt_duration:
  (. // 0) | (tonumber? // 0) | floor as $m
  | if   $m < 60   then "\($m)min"
    elif $m < 1440 then "\(($m/60)|floor)h \($m%60)min"
    else "\(($m/1440)|floor)d \((($m%1440)/60)|floor)h" end;

def line_display(v):
  (v.startLine // v.line) as $s | (v.endLine // v.line) as $e
  | if ($s != null) and ($e != null) and (($e|tonumber? // 0) > ($s|tonumber? // 0))
    then "\($s)-\($e)" else ((v.line // v.startLine // "N/A") | tostring) end;

.metadata as $m
| .portfolio as $p
| $p.totals as $t
| $p.aggregates as $agg

# --- Header -----------------------------------------------------------------
| "# Portfolio Analysis Report\n\n"
+ "## Portfolio Overview\n\n"
+ "| Field | Value |\n|-------|-------|\n"
+ (if (($m.organization // "") != "") then "| **Organization** | " + ($m.organization | esc) + " |\n" else "" end)
+ "| **Projects** | " + ($m.projectCount | tostring) + " |\n"
+ "| **Report Date** | " + ($m.reportDate | esc) + " |\n"
+ "| **SonarQube URL** | " + ($m.sonarUrl | esc) + " |\n"
+ "\n---\n\n"

# --- Quality gates ----------------------------------------------------------
+ "## Quality Gates\n\n"
+ "| Status | Count |\n|--------|-------|\n"
+ "| ✅ Passed | " + ($t.gatesPassed | tostring) + " |\n"
+ "| ❌ Failed | " + ($t.gatesFailed | tostring) + " |\n"
+ "| ⚠️ Other | " + ($t.gatesOther | tostring) + " |\n"
+ "\n---\n\n"

# --- Organization totals ----------------------------------------------------
+ "## Organization Totals\n\n"
+ "### Issues by Type\n\n"
+ "| Type | Count |\n|------|-------|\n"
+ "| 🐛 Bugs | " + ($t.issues.byType.BUG | tostring) + " |\n"
+ "| 🔒 Vulnerabilities | " + ($t.issues.byType.VULNERABILITY | tostring) + " |\n"
+ "| 🔧 Code Smells | " + ($t.issues.byType.CODE_SMELL | tostring) + " |\n"
+ "| **Total** | " + ($t.issues.total | tostring) + " |\n\n"
+ "### Issues by Severity\n\n"
+ "| Severity | Count |\n|----------|-------|\n"
+ "| ⛔ Blocker | " + ($t.issues.bySeverity.BLOCKER | tostring) + " |\n"
+ "| 🔴 Critical | " + ($t.issues.bySeverity.CRITICAL | tostring) + " |\n"
+ "| 🟠 Major | " + ($t.issues.bySeverity.MAJOR | tostring) + " |\n"
+ "| 🔵 Minor | " + ($t.issues.bySeverity.MINOR | tostring) + " |\n"
+ "| ⚪ Info | " + ($t.issues.bySeverity.INFO | tostring) + " |\n\n"
+ "### Security Hotspots\n\n"
+ "| Status | Count |\n|--------|-------|\n"
+ "| Total | " + ($t.hotspots.total | tostring) + " |\n"
+ "| 🔍 To Review | " + ($t.hotspots.toReview | tostring) + " |\n"
+ "| ✅ Reviewed | " + ($t.hotspots.reviewed | tostring) + " |\n\n"
+ "### Size & Debt\n\n"
+ "| Metric | Value |\n|--------|-------|\n"
+ "| Lines of Code | " + ($t.ncloc | tostring) + " |\n"
+ "| Technical Debt | " + ($t.sqale_index | fmt_duration) + " |\n"
+ "| Weighted Coverage | " + ((if $agg.coverage == null then "N/A" else ($agg.coverage | tostring) + "%" end)) + " |\n"
+ "| Weighted Duplications | " + ((if $agg.duplicated_lines_density == null then "N/A" else ($agg.duplicated_lines_density | tostring) + "%" end)) + " |\n"
+ "\n---\n\n"

# --- Worst offenders --------------------------------------------------------
+ "## Worst Offenders\n\n"
+ "_Ranked by failed quality gate, then Blocker+Critical issues, then total issues._\n\n"
+ "| Rank | Project | Quality Gate | Blocker+Critical | Total Issues |\n"
+ "|------|---------|--------------|------------------|--------------|\n"
+ ([ $p.worstOffenders | to_entries[] |
     "| " + ((.key + 1) | tostring) + " | " + (.value.projectName | esc)
     + " (`" + (.value.projectKey | esc) + "`) | " + (.value.gateStatus | esc)
     + " | " + (.value.blockerCritical | tostring) + " | " + (.value.totalIssues | tostring) + " |"
   ] | join("\n"))
+ "\n\n---\n\n"

# --- Per-project comparison -------------------------------------------------
+ "## Per-Project Comparison\n\n"
+ "| Project | Quality Gate | Bugs | Vulnerabilities | Code Smells | Coverage | Duplications | LOC |\n"
+ "|---------|--------------|------|-----------------|-------------|----------|--------------|-----|\n"
+ ([ $p.projects[] |
     "| " + ((.metadata.projectName // .metadata.projectKey) | esc)
     + " (`" + (.metadata.projectKey | esc) + "`) | " + ((.qualityGate.status // "UNKNOWN") | esc)
     + " | " + (n(.measures.bugs) | tostring)
     + " | " + (n(.measures.vulnerabilities) | tostring)
     + " | " + (n(.measures.code_smells) | tostring)
     + " | " + ((.measures.coverage // "N/A") | tostring) + "%"
     + " | " + ((.measures.duplicated_lines_density // "N/A") | tostring) + "%"
     + " | " + (n(.measures.ncloc) | tostring) + " |"
   ] | join("\n"))
+ "\n\n---\n\n"

# --- Per-project drill-down -------------------------------------------------
+ "## Project Details\n\n"
+ ([ $p.projects[] |
     (.metadata.projectName // .metadata.projectKey) as $name |
     "### " + ($name | esc) + " (`" + (.metadata.projectKey | esc) + "`)\n\n"
     + "**Quality Gate: " + ((.qualityGate.status // "UNKNOWN") | esc) + "**\n\n"
     + "#### Issues\n\n"
     + (if ((.issues // []) | length) > 0 then
         "| Severity | Type | Component | Line | Rule | Message |\n"
         + "|----------|------|-----------|------|------|---------|\n"
         + ([ .issues[] |
             "| " + ((.severity // "?") | esc) + " | " + ((.type // "?") | esc)
             + " | " + ((.component // "") | component_path | esc)
             + " | " + line_display(.) + " | " + ((.rule // "") | esc)
             + " | " + ((.message // "") | esc) + " |"
           ] | join("\n"))
       else "_No open issues found._" end)
     + "\n\n#### Security Hotspots\n\n"
     + (if ((.hotspots // []) | length) > 0 then
         "| Status | Risk | Component | Line | Rule | Message |\n"
         + "|--------|------|-----------|------|------|---------|\n"
         + ([ .hotspots[] |
             "| " + ((.status // "?") | esc) + " | " + ((.vulnerabilityProbability // "N/A") | esc)
             + " | " + ((.component // "") | component_path | esc)
             + " | " + line_display(.) + " | " + ((.rule // "") | esc)
             + " | " + ((.message // "") | esc) + " |"
           ] | join("\n"))
       else "_No security hotspots found._" end)
   ] | join("\n\n"))
+ "\n\n---\n\n"
+ "> Report generated by [sonarqube-community-reporter](https://github.com/a-h-abid/sonarqube-community-reporter) on " + ($m.reportDate | esc) + "\n"
