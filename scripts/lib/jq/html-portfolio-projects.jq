# ==============================================================================
# html-portfolio-projects.jq — Per-project drill-down sections (HTML) for a
# portfolio: each project's quality gate plus compact issue and hotspot tables.
# Input: a portfolio report object. Output: HTML section markup (jq -r).
# ==============================================================================
def esc: (. // "") | tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;");
def component_path: (. // "") | split(":") | last // "";
def gate_class:
  if   . == "OK"    then "qg-pass"
  elif . == "ERROR" then "qg-fail"
  elif . == "WARN"  then "qg-warn"
  else "qg-none" end;
def line_display(v):
  (v.startLine // v.line) as $s | (v.endLine // v.line) as $e
  | if ($s != null) and ($e != null) and (($e|tonumber? // 0) > ($s|tonumber? // 0))
    then "\($s)-\($e)" else ((v.line // v.startLine // "N/A") | tostring) end;

(.portfolio.projects // []) as $projects
| ([ $projects[] |
    (.metadata.projectName // .metadata.projectKey) as $name |
    "<div class=\"project-section\">"
    + "<h3>" + ($name | esc) + " <code>" + (.metadata.projectKey | esc) + "</code> "
    + "<span class=\"qg-pill " + ((.qualityGate.status // "UNKNOWN") | gate_class) + "\">"
    + ((.qualityGate.status // "UNKNOWN") | esc) + "</span></h3>"
    + "<h4>Issues</h4>"
    + (if ((.issues // []) | length) > 0 then
        "<div class=\"table-shell\"><table><thead><tr>"
        + "<th>Severity</th><th>Type</th><th>Component</th><th>Line</th><th>Rule</th><th>Message</th>"
        + "</tr></thead><tbody>"
        + ([ .issues[] |
            "<tr><td><span class=\"sev sev-" + ((.severity // "INFO") | esc) + "\">" + ((.severity // "?") | esc) + "</span></td>"
            + "<td>" + ((.type // "?") | esc) + "</td>"
            + "<td><span class=\"mono\">" + ((.component // "") | component_path | esc) + "</span></td>"
            + "<td>" + line_display(.) + "</td>"
            + "<td>" + ((.rule // "") | esc) + "</td>"
            + "<td>" + ((.message // "") | esc) + "</td></tr>"
          ] | join(""))
        + "</tbody></table></div>"
      else "<p><em>No open issues found.</em></p>" end)
    + "<h4>Security Hotspots</h4>"
    + (if ((.hotspots // []) | length) > 0 then
        "<div class=\"table-shell\"><table><thead><tr>"
        + "<th>Status</th><th>Risk</th><th>Component</th><th>Line</th><th>Rule</th><th>Message</th>"
        + "</tr></thead><tbody>"
        + ([ .hotspots[] |
            "<tr><td>" + ((.status // "?") | esc) + "</td>"
            + "<td>" + ((.vulnerabilityProbability // "N/A") | esc) + "</td>"
            + "<td><span class=\"mono\">" + ((.component // "") | component_path | esc) + "</span></td>"
            + "<td>" + line_display(.) + "</td>"
            + "<td>" + ((.rule // "") | esc) + "</td>"
            + "<td>" + ((.message // "") | esc) + "</td></tr>"
          ] | join(""))
        + "</tbody></table></div>"
      else "<p><em>No security hotspots found.</em></p>" end)
    + "</div>"
  ] | join("\n"))
